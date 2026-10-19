extends "res://tests/test_case.gd"
## Features, Model 1 (rules), Model 3 (policy), truth isolation and the trainee
## action workflow.

const Features := preload("res://scripts/ai/features.gd")
const RuleEngine := preload("res://scripts/ai/rule_engine.gd")
const DecisionPolicy := preload("res://scripts/ai/decision_policy.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")

const CONTEXT := {"wind": Vector3(4, 0, 0), "zone_center": Vector3.ZERO, "zone_radius": 100.0, "observer": Vector3(0, 25, 0)}


## A track that moved with constant velocity `v` for `seconds`, sampled every second.
func _track(id: String, start: Vector3, v: Vector3, seconds: int, extra: Dictionary = {}) -> Dictionary:
	var history := []
	for i in seconds + 1:
		history.append({"t": float(i), "position": start + v * i, "velocity": v, "sensor": "radar"})
	var track := {"id": id, "status": "confirmed", "created_t": 0.0, "last_update_t": float(seconds), "position": start + v * seconds,
		"velocity": v, "hits": seconds + 1, "radar_hits": seconds + 1, "eo_hits": 0, "eo_id_hits": 0, "id_replies": 0,
		"sizes": [], "flaps": 0, "quality_sum": 0.8 * (seconds + 1), "degraded_hits": 0, "history": history, "swarm_group": ""}
	track.merge(extra, true)
	return track


func _features(overrides: Dictionary) -> Dictionary:
	var f := {}
	for name in Features.NAMES:
		f[name] = 0.0
	f.merge({"duration_s": 30.0, "hits": 40.0, "radar_hits": 30.0, "speed_mean": 8.0, "air_speed_mean": 8.0, "zone_distance_last": 5.0}, true)
	f.merge(overrides, true)
	return f


func test_feature_values_for_a_straight_constant_track() -> void:
	var track := _track("T001", Vector3(500, 60, 0), Vector3(-6, 0, 0), 20)
	var f := Features.extract(track, [track], CONTEXT, 20.0)
	assert_eq(f.keys(), Features.NAMES, "every feature present, in the documented order")
	assert_near(f["speed_mean"], 6.0, 1e-6, "mean speed")
	assert_near(f["straightness"], 1.0, 1e-6, "straight path")
	assert_near(f["turn_rate_mean_dps"], 0.0, 1e-6, "no turning")
	assert_near(f["air_speed_mean"], 10.0, 1e-6, "air speed = |v - wind| (flying into a 4 m/s tailwind reversed)")
	assert_near(f["wind_alignment"], -1.0, 1e-6, "flies against the wind")
	assert_near(f["zone_distance_last"], 3.8, 1e-6, "distance to zone in zone radii")
	assert_near(f["duration_s"], 20.0, 1e-6, "duration")
	assert_eq(Features.to_vector(f).size(), Features.NAMES.size(), "vector length")


func test_neighbour_features_count_tracks_moving_together() -> void:
	var a := _track("T001", Vector3(400, 60, 0), Vector3(5, 0, 0), 10)
	var b := _track("T002", Vector3(420, 60, 0), Vector3(5, 0, 0), 10)
	var c := _track("T003", Vector3(400, 60, 30), Vector3(5.5, 0, 0), 10)
	var far := _track("T004", Vector3(900, 60, 0), Vector3(5, 0, 0), 10)
	var opposite := _track("T005", Vector3(410, 60, 10), Vector3(-5, 0, 0), 10)
	var f := Features.extract(a, [a, b, c, far, opposite], CONTEXT, 10.0)
	assert_eq(f["neighbor_count"], 2.0, "two close tracks with similar velocity")


func test_rules_fire_in_documented_order() -> void:
	var cases := [
		[{"duration_s": 3.0}, "unknown", "R0_INSUFFICIENT", "insufficient"],
		[{"id_reply_fraction": 0.9, "neighbor_count": 3.0}, "authorised_uav", "R1_ID_REPLY", "good"],
		[{"neighbor_count": 2.0}, "swarm", "R2_SWARM", "good"],
		[{"air_speed_mean": 1.0, "wind_alignment": 0.9, "speed_mean": 4.0}, "balloon", "R3_WIND_DRIFT", "good"],
		[{"eo_id_hits": 6.0, "flap_fraction": 0.8, "has_size": 1.0, "size_mean": 0.6}, "bird", "R4_WING_BEAT", "good"],
		[{"turn_rate_mean_dps": 40.0, "speed_mean": 9.0}, "bird", "R5_ERRATIC", "good"],
		[{"has_size": 1.0, "size_mean": 1.8, "speed_mean": 2.0, "eo_id_hits": 2.0}, "balloon", "R6_LARGE_SLOW", "good"],
		[{"turn_rate_mean_dps": 10.0}, "unidentified_uav", "R7_UAV_KINEMATICS", "good"],
		[{"speed_mean": 30.0, "air_speed_mean": 30.0}, "unknown", "R8_NO_MATCH", "good"],
	]
	for c in cases:
		var a := RuleEngine.assess(_features(c[0]))
		assert_eq([a["category"], a["rule"], a["evidence"]], [c[1], c[2], c[3]], "rule %s" % c[2])
		assert_true(a["explanation"].length() > 10, "%s explained" % c[2])
		assert_eq(a["method"], "rule-based", "labelled rule-based, not ML")
	var fair := RuleEngine.assess(_features({"radar_hits": 8.0, "duration_s": 10.0, "turn_rate_mean_dps": 10.0}))
	assert_eq(fair["evidence"], "fair", "less evidence is 'fair'")
	assert_near(fair["confidence"], 0.65 * 0.85, 0.01, "fair evidence lowers the rule confidence")


func test_policy_maps_assessments_to_procedural_responses() -> void:
	var f := _features({})
	var cases := [
		[{"category": "unknown", "confidence": 0.3, "evidence": "insufficient"}, {"speed_mean": 8.0}, "request_identification", "P_INSUFFICIENT_UAV_LIKE"],
		[{"category": "unknown", "confidence": 0.3, "evidence": "insufficient"}, {"speed_mean": 1.0}, "continue_observing", "P_INSUFFICIENT"],
		[{"category": "unknown", "confidence": 0.35, "evidence": "good"}, {}, "request_identification", "P_UNKNOWN"],
		[{"category": "unidentified_uav", "confidence": 0.5, "evidence": "fair"}, {}, "request_identification", "P_LOW_CONFIDENCE"],
		[{"category": "bird", "confidence": 0.85, "evidence": "good"}, {}, "log_observation", "P_BACKGROUND"],
		[{"category": "authorised_uav", "confidence": 0.85, "evidence": "good"}, {}, "log_observation", "P_COOPERATIVE"],
		[{"category": "unidentified_uav", "confidence": 0.65, "evidence": "good"}, {"zone_distance_last": 3.0}, "notify_supervisor", "P_UNIDENTIFIED"],
		[{"category": "unidentified_uav", "confidence": 0.65, "evidence": "good"}, {"zone_distance_last": 0.6}, "training_area_alert", "P_UNIDENTIFIED_IN_ZONE"],
		[{"category": "swarm", "confidence": 0.8, "evidence": "good"}, {}, "training_area_alert", "P_SWARM"],
	]
	for c in cases:
		var features := f.duplicate()
		features.merge(c[1], true)
		var r := DecisionPolicy.recommend(c[0], features)
		assert_eq([r["response"], r["reason_code"]], [c[2], c[3]], "policy %s" % c[3])
		assert_true(r["explanation"].length() > 10, "%s explained" % c[3])


func _session(path: String) -> ThreatSession:
	var session := ThreatSession.new(ScenarioConfig.load_file(path)["config"])
	session.start()
	return session


func test_decisions_never_read_ground_truth_labels() -> void:
	var a := _session("res://scenarios/03_mixed_rural_night_degraded.json")
	var b := _session("res://scenarios/03_mixed_rural_night_degraded.json")
	for actor in b.definition["actors"]:
		actor["profile"] = "bird"
		actor["truth_category"] = "background"
		actor["significant"] = false
		actor["group_id"] = ""
	for i in 20 * 120:
		a.step()
		b.step()
	var outputs_a := []
	var outputs_b := []
	for e in a.events:
		if e["type"] == "model_output":
			outputs_a.append(e["data"])
	for e in b.events:
		if e["type"] == "model_output":
			outputs_b.append(e["data"])
	assert_true(outputs_a.size() > 5, "model outputs produced (%d)" % outputs_a.size())
	assert_eq(outputs_a, outputs_b, "identical model outputs after changing every truth label")
	for id in a.decisions.latest:
		assert_eq(a.decisions.latest[id]["features"].keys(), Features.NAMES, "features contain only documented inputs")


func test_trainee_workflow_rules_and_spam() -> void:
	var session := _session("res://scenarios/01_single_rural_day.json")
	while session.tracker.confirmed_tracks().is_empty():
		session.step()
	var id: String = session.tracker.confirmed_tracks()[0]["id"]
	assert_true(not session.classify(id, "bird", 50)["ok"], "cannot classify before acknowledging")
	assert_true(not session.respond(id, "log_observation")["ok"], "cannot respond before classifying")
	assert_eq(session.spam_count, 0, "workflow-order mistakes are not spam")
	assert_true(session.acknowledge(id)["ok"], "acknowledge")
	assert_true(not session.acknowledge(id)["ok"], "second acknowledge rejected")
	assert_eq(session.spam_count, 1, "repeated acknowledge counts as spam")
	assert_true(not session.classify(id, "fighter", 50)["ok"], "unknown category rejected")
	assert_true(not session.classify(id, "bird", 150)["ok"], "confidence out of range rejected")
	for i in 4:
		assert_true(session.classify(id, "unknown", 30)["ok"], "re-classification %d allowed" % (i + 1))
	assert_eq(session.spam_count, 2, "fourth classification counts as spam")
	assert_true(session.respond(id, "continue_observing")["ok"], "respond")
	assert_true(not session.respond(id, "log_observation")["ok"], "second response rejected")
	assert_true(not session.acknowledge("T999")["ok"], "unknown track rejected")
	assert_eq(session.spam_count, 4, "duplicate response and unknown track count as spam")
	var response_event: Dictionary = {}
	for e in session.events:
		if e["type"] == "action" and e["data"]["kind"] == "respond" and e["data"]["valid"]:
			response_event = e
	assert_true(response_event["data"].has("model_recommendation"), "model recommendation recorded with the response")
	session.pause()
	assert_true(not session.acknowledge(id)["ok"], "no actions while paused")


func test_swarm_actions_apply_to_the_whole_group() -> void:
	var session := _session("res://scenarios/02_swarm_urban_day.json")
	var group := {}
	while group.is_empty() and session.time_s() < 140.0:
		session.step()
		for gid in session.tracker.groups:
			group = session.tracker.groups[gid]
	assert_true(not group.is_empty(), "swarm group observed")
	var members: Array = group["members"]
	session.acknowledge(members[0])
	session.classify(members[0], "swarm", 70)
	session.respond(members[0], "training_area_alert")
	for id in members:
		var state := session.trainee_state(id)
		assert_eq([state["category"], state["response"]], ["swarm", "training_area_alert"], "%s covered by the group decision" % id)
