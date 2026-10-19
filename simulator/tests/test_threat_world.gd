extends "res://tests/test_case.gd"
## Scenario generation and the ground-truth world: determinism, spawning, swarms,
## flight-model limits and what the sensor-facing snapshot exposes.

const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const Generator := preload("res://scripts/sim/scenario_generator.gd")
const ThreatWorld := preload("res://scripts/sim/threat_world.gd")
const FlightModel := preload("res://scripts/sim/flight_model.gd")
const VehicleState := preload("res://scripts/sim/vehicle_state.gd")


func _world(path: String) -> ThreatWorld:
	var result := ScenarioConfig.load_file(path)
	return ThreatWorld.new(Generator.build(result["config"]))


func _run(world: ThreatWorld, ticks: int) -> void:
	for i in ticks:
		world.step()


func test_same_seed_reproduces_and_different_seed_differs() -> void:
	var a := _world("res://scenarios/02_swarm_urban_day.json")
	var b := _world("res://scenarios/02_swarm_urban_day.json")
	_run(a, 1200)
	_run(b, 1200)
	assert_eq(a.state_hash(), b.state_hash(), "identical after 60 s")
	var config: Dictionary = ScenarioConfig.load_file("res://scenarios/02_swarm_urban_day.json")["config"]
	config["seed"] = 999
	var c := ThreatWorld.new(Generator.build(config))
	_run(c, 1200)
	assert_true(a.state_hash() != c.state_hash(), "different seed gives a different world")
	assert_eq(Generator.build(config)["layout"], Generator.build(config)["layout"], "layout reproducible")


func test_single_drone_scenario_spawns_on_schedule() -> void:
	var world := _world("res://scenarios/01_single_rural_day.json")
	var uav: Dictionary = world.definition["actors"][0]
	assert_eq(uav["profile"], "unidentified_uav", "first actor is the threat")
	_run(world, uav["spawn_tick"] - 1)
	assert_true(not "A01" in world.active_ids(), "not active before spawn tick")
	world.step()
	assert_true("A01" in world.active_ids(), "active at spawn tick")


func test_swarm_flies_as_a_group() -> void:
	var world := _world("res://scenarios/02_swarm_urban_day.json")
	var members := []
	for actor in world.definition["actors"]:
		if actor["profile"] == "swarm_uav":
			members.append(actor["id"])
			assert_eq(actor["group_id"], "G01", "%s in group G01" % actor["id"])
	assert_eq(members.size(), 6, "six swarm members")
	_run(world, 1600)
	var leader: RefCounted = world.get_state(members[0])
	for actor in world.definition["actors"]:
		if actor["id"] in members.slice(1):
			var slot: Vector3 = leader.position + (actor["params"]["offset"] as Vector3).rotated(Vector3.UP, leader.yaw)
			var error := slot.distance_to(world.get_state(actor["id"]).position)
			assert_true(error < 20.0, "%s holds its formation slot (%.1f m off)" % [actor["id"], error])


func test_actor_speeds_and_altitudes_respect_profiles() -> void:
	var world := _world("res://scenarios/03_mixed_rural_night_degraded.json")
	for i in 2400:
		world.step()
		if i % 20 != 0:
			continue
		for record in world.actors:
			if not record["active"]:
				continue
			var model: RefCounted = record["model"]
			var state: RefCounted = record["state"]
			var limit: float = model.max_speed + float(world.definition["wind"].length()) * 1.2 * model.wind_factor + 0.5
			assert_true(state.horizontal_speed() <= limit, "%s speed %.1f within %.1f" % [record["id"], state.horizontal_speed(), limit])
			assert_true(state.position.y >= model.min_altitude - 0.001 and state.position.y <= model.max_altitude + 0.001, "%s altitude bounded" % record["id"])


func test_flight_model_limits_turn_rate_and_acceleration() -> void:
	var model := FlightModel.new()
	model.max_turn_rate_degrees = 30.0
	model.max_acceleration = 2.0
	model.damping = 0.0
	model.wind_factor = 0.0
	var state := VehicleState.new()
	state.position = Vector3(0, 50, 0)
	var air := Vector3(0, 0, -10)
	state.velocity = air
	air = model.step(state, air, Vector3(10, 0, 0), Vector3.ZERO, 0.5)
	var turned := rad_to_deg(Vector2(0, -10).angle_to(Vector2(air.x, air.z)))
	assert_true(turned <= 15.0 + 0.01, "turned at most 15° in 0.5 s (%.2f°)" % turned)
	var state2 := VehicleState.new()
	state2.position = Vector3(0, 50, 0)
	var air2 := model.step(state2, Vector3.ZERO, Vector3(0, 0, -10), Vector3.ZERO, 1.0)
	assert_near(air2.length(), 2.0, 0.001, "acceleration limited to 2 m/s² over 1 s")
	var low := VehicleState.new()
	low.position = Vector3(0, 6, 0)
	model.step(low, Vector3.ZERO, Vector3(0, -3, 0), Vector3.ZERO, 2.0)
	assert_near(low.position.y, model.min_altitude, 0.001, "clamped at minimum altitude")
	assert_eq(model.step(low, Vector3(1, 0, 0), Vector3.ZERO, Vector3.ZERO, NAN), Vector3(1, 0, 0), "invalid dt ignored")


func test_balloon_drifts_with_the_wind() -> void:
	var world := _world("res://scenarios/02_swarm_urban_day.json")
	var balloon := ""
	for actor in world.definition["actors"]:
		if actor["profile"] == "balloon":
			balloon = actor["id"]
	_run(world, 600)
	var velocity: Vector3 = world.get_state(balloon).velocity
	var wind: Vector3 = world.definition["wind"]
	var alignment := Vector2(velocity.x, velocity.z).normalized().dot(Vector2(wind.x, wind.z).normalized())
	assert_true(alignment > 0.9, "balloon moves downwind (alignment %.2f)" % alignment)


func test_sensor_snapshot_contains_no_truth_labels() -> void:
	var world := _world("res://scenarios/03_mixed_rural_night_degraded.json")
	_run(world, 1800)
	var snapshot := world.physical_snapshot()
	assert_true(snapshot.size() > 0, "actors active")
	for item in snapshot:
		for forbidden in ["profile", "truth_category", "significant", "behavior", "group_id", "params"]:
			assert_true(not item.has(forbidden), "snapshot excludes " + forbidden)


func test_urban_and_rural_layouts_differ() -> void:
	var urban: Dictionary = Generator.build(ScenarioConfig.load_file("res://scenarios/02_swarm_urban_day.json")["config"])["layout"]
	var rural: Dictionary = Generator.build(ScenarioConfig.load_file("res://scenarios/01_single_rural_day.json")["config"])["layout"]
	var kinds := {}
	for o in urban["obstacles"]:
		kinds[o["kind"]] = true
	assert_eq(kinds.keys(), ["building"], "urban layout is buildings")
	var trees := 0
	for o in rural["obstacles"]:
		trees += int(o["kind"] == "tree")
	assert_true(trees > 100, "rural layout has trees")
	for o in urban["obstacles"]:
		assert_true(Vector2(o["center"].x, o["center"].z).length() > 160.0 - 1.0, "no building inside the cleared zone")
