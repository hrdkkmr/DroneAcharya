extends "res://tests/test_case.gd"
## Flight radar (synthetic sensor + display), traffic and simulated hazards.

const AppState := preload("res://scripts/app/app_state.gd")
const FlightSensor := preload("res://scripts/flight/flight_sensor.gd")
const FlightTraffic := preload("res://scripts/flight/flight_traffic.gd")
const FlightMissions := preload("res://scripts/flight/flight_missions.gd")
const RadarDisplay := preload("res://scripts/ui/radar_display.gd")
const MissionState := preload("res://scripts/mission/mission_state.gd")
const DT := 1.0 / 60.0


func _entity(id: String, kind: String, position: Vector3, velocity := Vector3.ZERO, iff := false) -> Dictionary:
	return {"id": id, "kind": kind, "position": position, "velocity": velocity, "iff": iff, "active": true}


func _run_sensor(sensor: FlightSensor, truth: Array, seconds: float, own := Vector3.ZERO) -> void:
	for i in int(seconds / DT):
		for e in truth:
			e["position"] += e["velocity"] * DT
		sensor.step(DT, own, truth)


func test_sensor_sees_only_within_range_and_hides_truth_ids() -> void:
	var sensor := FlightSensor.new(1)
	var truth := [_entity("E01", "unknown", Vector3(0, 30, -100)), _entity("E02", "unknown", Vector3(0, 30, -200))]
	_run_sensor(sensor, truth, 5.0)
	var contacts := sensor.contact_list()
	assert_eq(contacts.size(), 1, "only the drone within 160 m is a contact")
	assert_true(contacts[0]["id"].begins_with("C"), "sensor's own contact id")
	assert_true(contacts[0]["position"].distance_to(truth[0]["position"]) < 10.0, "contact near the real drone")
	for c in contacts:
		assert_true(not "E0" in str(c), "no truth id leaks into a contact")


func test_detection_probability_falls_with_range_and_noise_is_seeded() -> void:
	var near := FlightSensor.new(5)
	var far := FlightSensor.new(5)
	_run_sensor(near, [_entity("E01", "unknown", Vector3(0, 0, -20))], 100.0)
	_run_sensor(far, [_entity("E01", "unknown", Vector3(0, 0, -150))], 100.0)
	var near_rate := near.detections / float(near.detections + near.missed)
	var far_rate := far.detections / float(far.detections + far.missed)
	# Model: Pd 0.92 at 20 m, 0.62 at 150 m (200 updates each).
	assert_true(near_rate > 0.85 and far_rate < 0.72 and near_rate - far_rate > 0.15, "Pd near %.2f, far %.2f" % [near_rate, far_rate])
	var a := FlightSensor.new(9)
	var b := FlightSensor.new(9)
	_run_sensor(a, [_entity("E01", "unknown", Vector3(10, 20, -80))], 3.0)
	_run_sensor(b, [_entity("E01", "unknown", Vector3(10, 20, -80))], 3.0)
	assert_eq(a.contact_list()[0]["position"], b.contact_list()[0]["position"], "same seed, same noisy measurement")
	assert_true(a.contact_list()[0]["position"] != Vector3(10, 20, -80), "measurement carries noise")


func test_lost_contacts_go_stale_then_disappear() -> void:
	var sensor := FlightSensor.new(2)
	var truth := [_entity("E01", "unknown", Vector3(0, 20, -50))]
	_run_sensor(sensor, truth, 2.0)
	assert_eq(sensor.contact_list().size(), 1, "detected")
	_run_sensor(sensor, [], 2.0)
	assert_true(sensor.contact_list()[0]["stale"], "not seen for 2 s: stale (last known position)")
	_run_sensor(sensor, [], 2.5)
	assert_eq(sensor.contact_list().size(), 0, "dropped after 4 s without detection")
	_run_sensor(sensor, truth, 2.0)
	assert_eq(sensor.contact_list().size(), 1, "reacquired")


func test_classification_uses_observable_cues_only() -> void:
	var sensor := FlightSensor.new(3)
	var truth := [
		_entity("E01", "friendly", Vector3(-60, 30, -60), Vector3(5, 0, 0), true),
		_entity("E02", "projectile", Vector3(60, 5, -120), Vector3(0, 0, 22)),
		_entity("E03", "hostile_drone", Vector3(0, 10, -100), Vector3(0, 0, 5)),
		_entity("E04", "unknown", Vector3(100, 40, 0), Vector3(0, 0, -8)),
	]
	_run_sensor(sensor, truth, 3.0)
	var kinds := {}
	for c in sensor.contact_list():
		kinds[c["id"]] = c["kind"]
	var values := kinds.values()
	values.sort()
	assert_eq(values, ["friendly", "hostile", "projectile", "unknown"], "one of each kind from cues: %s" % str(kinds))


func test_traffic_and_hazards_are_deterministic() -> void:
	var mission := FlightMissions.get_mission("village_hostile")
	var logs := []
	for run in 2:
		var traffic := FlightTraffic.new(mission, Rect2(-230, -400, 450, 490), 42)
		var log := []
		for i in 60 * 40:
			traffic.step(DT, Vector3(-60, 14, -50))
			log.append_array(traffic.take_events())
		logs.append(log)
	assert_eq(logs[0], logs[1], "same seed and flight path, same events")
	assert_true(logs[0].any(func(e): return e["type"] == "launched"), "a site launches at a hovering drone in range")


func test_hovering_gets_hit_moving_avoids() -> void:
	var mission := FlightMissions.get_mission("village_hostile")
	mission["hostile_patrol"] = Vector3(400, 30, 400)
	var hover := FlightTraffic.new(mission, Rect2(-230, -400, 450, 490), 7)
	var hover_damage := 0.0
	for i in 60 * 30:
		hover_damage += hover.step(DT, Vector3(-60, 14, -50))
	var moving := FlightTraffic.new(mission, Rect2(-230, -400, 450, 490), 7)
	var moving_damage := 0.0
	var position := Vector3(-150, 14, -40)
	for i in 60 * 30:
		position += Vector3(8.0, 0, 0) * DT
		moving_damage += moving.step(DT, position)
	assert_true(hover_damage >= 35.0, "hovering in range is hit (%.0f damage)" % hover_damage)
	assert_true(moving_damage < hover_damage, "keeping moving is hit less (%.0f vs %.0f)" % [moving_damage, hover_damage])


func test_hostile_drone_follows_then_gives_up() -> void:
	var mission := FlightMissions.get_mission("city_hostile")
	mission["sites"] = []
	var traffic := FlightTraffic.new(mission, Rect2(-200, -370, 380, 450), 3)
	var hostile: Dictionary = traffic.entities.filter(func(e): return e["kind"] == "hostile_drone")[0]
	var own: Vector3 = hostile["position"] + Vector3(60, 0, 0)
	var modes := []
	for i in 60 * 40:
		own += Vector3(6.0, 0, 0) * DT
		traffic.step(DT, own)
		for e in traffic.take_events():
			if e["type"].begins_with("hostile_"):
				modes.append(e["type"])
	assert_true("hostile_follow" in modes, "follows when the trainee is near")
	assert_true("hostile_break_off" in modes, "gives up when outrun or after a while: %s" % str(modes))


func test_radar_display_is_heading_up_and_range_limited() -> void:
	var radar: RadarDisplay = add_node(RadarDisplay.new())
	radar.range_m = 100.0
	radar.own_position = Vector3.ZERO
	radar.own_yaw = 0.0
	radar.contacts = [{"id": "C01", "kind": "unknown", "position": Vector3(0, 0, -50)}, {"id": "C02", "kind": "unknown", "position": Vector3(0, 0, -150)}]
	radar.update_display()
	assert_eq(radar.drawn.size(), 1, "contact beyond the display range not drawn")
	assert_true(radar.drawn[0]["point"].y < -50.0 and absf(radar.drawn[0]["point"].x) < 0.01, "ahead is up")
	radar.own_yaw = PI / 2.0 # turned left: north is now on the right
	radar.update_display()
	assert_true(radar.drawn[0]["point"].x > 50.0, "contact north appears on the right after turning left")
	radar.marks = [{"kind": "destination", "position": Vector3(0, 0, 1000), "label": "LZ"}]
	radar.update_display()
	var lz: Array = radar.drawn.filter(func(d): return d["kind"] == "destination")
	assert_true(lz.size() == 1 and lz[0]["clamped"], "far destination pinned to the rim")
	for kind in ["friendly", "unknown", "hostile", "projectile", "track", "group"]:
		assert_true(not String(RadarDisplay.STYLES[kind]["letter"]).is_empty(), "%s has a letter, not only a colour" % kind)


func test_hostile_mission_radar_uses_sensor_contacts_and_hits_fail_the_mission() -> void:
	AppState.flight_mission = "village_hostile"
	var main := add_scene("res://scenes/flight/flight_training.tscn")
	await wait_physics_frames(3)
	assert_true(main.traffic != null and main.hud.radar != null, "hostile mission has traffic and a radar")
	main.drone.global_position = Vector3(-60, 14, -50)
	main.mission.state.status = MissionState.Status.FLYING
	var saw_warning := false
	for i in 60 * 45:
		main.drone.global_position = Vector3(-60, 14, -50)
		main.drone.velocity = Vector3.ZERO
		await tree.physics_frame
		if i % 10 == 0:
			main._process(0.0)
			saw_warning = saw_warning or main.hud.has_alert("incoming")
		if main.mission.state.is_finished():
			break
	main._process(0.0)
	var radar = main.hud.radar
	assert_eq(radar.contacts, main.sensor.contact_list(), "radar shows exactly the sensor's contacts")
	for c in radar.contacts:
		assert_true(c["id"].begins_with("C"), "radar contact ids come from the sensor")
	assert_true(saw_warning, "incoming warning banner shown before impacts")
	assert_true(main.threat_stats["incoming_warnings"] > 0 and main.threat_stats["projectiles_launched"] > 0, "warnings and launches counted: %s" % str(main.threat_stats))
	assert_eq(main.mission.state.status, MissionState.Status.FAILED, "a hovering drone in a hostile area is eventually lost")
	assert_true("integrity" in main.mission.state.failure_reason, "failure explains the cause: " + main.mission.state.failure_reason)
	assert_true(main.record.get("result", {}).has("threats"), "threat summary saved in the flight record")
	AppState.flight_mission = FlightMissions.DEFAULT
