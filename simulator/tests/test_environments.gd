extends "res://tests/test_case.gd"
## City and village environments: they build, differ, keep the route flyable, carry
## collision only where needed, and the autopilot (real controls) completes them.

const AppState := preload("res://scripts/app/app_state.gd")
const FlightMissions := preload("res://scripts/flight/flight_missions.gd")
const FlightWorld := preload("res://scripts/world/flight_world.gd")
const MissionState := preload("res://scripts/mission/mission_state.gd")
const Autopilot := preload("res://tests/tools/autopilot.gd")


func _start(mission: String, profile := "recon") -> Node:
	AppState.flight_mission = mission
	AppState.flight_profile = profile
	var main := add_scene("res://scenes/flight/flight_training.tscn")
	await wait_physics_frames(3)
	return main


func _reset_app() -> void:
	AppState.flight_mission = FlightMissions.DEFAULT
	AppState.flight_profile = "recon"


func _count(node: Node, type: String) -> int:
	var total := 1 if node.is_class(type) else 0
	for child in node.get_children():
		total += _count(child, type)
	return total


func test_city_and_village_build_with_their_own_props() -> void:
	var city := await _start("city_delivery")
	var world: Node = city.get_node("World")
	assert_true(city.get_node_or_null("Course") == null, "the hand-built course is replaced")
	for name in ["Buildings", "Props/Roads", "Props/LaneMarkings", "Props/Crossings", "Props/LightPoles", "Props/CarBodies",
			"Props/TreeCrowns", "Props/WaterTanks", "Props/CraneTower", "Props/Walls", "Props/SignPlates", "Checkpoints", "LandingZone"]:
		assert_true(world.has_node(name), "city has " + name)
	assert_eq(city.mission.checkpoints.size(), 5, "five city rings")
	assert_true(city.mission.is_configured(), "mission bound to the city rings")
	var scratch := Node3D.new()
	var city_stats: Dictionary = FlightWorld.build(scratch, FlightMissions.get_mission("city_delivery"))["stats"]
	scratch.free()
	assert_true(city_stats["buildings"] >= 60, "a real street of buildings (%d)" % city_stats["buildings"])
	city.queue_free()
	await tree.process_frame
	var village := await _start("village_supply")
	var vworld: Node = village.get_node("World")
	for name in ["Houses", "Props/PitchedRoofs", "Props/HutRoofs", "Props/CropRows", "Props/UtilityPoles", "Props/Wires",
			"Props/TowerTank", "Props/Tents", "Props/Helipad", "MainRoad", "Checkpoints", "LandingZone"]:
		assert_true(vworld.has_node(name), "village has " + name)
	assert_true(not vworld.has_node("Buildings") and not vworld.has_node("Props/Roads"), "village is not a recoloured city")
	_reset_app()


func test_environment_is_deterministic_for_a_seed() -> void:
	var mission := FlightMissions.get_mission("village_supply")
	var stats := []
	for seed in [mission["seed"], mission["seed"], 99]:
		mission["seed"] = seed
		var root := Node3D.new()
		stats.append(FlightWorld.build(root, mission)["stats"])
		root.free()
	assert_eq(stats[0], stats[1], "same seed, same village")
	assert_true(stats[2] != stats[0], "another seed places props differently")


func test_collision_only_on_hazards_and_within_budget() -> void:
	for id in ["city_delivery", "village_supply"]:
		var root := Node3D.new()
		var built := FlightWorld.build(root, FlightMissions.get_mission(id))
		var stats: Dictionary = built["stats"]
		assert_true(stats["collision_shapes"] < 2500, "%s collision shapes within budget (%d)" % [id, stats["collision_shapes"]])
		var obstacles: Node = root.get_node("Obstacles")
		for body in obstacles.get_children():
			assert_true(body.is_in_group("obstacle"), "%s/%s is an obstacle" % [id, body.name])
		# Ground decals (roads, fields, crossings) are visual only.
		for name in ["LaneMarkings", "Crossings", "CropRows", "FieldSoil", "Bushes", "Helipad"]:
			assert_true(not obstacles.has_node(name), "%s has no collision" % name)
		var draw_nodes := _count(root, "MultiMeshInstance3D")
		assert_true(draw_nodes < 80, "%s drawn with few batched nodes (%d)" % [id, draw_nodes])
		root.free()


## Sweeps a drone-sized box along every route segment: nothing may block it.
func test_every_route_segment_is_clear() -> void:
	for id in ["city_delivery", "village_supply"]:
		var main := await _start(id)
		var mission: Dictionary = FlightMissions.get_mission(id)
		var route: Dictionary = mission["route"]
		var points: Array = [route["spawn"] + Vector3(0, 1.0, 0)]
		points.append(Vector3(route["spawn"].x, route["checkpoints"][0].y, route["spawn"].z))
		points.append_array(route["checkpoints"])
		points.append(Vector3(route["landing"].x, route["checkpoints"][-1].y, route["landing"].z))
		points.append(route["landing"] + Vector3(0, 1.0, 0))
		var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.6, 0.8, 1.6)
		for i in points.size() - 1:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = Transform3D(Basis.IDENTITY, points[i])
			query.motion = points[i + 1] - points[i]
			query.exclude = [main.drone.get_rid()]
			query.collision_mask = 1
			var fraction := space.cast_motion(query)
			assert_true(fraction[0] >= 0.999, "%s segment %d → %d is clear (blocked at %.2f)" % [id, i, i + 1, fraction[0]])
		main.queue_free()
		await tree.process_frame
	_reset_app()


func test_autopilot_completes_city_and_village_missions() -> void:
	for id in ["city_delivery", "village_supply"]:
		var main := await _start(id)
		var drone: CharacterBody3D = main.drone
		var mission: Node = main.mission
		var pilot := Autopilot.new()
		pilot.landing_cruise_altitude = 12.0
		for i in 60 * 200:
			pilot.fly_mission(drone, mission)
			await tree.physics_frame
			if mission.state.is_finished():
				break
		pilot.release_all()
		assert_eq(mission.state.status, MissionState.Status.COMPLETED, "%s completed by the autopilot: next ring %d, reason '%s', at %s" % [
			id, mission.state.next_checkpoint, mission.state.failure_reason, drone.global_position])
		print("     %s autopilot time: %.1f s (limit %.0f s)" % [id, mission.state.elapsed_seconds, mission.state.time_limit_s])
		main.queue_free()
		await tree.process_frame
	_reset_app()
