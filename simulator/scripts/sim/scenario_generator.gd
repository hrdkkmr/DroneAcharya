extends RefCounted
## Turns a validated scenario config into a concrete, deterministic definition:
## actors (with hidden truth labels), routes, layout obstacles, zone and wind.
## The same config always produces the same definition.

const SimRandom := preload("res://scripts/sim/sim_random.gd")
const ActorProfiles := preload("res://scripts/sim/actor_profiles.gd")

const DEFINITION_FORMAT := "droneacharya-scenario-definition"
const GENERATOR_VERSION := "generator-1"
const TICK_RATE := 20 ## simulation ticks per second
const OBSERVER_POSITION := Vector3(0.0, 25.0, 0.0) ## top of the observation tower
const AREA_LIMIT_M := 2200.0 ## actors beyond this horizontal range leave the scenario


static func build(config: Dictionary) -> Dictionary:
	var seed_value: int = config["seed"]
	var zone_radius: float = config["protected_zone_radius_m"]
	var wind_dir := deg_to_rad(float(config["wind"]["direction_deg"]))
	var wind := Vector3(sin(wind_dir), 0.0, -cos(wind_dir)) * float(config["wind"]["speed_mps"])
	var actors := []
	var group_number := 0
	for gi in config["groups"].size():
		var group: Dictionary = config["groups"][gi]
		var rng := SimRandom.stream(seed_value, "group-%d" % gi)
		var profile := ActorProfiles.get_profile(group["profile"])
		var is_swarm: bool = group["profile"] == "swarm_uav"
		var group_id := ""
		var leader := {}
		if is_swarm:
			group_number += 1
			group_id = "G%02d" % group_number
		for k in group["count"]:
			var actor := _actor(actors.size() + 1, group, profile, rng, wind, zone_radius)
			actor["group_id"] = group_id
			if is_swarm and k == 0:
				leader = actor
			elif is_swarm:
				_attach_to_formation(actor, leader, k, rng)
			actors.append(actor)
	return {
		"format": DEFINITION_FORMAT, "generator": GENERATOR_VERSION,
		"scenario_id": config["id"], "seed": seed_value, "config": config,
		"tick_rate": TICK_RATE, "duration_ticks": int(config["duration_s"]) * TICK_RATE,
		"observer_position": OBSERVER_POSITION,
		"protected_zone": {"center": Vector3.ZERO, "radius_m": zone_radius},
		"wind": wind, "layout": _layout(config), "actors": actors,
	}


static func _actor(number: int, group: Dictionary, profile: Dictionary, rng: RandomNumberGenerator, wind: Vector3, zone_radius: float) -> Dictionary:
	var behavior: String = group["behavior"]
	var bearing := deg_to_rad(rng.randf_range(0.0, 360.0))
	if behavior == "drift" and wind.length() > 0.1:
		# Balloons start upwind so the wind carries them across the area.
		bearing = atan2(-wind.x, wind.z) + deg_to_rad(rng.randf_range(-50.0, 50.0))
	var distance := SimRandom.range_between(rng, group["start_range_m"])
	var altitude := SimRandom.range_between(rng, group["altitude_m"])
	var speed := SimRandom.range_between(rng, group["speed_mps"])
	var start := Vector3(sin(bearing) * distance, altitude, -cos(bearing) * distance)
	var spawn_s := snappedf(SimRandom.range_between(rng, group["spawn_s"]), 1.0 / TICK_RATE)
	var params := {"speed": speed, "altitude": altitude}
	var inward := -Vector3(start.x, 0.0, start.z).normalized()
	match behavior:
		"transit":
			# Straight route past the protected zone; authorised traffic keeps a wider corridor.
			var side := Vector3(-inward.z, 0.0, inward.x) * (1.0 if rng.randf() < 0.5 else -1.0)
			var offset := rng.randf_range(250.0, 420.0) if group["profile"] == "authorised_uav" else rng.randf_range(0.2, 1.6) * zone_radius
			var pass_point := side * offset + Vector3(0.0, altitude, 0.0)
			var end := pass_point + (pass_point - Vector3(start.x, altitude, start.z))
			params["waypoints"] = [pass_point, Vector3(end.x, altitude, end.z)]
		"loiter", "hover":
			var center_bearing := bearing + deg_to_rad(rng.randf_range(-40.0, 40.0))
			var center_distance := rng.randf_range(0.8, 2.5) * zone_radius
			params["center"] = Vector3(sin(center_bearing) * center_distance, altitude, -cos(center_bearing) * center_distance)
			params["radius"] = rng.randf_range(40.0, 90.0)
			params["clockwise"] = rng.randf() < 0.5
		"erratic":
			params["anchor"] = start
			params["rng_seed"] = rng.randi()
		"drift":
			params["climb_mps"] = rng.randf_range(0.1, 0.4)
	var first_target: Vector3 = params["waypoints"][0] if params.has("waypoints") else params.get("center", start + inward * 50.0)
	var direction := (first_target - start)
	direction.y = 0.0
	var velocity := direction.normalized() * speed if direction.length() > 1.0 else Vector3.ZERO
	return {
		"id": "A%02d" % number, "profile": group["profile"], "behavior": behavior,
		"truth_category": profile["truth_category"], "significant": profile["significant"],
		"spawn_tick": int(round(spawn_s * TICK_RATE)),
		"initial_position": start, "initial_velocity": velocity,
		"size_m": profile["size_m"], "radar_reflectivity": profile["radar_reflectivity"],
		"id_reply": profile["id_reply"], "params": params,
	}


## Swarm members fly in a staggered V behind the first member (the leader).
static func _attach_to_formation(actor: Dictionary, leader: Dictionary, index: int, rng: RandomNumberGenerator) -> void:
	var spacing := rng.randf_range(8.0, 12.0)
	var rank := (index + 1) / 2
	var side := -1.0 if index % 2 == 1 else 1.0
	var offset := Vector3(side * rank * spacing, rng.randf_range(-3.0, 3.0), rank * spacing)
	actor["behavior"] = "formation"
	actor["spawn_tick"] = leader["spawn_tick"]
	actor["params"] = {"leader": leader["id"], "offset": offset, "speed": leader["params"]["speed"]}
	var heading := _heading_of(leader["initial_velocity"])
	actor["initial_position"] = leader["initial_position"] + offset.rotated(Vector3.UP, heading)
	actor["initial_velocity"] = leader["initial_velocity"]


## Yaw angle (radians, Godot convention) of a horizontal velocity.
static func _heading_of(velocity: Vector3) -> float:
	if Vector2(velocity.x, velocity.z).length() < 0.01:
		return 0.0
	return atan2(-velocity.x, -velocity.z)


## Procedural obstacles. Each is an axis-aligned box: {kind, center, size}; center.y
## is half the height so the box stands on the ground.
static func _layout(config: Dictionary) -> Dictionary:
	var rng := SimRandom.stream(int(config["seed"]), "layout")
	var obstacles := []
	var clear_radius: float = config["protected_zone_radius_m"] + 40.0
	if config["environment"] == "urban":
		var block := 60.0
		for gx in range(-12, 13):
			for gz in range(-12, 13):
				var center := Vector2(gx * block, gz * block)
				if center.length() < clear_radius or center.length() > 720.0 or rng.randf() < 0.35:
					continue
				var size := Vector3(rng.randf_range(16.0, 40.0), rng.randf_range(8.0, 38.0), rng.randf_range(16.0, 40.0))
				obstacles.append({"kind": "building", "center": Vector3(center.x, size.y * 0.5, center.y), "size": size})
	else:
		for i in 180:
			var angle := rng.randf_range(0.0, TAU)
			var distance := rng.randf_range(clear_radius, 900.0)
			var height := rng.randf_range(6.0, 14.0)
			var width := rng.randf_range(3.0, 7.0)
			obstacles.append({"kind": "tree", "center": Vector3(sin(angle) * distance, height * 0.5, -cos(angle) * distance), "size": Vector3(width, height, width)})
		for i in 8:
			var angle := rng.randf_range(0.0, TAU)
			var distance := rng.randf_range(clear_radius + 60.0, 800.0)
			obstacles.append({"kind": "building", "center": Vector3(sin(angle) * distance, 3.5, -cos(angle) * distance), "size": Vector3(12.0, 7.0, 9.0)})
	return {"environment": config["environment"], "obstacles": obstacles}
