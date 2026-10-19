extends RefCounted
## Baseline track management over delivered observations only (no ground truth).
## * Association: per (sensor, time) batch, greedy nearest-neighbour inside a gate.
##   Radar uses metric distance to the predicted position; the camera (coarse range)
##   uses angular distance.
## * Filtering: alpha-beta position/velocity filter. The first updates use the
##   growing-memory gains α=2(2n-1)/(n(n+1)), β=6/(n(n+1)) (a least-squares line fit),
##   which then settle to the steady gains below. Simple fusion: the camera
##   corrects direction only (its range is coarse); while a track has a camera update
##   from the last second, radar corrects range only (its bearing is coarse).
## * Lifecycle: tentative → confirmed (3 hits within 6 s) → coasting (no update for
##   2.5 s; position extrapolated) → lost (no update for 8 s; retired).
##   Coasting means "no recent observation", not "target gone".
## * Swarm summary: confirmed tracks closer than 80 m with similar velocity, in
##   groups of three or more, form a group with a stable id.

const CONFIRM_HITS := 3
const CONFIRM_WINDOW_S := 6.0
const COAST_AFTER_S := 2.5
const LOST_AFTER_S := 8.0
const HISTORY_LIMIT := 240
const RADAR_ALPHA := 0.4
const RADAR_BETA := 0.1
const EO_ALPHA := 0.5
const EO_BETA := 0.02
const EO_MIN_RANGE_M := 50.0 ## closer than this the camera's angle-only update is unreliable
const EO_FRESH_S := 1.0 ## a camera update this recent makes radar correct range only
const GROUP_DISTANCE_M := 80.0
const GROUP_SPEED_DIFF_MPS := 6.0
const GROUP_MIN_SIZE := 3

var observer: Vector3
var radar_bearing_sigma_deg := 1.0
var eo_bearing_sigma_deg := 0.15
var eo_can_initiate := false
var tracks := {} ## active (tentative, confirmed, coasting) by id
var retired: Array = [] ## lost or dropped tracks
var events: Array = [] ## lifecycle events not yet collected: {type, track_id, t}
var groups := {} ## group id -> {id, members: Array, centroid, velocity}

var _next_track := 1
var _next_group := 1


func _init(observer_position: Vector3, sensor_config: Dictionary) -> void:
	observer = observer_position
	radar_bearing_sigma_deg = float(sensor_config["radar"]["bearing_noise_deg"])
	eo_bearing_sigma_deg = float(sensor_config["eo"]["bearing_noise_deg"])
	eo_can_initiate = not bool(sensor_config["radar"]["enabled"])


## Associates a batch of delivered observations (sorted by time) with tracks.
func process(observations: Array, now: float) -> void:
	var batches := {}
	var order := []
	for o in observations:
		var key := "%s@%.3f" % [o["sensor"], o["t"]]
		if not batches.has(key):
			batches[key] = []
			order.append(key)
		batches[key].append(o)
	for key in order:
		_process_batch(batches[key])
	maintain(now)


func _process_batch(batch: Array) -> void:
	var pairs := []
	for i in batch.size():
		for id in tracks:
			var cost := association_cost(tracks[id], batch[i])
			if cost < 1.0:
				pairs.append([cost, i, id])
	pairs.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	var used_obs := {}
	var used_tracks := {}
	for pair in pairs:
		if used_obs.has(pair[1]) or used_tracks.has(pair[2]):
			continue
		used_obs[pair[1]] = true
		used_tracks[pair[2]] = true
		_update(tracks[pair[2]], batch[pair[1]])
	for i in batch.size():
		if not used_obs.has(i) and (batch[i]["sensor"] == "radar" or eo_can_initiate):
			_create(batch[i])


## Normalised association cost; < 1 means the observation is inside the track's gate.
func association_cost(track: Dictionary, o: Dictionary) -> float:
	var dt := maxf(float(o["t"]) - float(track["last_update_t"]), 0.0)
	var predicted: Vector3 = track["position"] + track["velocity"] * dt
	var distance := (predicted - observer).length()
	if o["sensor"] == "eo":
		# Compare in cross-range metres: the camera's range is coarse but its angle is precise.
		var cross_m := (predicted - observer).angle_to(o["position"] - observer) * distance
		var gate_eo := 10.0 + 3.0 * distance * deg_to_rad(eo_bearing_sigma_deg) + 6.0 * dt
		return cross_m / gate_eo
	var cross_sigma := distance * deg_to_rad(radar_bearing_sigma_deg)
	var gate_m := 15.0 + 3.0 * sqrt(pow(float(o["range_sigma_m"]), 2.0) + cross_sigma * cross_sigma) + 6.0 * dt
	return (predicted - (o["position"] as Vector3)).length() / gate_m


func _create(o: Dictionary) -> void:
	var id := "T%03d" % _next_track
	_next_track += 1
	var track := {
		"id": id, "status": "tentative", "created_t": o["t"], "last_update_t": o["t"],
		"confirmed_t": -1.0, "last_eo_t": float(o["t"]) if o["sensor"] == "eo" else -INF,
		"position": o["position"], "velocity": Vector3.ZERO,
		"hits": 0, "kinematic_updates": 0, "radar_hits": 0, "eo_hits": 0, "id_replies": 0, "eo_id_hits": 0,
		"sizes": [], "flaps": 0, "quality_sum": 0.0, "degraded_hits": 0,
		"history": [], "obs_ids": [], "swarm_group": "",
	}
	tracks[id] = track
	events.append({"type": "track_created", "track_id": id, "t": o["t"]})
	_absorb(track, o, false)


func _update(track: Dictionary, o: Dictionary) -> void:
	var dt := float(o["t"]) - float(track["last_update_t"])
	if dt > 1e-6:
		var predicted: Vector3 = track["position"] + track["velocity"] * dt
		var measured: Vector3 = o["position"]
		var alpha := RADAR_ALPHA
		var beta := RADAR_BETA
		if o["sensor"] == "eo":
			# The camera's range is coarse: keep the predicted range, take its direction.
			measured = observer + (measured - observer).normalized() * (predicted - observer).length()
			alpha = EO_ALPHA
			beta = EO_BETA
		if o["sensor"] == "eo" and (predicted - observer).length() < EO_MIN_RANGE_M:
			measured = predicted
		var n := int(track["kinematic_updates"]) + 2
		alpha = maxf(alpha, 2.0 * (2.0 * n - 1.0) / (n * (n + 1.0)))
		beta = maxf(beta, 6.0 / (n * (n + 1.0)))
		track["kinematic_updates"] += 1
		var residual := measured - predicted
		if o["sensor"] == "radar" and float(o["t"]) - float(track["last_eo_t"]) <= EO_FRESH_S:
			var line := (predicted - observer).normalized()
			residual = line * residual.dot(line)
		track["position"] = predicted + residual * alpha
		track["velocity"] = (track["velocity"] as Vector3) + residual * (beta / dt)
		track["last_update_t"] = o["t"]
	if o["sensor"] == "eo":
		track["last_eo_t"] = maxf(float(track["last_eo_t"]), float(o["t"]))
	_absorb(track, o, dt > 1e-6)
	if track["status"] == "tentative" and track["hits"] >= CONFIRM_HITS:
		track["status"] = "confirmed"
		track["confirmed_t"] = o["t"]
		events.append({"type": "track_confirmed", "track_id": track["id"], "t": o["t"]})
	elif track["status"] == "coasting":
		track["status"] = "confirmed"
		events.append({"type": "track_reacquired", "track_id": track["id"], "t": o["t"]})


## Adds an observation's attributes to the track (also for late, out-of-order ones).
func _absorb(track: Dictionary, o: Dictionary, kinematic: bool) -> void:
	track["hits"] += 1
	track["obs_ids"].append(o["id"])
	track["quality_sum"] += float(o["quality"])
	track["degraded_hits"] += int(o["degraded"])
	if o["sensor"] == "radar":
		track["radar_hits"] += 1
		track["id_replies"] += int(o["id_reply"])
	else:
		track["eo_hits"] += 1
		if o["id_quality"]:
			track["eo_id_hits"] += 1
			track["sizes"].append(o["apparent_size_m"])
			track["flaps"] += int(o["flap_detected"])
	if kinematic or track["history"].is_empty():
		track["history"].append({"t": o["t"], "position": track["position"], "velocity": track["velocity"], "sensor": o["sensor"]})
		if track["history"].size() > HISTORY_LIMIT:
			track["history"].pop_front()


## Applies time-based lifecycle rules at `now`.
func maintain(now: float) -> void:
	for id in tracks.keys():
		var track: Dictionary = tracks[id]
		var age := now - float(track["last_update_t"])
		match track["status"]:
			"tentative":
				if now - float(track["created_t"]) > CONFIRM_WINDOW_S:
					_retire(track, "dropped", now)
			"confirmed", "coasting":
				if track["status"] == "confirmed" and age > COAST_AFTER_S:
					track["status"] = "coasting"
					events.append({"type": "track_coasting", "track_id": id, "t": now})
				if track["status"] == "coasting" and age > LOST_AFTER_S:
					_retire(track, "lost", now)
	_update_groups()


func _retire(track: Dictionary, status: String, now: float) -> void:
	track["status"] = status
	track["retired_t"] = now
	tracks.erase(track["id"])
	retired.append(track)
	events.append({"type": "track_" + status, "track_id": track["id"], "t": now})


## Estimated position at `now` (extrapolated while coasting).
func estimated_position(track: Dictionary, now: float) -> Vector3:
	var dt := clampf(now - float(track["last_update_t"]), 0.0, LOST_AFTER_S)
	return track["position"] + track["velocity"] * dt


func confirmed_tracks() -> Array:
	var result := []
	for id in tracks:
		if tracks[id]["status"] != "tentative":
			result.append(tracks[id])
	result.sort_custom(func(a, b): return a["id"] < b["id"])
	return result


func take_events() -> Array:
	var result := events
	events = []
	return result


func _update_groups() -> void:
	var candidates := confirmed_tracks()
	var parent := {}
	for t in candidates:
		parent[t["id"]] = t["id"]
	for i in candidates.size():
		for j in range(i + 1, candidates.size()):
			var a: Dictionary = candidates[i]
			var b: Dictionary = candidates[j]
			var dv: Vector3 = a["velocity"] - b["velocity"]
			if (a["position"] as Vector3).distance_to(b["position"]) < GROUP_DISTANCE_M and Vector2(dv.x, dv.z).length() < GROUP_SPEED_DIFF_MPS:
				parent[_root(parent, a["id"])] = _root(parent, b["id"])
	var components := {}
	for t in candidates:
		components.get_or_add(_root(parent, t["id"]), []).append(t["id"])
	var new_groups := {}
	var taken := {}
	for root in components:
		var members: Array = components[root]
		if members.size() < GROUP_MIN_SIZE:
			continue
		members.sort()
		var best := ""
		var best_overlap := 0
		for gid in groups:
			if taken.has(gid):
				continue
			var overlap := 0
			for m in members:
				overlap += int(m in groups[gid]["members"])
			if overlap > best_overlap:
				best_overlap = overlap
				best = gid
		if best.is_empty():
			best = "S%02d" % _next_group
			_next_group += 1
		taken[best] = true
		var centroid := Vector3.ZERO
		var velocity := Vector3.ZERO
		for m in members:
			centroid += tracks[m]["position"]
			velocity += tracks[m]["velocity"]
		new_groups[best] = {"id": best, "members": members, "centroid": centroid / members.size(), "velocity": velocity / members.size()}
	for t in candidates:
		t["swarm_group"] = ""
	for gid in new_groups:
		for m in new_groups[gid]["members"]:
			tracks[m]["swarm_group"] = gid
	groups = new_groups


static func _root(parent: Dictionary, id: String) -> String:
	while parent[id] != id:
		parent[id] = parent[parent[id]]
		id = parent[id]
	return id
