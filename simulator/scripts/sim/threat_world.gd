extends RefCounted
## Ground-truth simulation of the scripted target actors, stepped at a fixed rate.
## Behaviours produce a desired air velocity; flight_model.gd applies the limits.
## physical_snapshot() is the only view a sensor may use: it contains physical
## properties, never profile names or truth labels.

const VehicleState := preload("res://scripts/sim/vehicle_state.gd")
const FlightModel := preload("res://scripts/sim/flight_model.gd")
const ActorProfiles := preload("res://scripts/sim/actor_profiles.gd")
const Generator := preload("res://scripts/sim/scenario_generator.gd")

var definition: Dictionary
var tick := 0
var dt := 1.0 / Generator.TICK_RATE
var actors: Array = [] ## runtime records, same order as definition.actors

var _by_id := {}


func _init(scenario_definition: Dictionary) -> void:
	definition = scenario_definition
	dt = 1.0 / float(definition.get("tick_rate", Generator.TICK_RATE))
	for actor_def in definition["actors"]:
		var record := {
			"def": actor_def, "id": actor_def["id"], "state": VehicleState.new(),
			"air_velocity": Vector3.ZERO, "spawned": false, "active": false, "exited": false,
			"model": FlightModel.from_profile(ActorProfiles.get_profile(actor_def["profile"])),
			"waypoint": 0, "next_turn_tick": 0, "turn_target": Vector3.ZERO,
			"rng": null,
		}
		if actor_def["params"].has("rng_seed"):
			var rng := RandomNumberGenerator.new()
			rng.seed = actor_def["params"]["rng_seed"]
			record["rng"] = rng
		actors.append(record)
		_by_id[actor_def["id"]] = record


func time_s() -> float:
	return tick * dt


func is_finished() -> bool:
	return tick >= int(definition["duration_ticks"])


## Advances one fixed tick.
func step() -> void:
	tick += 1
	var wind: Vector3 = definition["wind"]
	var gust := wind * 0.15 * sin(time_s() * 0.7)
	for record in actors:
		if record["exited"]:
			continue
		if not record["spawned"] and tick >= int(record["def"]["spawn_tick"]):
			_spawn(record)
		if not record["active"]:
			continue
		var desired := _desired_velocity(record)
		record["air_velocity"] = record["model"].step(record["state"], record["air_velocity"], desired, wind + gust, dt)
		var p: Vector3 = record["state"].position
		if Vector2(p.x, p.z).length() > Generator.AREA_LIMIT_M:
			record["active"] = false
			record["exited"] = true


func active_ids() -> Array:
	var ids := []
	for record in actors:
		if record["active"]:
			ids.append(record["id"])
	return ids


func get_state(actor_id: String) -> RefCounted:
	return _by_id[actor_id]["state"] if _by_id.has(actor_id) else null


## Physical properties only. This is the sensor's sole input about the targets.
func physical_snapshot() -> Array:
	var result := []
	for record in actors:
		if not record["active"]:
			continue
		var d: Dictionary = record["def"]
		result.append({
			"actor_id": d["id"], ## used only to label truth links; sensors must not copy it into observations
			"position": record["state"].position, "velocity": record["state"].velocity,
			"size_m": d["size_m"], "radar_reflectivity": d["radar_reflectivity"], "id_reply": d["id_reply"],
		})
	return result


## Deterministic fingerprint of all actor positions (for reproducibility tests).
func state_hash() -> int:
	var parts := PackedStringArray()
	for record in actors:
		var p: Vector3 = record["state"].position
		parts.append("%s:%d:%.3f,%.3f,%.3f" % [record["id"], int(record["active"]), p.x, p.y, p.z])
	return ",".join(parts).hash()


func _spawn(record: Dictionary) -> void:
	var d: Dictionary = record["def"]
	var state: RefCounted = record["state"]
	state.position = d["initial_position"]
	state.velocity = d["initial_velocity"]
	state.time_s = time_s()
	record["air_velocity"] = d["initial_velocity"]
	record["spawned"] = true
	record["active"] = true


func _desired_velocity(record: Dictionary) -> Vector3:
	var d: Dictionary = record["def"]
	var params: Dictionary = d["params"]
	var state: RefCounted = record["state"]
	var position: Vector3 = state.position
	match d["behavior"]:
		"transit":
			var waypoints: Array = params["waypoints"]
			var index: int = record["waypoint"]
			if index < waypoints.size() and _horizontal_distance(position, waypoints[index]) < 20.0:
				index += 1
				record["waypoint"] = index
			var target: Vector3 = waypoints[mini(index, waypoints.size() - 1)]
			var direction: Vector3 = (target - position) if index < waypoints.size() else (waypoints[-1] - waypoints[-2])
			return _toward(direction, params["speed"], params["altitude"] - position.y)
		"loiter":
			var to_center: Vector3 = params["center"] - position
			to_center.y = 0.0
			var distance := to_center.length()
			if distance > params["radius"] + 25.0:
				return _toward(to_center, params["speed"], params["altitude"] - position.y)
			var outward := -to_center.normalized()
			var tangent := Vector3(-outward.z, 0.0, outward.x) * (1.0 if params["clockwise"] else -1.0)
			var correction: Vector3 = outward * (float(params["radius"]) - distance) * 0.3
			return _toward(tangent * params["speed"] + correction, params["speed"], params["altitude"] - position.y)
		"hover":
			var to_point: Vector3 = params["center"] - position
			if to_point.length() > 15.0:
				return _toward(to_point, params["speed"], to_point.y)
			return to_point * 0.4
		"drift":
			return Vector3(0.0, params["climb_mps"], 0.0)
		"erratic":
			return _bird_velocity(record, params, position)
		"formation":
			var leader: Dictionary = _by_id[params["leader"]]
			var leader_state: RefCounted = leader["state"]
			var slot: Vector3 = leader_state.position + (params["offset"] as Vector3).rotated(Vector3.UP, leader_state.yaw)
			return leader_state.velocity + (slot - position) * 0.8
	return Vector3.ZERO


## Birds pick a new heading, speed and height every 1-3 s and stay near their anchor.
func _bird_velocity(record: Dictionary, params: Dictionary, position: Vector3) -> Vector3:
	var rng: RandomNumberGenerator = record["rng"]
	if tick >= int(record["next_turn_tick"]):
		var heading := atan2(record["state"].velocity.x, -record["state"].velocity.z) + deg_to_rad(rng.randf_range(-100.0, 100.0))
		var anchor: Vector3 = params["anchor"]
		if _horizontal_distance(position, anchor) > 250.0:
			heading = atan2(anchor.x - position.x, -(anchor.z - position.z))
		var speed := rng.randf_range(0.6, 1.2) * float(params["speed"])
		var height := clampf(position.y + rng.randf_range(-15.0, 15.0), 15.0, 120.0)
		record["turn_target"] = Vector3(sin(heading) * speed, (height - position.y) * 0.3, -cos(heading) * speed)
		record["next_turn_tick"] = tick + int(rng.randf_range(1.0, 3.0) / dt)
	return record["turn_target"]


static func _toward(direction: Vector3, speed: float, climb: float) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	var horizontal := flat.normalized() * speed if flat.length() > 0.01 else Vector3.ZERO
	return Vector3(horizontal.x, clampf(climb * 0.5, -3.0, 3.0), horizontal.z)


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
