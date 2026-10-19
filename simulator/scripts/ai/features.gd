extends RefCounted
## features-1: numeric description of one track, computed ONLY from the tracker's
## record of delivered observations plus public context (wind report, protected-zone
## geometry, other tracks). Shared by the rule engine, the ML classifier and the
## dataset generator so training and inference use identical inputs.
## A track dictionary never contains truth labels (see tracker.gd); this module must
## not be given anything else from the simulation.

const VERSION := "features-1"
const NAMES := [
	"duration_s", "hits", "radar_hits", "eo_hits", "eo_id_hits",
	"speed_mean", "speed_std", "speed_max",
	"turn_rate_mean_dps", "turn_rate_std_dps",
	"climb_abs_mean", "altitude_mean", "altitude_std",
	"straightness", "air_speed_mean", "wind_alignment",
	"quality_mean", "id_reply_fraction",
	"size_mean", "has_size", "flap_fraction",
	"neighbor_count", "in_swarm_group",
	"zone_distance_min", "zone_distance_last", "range_last",
	"degraded_fraction",
]
const MIN_SPEED_FOR_TURN := 2.0 ## m/s; heading of slower samples is mostly noise
const NEIGHBOR_DISTANCE_M := 80.0
const NEIGHBOR_SPEED_DIFF_MPS := 6.0


## Public context for one exercise: {wind: Vector3, zone_center: Vector3,
## zone_radius: float, observer: Vector3}. Built from the scenario config only.
static func context_from(definition: Dictionary) -> Dictionary:
	return {
		"wind": definition["wind"], "zone_center": definition["protected_zone"]["center"],
		"zone_radius": float(definition["protected_zone"]["radius_m"]),
		"observer": definition["observer_position"],
	}


## Returns a Dictionary name -> float for one track at time `now`.
## `others` are the other active tracks (used for the swarm-neighbour features).
static func extract(track: Dictionary, others: Array, context: Dictionary, now: float) -> Dictionary:
	var f := {}
	for name in NAMES:
		f[name] = 0.0
	var history: Array = track["history"]
	f["duration_s"] = maxf(float(track["last_update_t"]) - float(track["created_t"]), 0.0)
	f["hits"] = float(track["hits"])
	f["radar_hits"] = float(track["radar_hits"])
	f["eo_hits"] = float(track["eo_hits"])
	f["eo_id_hits"] = float(track["eo_id_hits"])
	f["quality_mean"] = float(track["quality_sum"]) / maxf(float(track["hits"]), 1.0)
	f["id_reply_fraction"] = float(track["id_replies"]) / maxf(float(track["radar_hits"]), 1.0)
	f["degraded_fraction"] = float(track["degraded_hits"]) / maxf(float(track["hits"]), 1.0)
	var sizes: Array = track["sizes"]
	if not sizes.is_empty():
		var total := 0.0
		for s in sizes:
			total += float(s)
		f["size_mean"] = total / sizes.size()
		f["has_size"] = 1.0
		f["flap_fraction"] = float(track["flaps"]) / maxf(float(track["eo_id_hits"]), 1.0)

	var wind: Vector3 = context["wind"]
	var speeds := []
	var climbs := []
	var altitudes := []
	var air_speeds := []
	var alignment := 0.0
	var aligned_samples := 0
	var turns := []
	var path := 0.0
	for i in history.size():
		var sample: Dictionary = history[i]
		var v: Vector3 = sample["velocity"]
		var horizontal := Vector2(v.x, v.z)
		speeds.append(horizontal.length())
		climbs.append(absf(v.y))
		altitudes.append((sample["position"] as Vector3).y)
		air_speeds.append(Vector2(v.x - wind.x, v.z - wind.z).length())
		if horizontal.length() > 0.5 and Vector2(wind.x, wind.z).length() > 0.5:
			alignment += horizontal.normalized().dot(Vector2(wind.x, wind.z).normalized())
			aligned_samples += 1
		if i > 0:
			var previous: Dictionary = history[i - 1]
			var dt := float(sample["t"]) - float(previous["t"])
			path += (sample["position"] as Vector3).distance_to(previous["position"])
			var pv: Vector3 = previous["velocity"]
			if dt >= 0.15 and horizontal.length() > MIN_SPEED_FOR_TURN and Vector2(pv.x, pv.z).length() > MIN_SPEED_FOR_TURN:
				turns.append(absf(rad_to_deg(Vector2(pv.x, pv.z).angle_to(horizontal))) / dt)
	if not speeds.is_empty():
		f["speed_mean"] = _mean(speeds)
		f["speed_std"] = _std(speeds)
		f["speed_max"] = speeds.max()
		f["climb_abs_mean"] = _mean(climbs)
		f["altitude_mean"] = _mean(altitudes)
		f["altitude_std"] = _std(altitudes)
		f["air_speed_mean"] = _mean(air_speeds)
	if aligned_samples > 0:
		f["wind_alignment"] = alignment / aligned_samples
	if not turns.is_empty():
		f["turn_rate_mean_dps"] = _mean(turns)
		f["turn_rate_std_dps"] = _std(turns)
	if history.size() >= 2 and path > 1.0:
		var first: Vector3 = history[0]["position"]
		var last: Vector3 = history[-1]["position"]
		f["straightness"] = clampf(first.distance_to(last) / path, 0.0, 1.0)

	var position: Vector3 = track["position"]
	var center: Vector3 = context["zone_center"]
	var radius: float = context["zone_radius"]
	var minimum := INF
	for sample in history:
		var p: Vector3 = sample["position"]
		minimum = minf(minimum, Vector2(p.x - center.x, p.z - center.z).length())
	f["zone_distance_min"] = (minimum if minimum < INF else Vector2(position.x - center.x, position.z - center.z).length()) / radius
	f["zone_distance_last"] = Vector2(position.x - center.x, position.z - center.z).length() / radius
	f["range_last"] = position.distance_to(context["observer"])

	var neighbors := 0
	var velocity: Vector3 = track["velocity"]
	for other in others:
		if other["id"] == track["id"] or other["status"] == "tentative":
			continue
		var dv: Vector3 = (other["velocity"] as Vector3) - velocity
		if position.distance_to(other["position"]) < NEIGHBOR_DISTANCE_M and Vector2(dv.x, dv.z).length() < NEIGHBOR_SPEED_DIFF_MPS:
			neighbors += 1
	f["neighbor_count"] = float(neighbors)
	f["in_swarm_group"] = 0.0 if String(track.get("swarm_group", "")).is_empty() else 1.0
	return f


## Feature values in NAMES order (the ML input vector).
static func to_vector(features: Dictionary) -> PackedFloat64Array:
	var vector := PackedFloat64Array()
	for name in NAMES:
		vector.append(float(features[name]))
	return vector


static func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total / values.size()


static func _std(values: Array) -> float:
	var mean := _mean(values)
	var total := 0.0
	for v in values:
		total += (float(v) - mean) * (float(v) - mean)
	return sqrt(total / values.size())
