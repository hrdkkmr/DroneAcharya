extends "res://tests/test_case.gd"
## Synthetic sensor model and tracker: range/FOV/LOS, noise, missed detections,
## delay, degradation, track lifecycle, swarm grouping and truth isolation.

const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const Generator := preload("res://scripts/sim/scenario_generator.gd")
const SensorModel := preload("res://scripts/sim/sensor_model.gd")
const Tracker := preload("res://scripts/sim/tracker.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")

const TRUTH_KEYS := ["actor_id", "profile", "truth_category", "significant", "behavior", "group_id", "label"] ## group_id = truth swarm id


## A controlled definition: empty layout, one sensor configuration, no clutter.
func _definition(sensor_overrides: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var raw := {
		"format": "droneacharya-scenario", "version": 1, "id": "s", "seed": 11,
		"environment": "rural", "time_of_day": "day", "visibility": "clear", "duration_s": 60,
		"groups": [{"profile": "unidentified_uav", "behavior": "hover"}],
		"sensor": {"clutter_per_min": 0.0, "delay_s": [0.0, 0.0]},
	}
	raw["sensor"].merge(sensor_overrides, true)
	raw.merge(extra, true)
	var result := ScenarioConfig.validate(raw)
	assert_true(result["ok"], "test config valid: " + "; ".join(result["errors"]))
	var definition := Generator.build(result["config"])
	definition["layout"]["obstacles"] = []
	return definition


func _target(position: Vector3, extra: Dictionary = {}) -> Dictionary:
	var target := {"actor_id": "A01", "position": position, "velocity": Vector3.ZERO, "size_m": 0.7, "radar_reflectivity": 0.35, "id_reply": false, "flapping": false}
	target.merge(extra, true)
	return target


func _scan(sensor: SensorModel, targets: Array, seconds: float) -> Array:
	var delivered := []
	for tick in range(1, int(seconds * 20) + 1):
		delivered.append_array(sensor.update(tick, targets))
	return delivered


func test_observations_carry_no_ground_truth() -> void:
	var session := ThreatSession.new(ScenarioConfig.load_file("res://scenarios/03_mixed_rural_night_degraded.json")["config"])
	session.start()
	for i in 20 * 90:
		session.step()
	assert_true(session.observations.size() > 50, "observations delivered (%d)" % session.observations.size())
	for o in session.observations:
		for key in TRUTH_KEYS:
			assert_true(not o.has(key), "observation has no '%s'" % key)
	for track in session.tracker.confirmed_tracks():
		for key in TRUTH_KEYS:
			assert_true(not track.has(key), "track has no '%s'" % key)
	assert_true(session.sensor.truth_links.size() == session.sensor._next_id - 1, "every observation has a separate truth link")
	assert_true("clutter" in session.sensor.truth_links.values(), "clutter recorded in truth links only")


func test_radar_range_elevation_limit_and_noise() -> void:
	var sensor := SensorModel.new(_definition({"radar": {"detection_prob": 1.0, "range_m": 1000.0, "range_noise_m": 10.0}, "eo": {"enabled": false}}))
	var observer: Vector3 = sensor.observer
	assert_eq(_scan(sensor, [_target(observer + Vector3(0, 0, -1100))], 10.0).size(), 0, "nothing beyond radar range")
	assert_eq(_scan(sensor, [_target(observer + Vector3(0, 300, -100))], 10.0).size(), 0, "nothing above max elevation (72°)")
	var near := _scan(sensor, [_target(observer + Vector3(0, 0, -300))], 60.0)
	assert_true(near.size() >= 45, "near target detected on most of 60 scans (%d)" % near.size())
	var errors := []
	for o in near:
		errors.append(float(o["range_m"]) - 300.0)
	var mean := 0.0
	for e in errors:
		mean += e
	mean /= errors.size()
	var variance := 0.0
	for e in errors:
		variance += (e - mean) * (e - mean)
	var std := sqrt(variance / errors.size())
	assert_true(absf(mean) < 5.0, "range noise unbiased (mean %.2f m)" % mean)
	assert_true(std > 6.0 and std < 14.0, "range noise ≈ configured 10 m (std %.2f m)" % std)


func test_missed_detections_follow_detection_probability() -> void:
	var sensor := SensorModel.new(_definition({"radar": {"detection_prob": 0.5}, "eo": {"enabled": false}}))
	var delivered := _scan(sensor, [_target(sensor.observer + Vector3(0, 0, -200))], 200.0)
	assert_true(delivered.size() > 50 and delivered.size() < 140, "about half of 200 scans detect (%d)" % delivered.size())
	assert_eq(sensor.stats["radar_missed"] + sensor.stats["radar_detections"], 200, "every scan is a detection or a miss")


func test_measurement_delay_is_applied() -> void:
	var sensor := SensorModel.new(_definition({"radar": {"detection_prob": 1.0}, "eo": {"enabled": false}, "delay_s": [1.0, 1.5]}))
	var target := _target(sensor.observer + Vector3(0, 0, -200))
	assert_eq(sensor.update(20, [target]).size(), 0, "not delivered at measurement time")
	var delivered := []
	for tick in range(21, 60):
		for o in sensor.update(tick, []):
			delivered.append([o, tick / 20.0])
	assert_eq(delivered.size(), 1, "delivered later")
	var delay: float = delivered[0][1] - float(delivered[0][0]["t"])
	assert_true(delay >= 0.99 and delay <= 1.56, "delay within 1.0-1.5 s (%.2f)" % delay)


func test_camera_limits_night_fog_fov_and_line_of_sight() -> void:
	var day := SensorModel.new(_definition({"radar": {"enabled": false}}))
	var night := SensorModel.new(_definition({"radar": {"enabled": false}}, {"time_of_day": "night", "visibility": "fog"}))
	assert_near(day.eo_range_m(), 700.0, 0.01, "day clear camera range")
	assert_near(night.eo_range_m(), 700.0 * 0.25 * 0.5, 0.01, "night + fog reduces camera range")
	var far := _target(day.observer + Vector3(0, 0, -400))
	assert_true(_scan(day, [far], 5.0).size() > 0, "visible in daylight at 400 m")
	assert_eq(_scan(night, [far], 5.0).size(), 0, "not visible at night in fog at 400 m")
	var sector := SensorModel.new(_definition({"radar": {"enabled": false}, "eo": {"fov_deg": 90.0, "center_deg": 0.0}}))
	assert_true(_scan(sector, [_target(sector.observer + Vector3(0, 0, -300))], 5.0).size() > 0, "inside 90° sector (north)")
	assert_eq(_scan(sector, [_target(sector.observer + Vector3(300, 0, 0))], 5.0).size(), 0, "outside sector (east)")
	var blocked := _definition({"radar": {"detection_prob": 1.0}})
	blocked["layout"]["obstacles"] = [{"kind": "building", "center": Vector3(0, 30, -150), "size": Vector3(40, 60, 10)}]
	var behind := SensorModel.new(blocked)
	assert_eq(_scan(behind, [_target(behind.observer + Vector3(0, -5, -300))], 5.0).size(), 0, "building blocks radar and camera")
	assert_eq(behind.line_of_sight(behind.observer, behind.observer + Vector3(0, 100, -300)), "clear", "line passes over the building")


func test_identification_quality_size_and_wing_beat_cues() -> void:
	var sensor := SensorModel.new(_definition({"radar": {"enabled": false}, "eo": {"detection_prob": 1.0}}))
	var close := _scan(sensor, [_target(sensor.observer + Vector3(0, 0, -200), {"size_m": 0.6, "flapping": true})], 10.0)
	var flaps := 0
	for o in close:
		assert_true(o["id_quality"] and o["apparent_size_m"] > 0.0, "identification quality within 350 m")
		flaps += int(o["flap_detected"])
	assert_true(flaps > close.size() * 0.6, "wing-beat cue usually detected for a flapping target")
	for o in _scan(sensor, [_target(sensor.observer + Vector3(0, 0, -500))], 5.0):
		assert_true(not o["id_quality"] and o["apparent_size_m"] < 0.0, "no identification cues beyond 350 m")


func test_degradation_reduces_detections_and_adds_noise_and_delay() -> void:
	var definition := _definition({"radar": {"detection_prob": 0.95}, "eo": {"enabled": false}, "delay_s": [0.2, 0.4],
		"degradation": [{"start_s": 0.0, "end_s": 60.0, "severity": 1.0}]})
	var degraded := SensorModel.new(definition)
	var nominal := SensorModel.new(_definition({"radar": {"detection_prob": 0.95}, "eo": {"enabled": false}, "delay_s": [0.2, 0.4]}))
	var target := _target(degraded.observer + Vector3(0, 0, -500))
	var a := _scan(degraded, [target], 55.0)
	var b := _scan(nominal, [target], 55.0)
	assert_true(a.size() < b.size() * 0.7, "fewer detections when degraded (%d vs %d)" % [a.size(), b.size()])
	for o in a:
		assert_true(o["degraded"], "observation flagged as degraded")
		assert_near(o["range_sigma_m"], 8.0 * 3.0, 0.01, "range noise tripled at severity 1")
		assert_true(float(o["t_delivered"]) - float(o["t"]) >= 0.39, "delay doubled at severity 1")


func test_tracker_creates_confirms_coasts_and_retires_a_track() -> void:
	var tracker := Tracker.new(Vector3(0, 25, 0), _definition()["config"]["sensor"])
	var obs := func(t: float, z: float) -> Dictionary:
		return {"id": "O%d" % int(t * 10), "sensor": "radar", "t": t, "position": Vector3(0, 60, z), "range_sigma_m": 5.0,
			"quality": 0.8, "degraded": false, "id_reply": false, "id_quality": false, "apparent_size_m": -1.0, "flap_detected": false}
	tracker.process([obs.call(1.0, -500.0)], 1.0)
	assert_eq(tracker.tracks.size(), 1, "track created")
	var id: String = tracker.tracks.keys()[0]
	assert_eq(tracker.tracks[id]["status"], "tentative", "starts tentative")
	tracker.process([obs.call(2.0, -490.0)], 2.0)
	tracker.process([obs.call(3.0, -480.0)], 3.0)
	assert_eq(tracker.tracks[id]["status"], "confirmed", "confirmed after 3 hits")
	assert_near((tracker.tracks[id]["velocity"] as Vector3).z, 10.0, 2.0, "velocity estimated ≈ +10 m/s")
	tracker.maintain(6.0)
	assert_eq(tracker.tracks[id]["status"], "coasting", "coasting after missed updates")
	assert_near(tracker.estimated_position(tracker.tracks[id], 6.0).z, -450.0, 8.0, "position extrapolated while coasting")
	tracker.process([obs.call(6.5, -445.0)], 6.5)
	assert_eq(tracker.tracks[id]["status"], "confirmed", "reacquired, not duplicated")
	assert_eq(tracker.tracks.size(), 1, "no duplicate track on reacquisition")
	tracker.maintain(16.0)
	assert_true(tracker.tracks.is_empty() and tracker.retired[0]["status"] == "lost", "retired as lost after 8 s without updates")
	var types := []
	for e in tracker.take_events():
		types.append(e["type"])
	assert_eq(types, ["track_created", "track_confirmed", "track_coasting", "track_reacquired", "track_coasting", "track_lost"], "lifecycle events (lost always follows coasting)")


func test_tracker_drops_unconfirmed_clutter_and_separates_distant_targets() -> void:
	var tracker := Tracker.new(Vector3(0, 25, 0), _definition()["config"]["sensor"])
	var make := func(id: String, t: float, p: Vector3) -> Dictionary:
		return {"id": id, "sensor": "radar", "t": t, "position": p, "range_sigma_m": 5.0, "quality": 0.5,
			"degraded": false, "id_reply": false, "id_quality": false, "apparent_size_m": -1.0, "flap_detected": false}
	tracker.process([make.call("c1", 1.0, Vector3(300, 50, -300))], 1.0)
	tracker.maintain(8.0)
	assert_eq(tracker.retired.size(), 1, "single clutter hit dropped")
	assert_eq(tracker.retired[0]["status"], "dropped", "dropped, not lost")
	for t in [10.0, 11.0, 12.0]:
		tracker.process([make.call("a%d" % t, t, Vector3(0, 50, -600)), make.call("b%d" % t, t, Vector3(200, 50, -600))], t)
	assert_eq(tracker.confirmed_tracks().size(), 2, "two separated targets give two tracks")


func test_swarm_members_keep_individual_tracks_and_form_one_group() -> void:
	var session := ThreatSession.new(ScenarioConfig.load_file("res://scenarios/02_swarm_urban_day.json")["config"])
	session.start()
	var largest := 0
	var group_ticks := 0
	for i in 20 * 120:
		session.step()
		for gid in session.tracker.groups:
			largest = maxi(largest, session.tracker.groups[gid]["members"].size())
		group_ticks += int(not session.tracker.groups.is_empty())
	assert_true(largest >= 3, "a group of at least 3 member tracks formed (largest %d)" % largest)
	assert_true(group_ticks > 20 * 10, "group persisted for more than 10 s (%.1f s)" % (group_ticks / 20.0))


func test_sensor_and_tracker_are_reproducible() -> void:
	var config: Dictionary = ScenarioConfig.load_file("res://scenarios/03_mixed_rural_night_degraded.json")["config"]
	var digests := []
	for run in 2:
		var session := ThreatSession.new(config)
		session.start()
		for i in 20 * 120:
			session.step()
		var parts := PackedStringArray()
		for o in session.observations:
			parts.append("%s:%.4f:%.4f" % [o["id"], o["range_m"], o["bearing_deg"]])
		for e in session.events:
			parts.append("%d:%s:%s" % [e["tick"], e["type"], e["data"].get("track_id", "")])
		digests.append(",".join(parts).hash())
	assert_eq(digests[0], digests[1], "identical observations and track events for the same seed")
