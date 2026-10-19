extends RefCounted
## Synthetic sensors (fictional training models, not real sensor performance):
##  * radar — range/bearing/elevation with noise, periodic scans, missed detections,
##    clutter false alarms, a fictional cooperative ID reply; unaffected by darkness.
##  * eo (camera) — precise bearing/elevation, coarse range; within its identification
##    range it also reports an apparent size and a wing-beat cue. Limited by night,
##    haze and fog. Both need line of sight; buildings block both, trees block the camera.
## Observations are delivered after a random delay. Each observation carries only
## measured values. Which actor produced it is recorded separately in `truth_links`,
## which only evaluation, labelling and replay may read.

const SimRandom := preload("res://scripts/sim/sim_random.gd")

const EO_VISIBILITY_FACTOR := {"clear": 1.0, "haze": 0.6, "fog": 0.25}
const EO_NIGHT_FACTOR := 0.5
const RADAR_TREE_FACTOR := 0.7 ## radar detection probability multiplier through trees
const EO_COARSE_RANGE_FRACTION := 0.25 ## 1-sigma range error of a camera-only estimate

var config: Dictionary
var observer: Vector3
var obstacles: Array
var tick_rate := 20
## obs id -> actor id, or "clutter". Ground truth: never pass to inference code.
var truth_links := {}
var stats := {"radar_scans": 0, "eo_scans": 0, "radar_detections": 0, "eo_detections": 0, "radar_missed": 0, "eo_missed": 0, "clutter": 0, "blocked": 0}

var _radar: Dictionary
var _eo: Dictionary
var _pending: Array = [] ## observations waiting for their delivery time
var _next_id := 1
var _rng_radar: RandomNumberGenerator
var _rng_eo: RandomNumberGenerator
var _rng_clutter: RandomNumberGenerator
var _rng_delay: RandomNumberGenerator


func _init(definition: Dictionary) -> void:
	config = definition["config"]
	observer = definition["observer_position"]
	obstacles = definition["layout"]["obstacles"]
	tick_rate = int(definition["tick_rate"])
	_radar = config["sensor"]["radar"]
	_eo = config["sensor"]["eo"]
	var seed_value: int = definition["seed"]
	_rng_radar = SimRandom.stream(seed_value, "sensor-radar")
	_rng_eo = SimRandom.stream(seed_value, "sensor-eo")
	_rng_clutter = SimRandom.stream(seed_value, "sensor-clutter")
	_rng_delay = SimRandom.stream(seed_value, "sensor-delay")


## Severity (0..1) of any degradation window active at time t.
func degradation_at(t: float) -> float:
	var severity := 0.0
	for window in config["sensor"]["degradation"]:
		if t >= float(window["start_s"]) and t < float(window["end_s"]):
			severity = maxf(severity, float(window["severity"]))
	return severity


func eo_range_m() -> float:
	var factor: float = EO_VISIBILITY_FACTOR.get(config["visibility"], 1.0)
	if config["time_of_day"] == "night":
		factor *= EO_NIGHT_FACTOR
	return float(_eo["range_m"]) * factor


func eo_id_range_m() -> float:
	return minf(float(_eo["id_range_m"]), eo_range_m())


## Ground-truth geometry check used ONLY for assessment (never for inference):
## is this object genuinely available at identification quality right now? That is
## inside the camera's identification range and field of view with clear line of
## sight, or a cooperative object inside radar coverage. No randomness.
func identification_available(target: Dictionary) -> bool:
	var offset: Vector3 = target["position"] - observer
	var distance := offset.length()
	if _eo["enabled"] and distance <= eo_id_range_m() and in_eo_field_of_view(offset) and line_of_sight(observer, target["position"]) == "clear":
		return true
	if _radar["enabled"] and target["id_reply"] and distance <= float(_radar["range_m"]):
		var elevation := rad_to_deg(asin(clampf(offset.y / maxf(distance, 0.001), -1.0, 1.0)))
		return elevation <= float(_radar["max_elevation_deg"]) and line_of_sight(observer, target["position"]) != "blocked"
	return false


## True when a direction (relative to the observer) lies inside the camera's azimuth sector.
func in_eo_field_of_view(offset: Vector3) -> bool:
	var fov := float(_eo["fov_deg"])
	if fov >= 360.0:
		return true
	var bearing := rad_to_deg(atan2(offset.x, -offset.z))
	return absf(angle_difference(deg_to_rad(bearing), deg_to_rad(float(_eo["center_deg"])))) <= deg_to_rad(fov * 0.5)


func period_ticks(rate_hz: float) -> int:
	return maxi(1, int(round(tick_rate / rate_hz)))


## Runs the scans due at this tick and returns the observations delivered at it.
func update(tick: int, snapshot: Array) -> Array:
	var t := float(tick) / tick_rate
	var severity := degradation_at(t)
	if _radar["enabled"] and tick % period_ticks(_radar["rate_hz"]) == 0:
		_radar_scan(t, snapshot, severity)
	if _eo["enabled"] and tick % period_ticks(_eo["rate_hz"]) == 0:
		_eo_scan(t, snapshot, severity)
	var delivered := []
	var waiting := []
	for observation in _pending:
		if observation["t_delivered"] <= t + 1e-6:
			delivered.append(observation)
		else:
			waiting.append(observation)
	_pending = waiting
	delivered.sort_custom(func(a, b): return a["t"] < b["t"] or (a["t"] == b["t"] and a["id"] < b["id"]))
	return delivered


func _radar_scan(t: float, snapshot: Array, severity: float) -> void:
	stats["radar_scans"] += 1
	var max_range: float = _radar["range_m"]
	for target in snapshot:
		var offset: Vector3 = target["position"] - observer
		var distance := offset.length()
		if distance > max_range:
			continue
		if rad_to_deg(asin(clampf(offset.y / maxf(distance, 0.001), -1.0, 1.0))) > float(_radar["max_elevation_deg"]):
			continue
		var los := line_of_sight(observer, target["position"])
		if los == "blocked":
			stats["blocked"] += 1
			continue
		var reflect := 0.55 + 0.45 * minf(float(target["radar_reflectivity"]) / 0.4, 1.0)
		var p := float(_radar["detection_prob"]) * reflect * (1.0 - 0.5 * pow(distance / max_range, 2.0)) * (1.0 - 0.6 * severity)
		if los == "trees":
			p *= RADAR_TREE_FACTOR
		if config["environment"] == "urban":
			p *= 0.95
		if _rng_radar.randf() >= p:
			stats["radar_missed"] += 1
			continue
		stats["radar_detections"] += 1
		var noise_scale := 1.0 + 2.0 * severity
		var reply := false
		if target["id_reply"]:
			reply = _rng_radar.randf() < 0.9 * (1.0 - 0.5 * severity)
		else:
			reply = _rng_radar.randf() < 0.01
		var quality := clampf(p + _rng_radar.randfn(0.0, 0.05), 0.0, 1.0)
		_emit(_radar_measurement(t, offset, noise_scale), "radar", t, quality, severity, target["actor_id"], {"id_reply": reply})
	_add_clutter(t, severity)


func _radar_measurement(t: float, offset: Vector3, noise_scale: float) -> Dictionary:
	var distance := offset.length()
	var bearing := rad_to_deg(atan2(offset.x, -offset.z)) + _rng_radar.randfn(0.0, float(_radar["bearing_noise_deg"]) * noise_scale)
	var elevation := rad_to_deg(asin(clampf(offset.y / maxf(distance, 0.001), -1.0, 1.0))) + _rng_radar.randfn(0.0, float(_radar["elevation_noise_deg"]) * noise_scale)
	var range_sigma := float(_radar["range_noise_m"]) * noise_scale
	var measured_range := maxf(distance + _rng_radar.randfn(0.0, range_sigma), 1.0)
	return {"t": t, "bearing_deg": fposmod(bearing, 360.0), "elevation_deg": elevation, "range_m": measured_range, "range_sigma_m": range_sigma}


func _eo_scan(t: float, snapshot: Array, severity: float) -> void:
	stats["eo_scans"] += 1
	var max_range := eo_range_m()
	var id_range := eo_id_range_m()
	for target in snapshot:
		var offset: Vector3 = target["position"] - observer
		var distance := offset.length()
		if distance > max_range or not in_eo_field_of_view(offset):
			continue
		if line_of_sight(observer, target["position"]) != "clear":
			stats["blocked"] += 1
			continue
		var p := float(_eo["detection_prob"]) * (1.0 - 0.6 * pow(distance / max_range, 2.0)) * (1.0 - 0.3 * severity)
		if _rng_eo.randf() >= p:
			stats["eo_missed"] += 1
			continue
		stats["eo_detections"] += 1
		var bearing_noise := float(_eo["bearing_noise_deg"]) * (1.0 + severity)
		var range_sigma := distance * EO_COARSE_RANGE_FRACTION
		var m := {
			"t": t,
			"bearing_deg": fposmod(rad_to_deg(atan2(offset.x, -offset.z)) + _rng_eo.randfn(0.0, bearing_noise), 360.0),
			"elevation_deg": rad_to_deg(asin(clampf(offset.y / maxf(distance, 0.001), -1.0, 1.0))) + _rng_eo.randfn(0.0, bearing_noise),
			"range_m": maxf(distance + _rng_eo.randfn(0.0, range_sigma), 1.0), "range_sigma_m": range_sigma,
		}
		var extra := {"id_quality": distance <= id_range, "apparent_size_m": -1.0, "flap_detected": false}
		if extra["id_quality"]:
			extra["apparent_size_m"] = maxf(float(target["size_m"]) * (1.0 + _rng_eo.randfn(0.0, 0.15)), 0.05)
			var flapping: bool = target.get("flapping", false)
			extra["flap_detected"] = _rng_eo.randf() < (0.85 if flapping else 0.04)
		var quality := clampf(1.0 - distance / max_range + _rng_eo.randfn(0.0, 0.05), 0.0, 1.0)
		_emit(m, "eo", t, quality, severity, target["actor_id"], extra)


## False radar detections: Poisson-distributed per scan, random positions.
func _add_clutter(t: float, severity: float) -> void:
	var expected := float(config["sensor"]["clutter_per_min"]) / 60.0 / float(_radar["rate_hz"]) * (1.0 + 2.0 * severity)
	var count := 0
	var threshold := exp(-expected)
	var product := _rng_clutter.randf()
	while product > threshold and count < 10:
		count += 1
		product *= _rng_clutter.randf()
	for i in count:
		var bearing := _rng_clutter.randf_range(0.0, TAU)
		var distance := _rng_clutter.randf_range(200.0, float(_radar["range_m"]))
		var offset := Vector3(sin(bearing) * distance, _rng_clutter.randf_range(5.0, 150.0) - observer.y, -cos(bearing) * distance)
		stats["clutter"] += 1
		_emit(_radar_measurement(t, offset, 1.0 + 2.0 * severity), "radar", t, clampf(_rng_clutter.randf_range(0.2, 0.6), 0.0, 1.0), severity, "clutter", {"id_reply": false})


func _emit(measurement: Dictionary, sensor: String, t: float, quality: float, severity: float, source: String, extra: Dictionary) -> void:
	var delay_range: Array = config["sensor"]["delay_s"]
	var delay := _rng_delay.randf_range(float(delay_range[0]), float(delay_range[1])) * (1.0 + severity)
	var id := "O%06d" % _next_id
	_next_id += 1
	var observation := {
		"id": id, "sensor": sensor, "t": t, "t_delivered": snappedf(t + delay, 1.0 / tick_rate),
		"bearing_deg": measurement["bearing_deg"], "elevation_deg": measurement["elevation_deg"],
		"range_m": measurement["range_m"], "range_sigma_m": measurement["range_sigma_m"],
		"position": position_from(measurement["bearing_deg"], measurement["elevation_deg"], measurement["range_m"]),
		"quality": quality, "degraded": severity > 0.0,
		"id_reply": false, "id_quality": false, "apparent_size_m": -1.0, "flap_detected": false,
	}
	observation.merge(extra, true)
	truth_links[id] = source
	_pending.append(observation)


func position_from(bearing_deg: float, elevation_deg: float, range_m: float) -> Vector3:
	var b := deg_to_rad(bearing_deg)
	var e := deg_to_rad(elevation_deg)
	var horizontal := cos(e) * range_m
	return observer + Vector3(sin(b) * horizontal, sin(e) * range_m, -cos(b) * horizontal)


## "clear", "trees" (only trees in the way) or "blocked" (a building in the way).
func line_of_sight(from: Vector3, to: Vector3) -> String:
	var result := "clear"
	var reach := from.distance_to(to)
	for o in obstacles:
		var center: Vector3 = o["center"]
		if Vector2(center.x - from.x, center.z - from.z).length() > reach + 60.0:
			continue
		var half: Vector3 = o["size"] * 0.5
		if segment_hits_box(from, to, center - half, center + half):
			if o["kind"] == "building":
				return "blocked"
			result = "trees"
	return result


## Slab test: does the segment from a to b pass through the box [lo, hi]?
static func segment_hits_box(a: Vector3, b: Vector3, lo: Vector3, hi: Vector3) -> bool:
	var direction := b - a
	var t_min := 0.0
	var t_max := 1.0
	for axis in 3:
		if absf(direction[axis]) < 1e-9:
			if a[axis] < lo[axis] or a[axis] > hi[axis]:
				return false
			continue
		var t1 := (lo[axis] - a[axis]) / direction[axis]
		var t2 := (hi[axis] - a[axis]) / direction[axis]
		t_min = maxf(t_min, minf(t1, t2))
		t_max = minf(t_max, maxf(t1, t2))
		if t_min > t_max:
			return false
	return true
