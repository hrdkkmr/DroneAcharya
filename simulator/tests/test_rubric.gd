extends "res://tests/test_case.gd"
## da-rubric-1 formulas, penalties, bounds and edge cases on hand-built records,
## plus an end-to-end scripted trainee on a real session.

const Rubric := preload("res://scripts/training/rubric.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const SessionRecord := preload("res://scripts/training/session_record.gd")

var _seq := 0


## Minimal record: actors [[id, profile, significant, group]], tracks [[id, confirmed_t, [obs ids]]],
## links {obs: actor}, id-quality availability seconds per actor {actor: [t...]}.
func _record(actors: Array, tracks: Array, links: Dictionary, available: Dictionary, degradation := []) -> Dictionary:
	_seq = 0
	var raw := {"format": "droneacharya-scenario", "version": 1, "id": "r", "seed": 1, "environment": "rural",
		"time_of_day": "day", "visibility": "clear", "duration_s": 120, "groups": [{"profile": "bird"}],
		"sensor": {"degradation": degradation}}
	var config: Dictionary = ScenarioConfig.validate(raw)["config"]
	var truth_actors := []
	for a in actors:
		truth_actors.append({"id": a[0], "profile": a[1], "significant": a[2], "group_id": a[3] if a.size() > 3 else "", "truth_category": "", "behavior": "", "spawn_tick": 0})
	var record_tracks := []
	for t in tracks:
		record_tracks.append({"id": t[0], "confirmed_t": t[1], "obs_ids": t[2], "status": "confirmed", "created_t": t[1] - 2.0, "retired_t": -1.0, "hits": t[2].size()})
	var samples := []
	for second in 121:
		var ids := []
		for actor in available:
			if float(second) in available[actor]:
				ids.append(actor)
		samples.append({"t": float(second), "active": [], "id": ids, "zone": []})
	return {"scenario": config, "status": "completed", "spam_count": 0, "events": [], "tracks": record_tracks,
		"truth": {"actors": truth_actors, "links": links, "availability": samples, "protected_zone_radius_m": 120.0}}


func _act(record: Dictionary, t: float, kind: String, track: String, data: Dictionary = {}) -> void:
	_seq += 1
	var payload := {"kind": kind, "track_id": track, "valid": true}
	payload.merge(data)
	record["events"].append({"seq": _seq, "tick": int(t * 20), "t": t, "type": "action", "data": payload})


func _range(a: int, b: int) -> Array:
	var r := []
	for i in range(a, b + 1):
		r.append(float(i))
	return r


func _threat_record() -> Dictionary:
	return _record([["A01", "unidentified_uav", true]], [["T001", 10.0, ["o1", "o2"]]], {"o1": "A01", "o2": "A01"}, {"A01": _range(10, 40)})


func test_perfect_run_scores_100() -> void:
	var r := _threat_record()
	_act(r, 12.0, "acknowledge", "T001")
	_act(r, 20.0, "classify", "T001", {"category": "unidentified_uav", "confidence": 80})
	_act(r, 22.0, "respond", "T001", {"response": "notify_supervisor"})
	var e := Rubric.evaluate(r)
	assert_eq(e["score"], 100.0, "perfect score")
	assert_eq(e["penalty_points"], 0.0, "no penalties")
	assert_eq(e["components"]["degraded"]["n"], 0, "no degraded objects")
	var total := 0.0
	for key in e["components"]:
		total += float(e["components"][key]["effective_weight"])
	assert_near(total, 100.0, 0.05, "unused degraded weight redistributed so weights still total 100")
	assert_true(e["comparable"], "comparable")


func test_detection_and_response_time_window_credit() -> void:
	var r := _threat_record()
	_act(r, 30.0, "acknowledge", "T001")
	_act(r, 31.0, "classify", "T001", {"category": "unidentified_uav", "confidence": 60})
	_act(r, 50.0, "respond", "T001", {"response": "notify_supervisor"})
	var c: Dictionary = Rubric.evaluate(r)["entities"][0]["credits"]
	assert_near(c["detection"], 0.4, 1e-6, "20 s after confirmation: (30-20)/(30-5) = 0.4")
	assert_near(c["response_time"], 0.4 + 0.6 * (60.0 - 40.0) / 45.0, 1e-6, "response 40 s after confirmation")
	assert_near(Rubric.window_credit(3.0, 5.0, 30.0), 1.0, 1e-9, "within grace = full credit")
	assert_near(Rubric.window_credit(45.0, 5.0, 30.0), 0.0, 1e-9, "after window = no credit")


func test_unknown_with_weak_evidence_is_rewarded_for_honesty() -> void:
	var r := _record([["A01", "unidentified_uav", true]], [["T001", 10.0, ["o1"]]], {"o1": "A01"}, {"A01": [11.0]})
	_act(r, 11.0, "acknowledge", "T001")
	_act(r, 12.0, "classify", "T001", {"category": "unknown", "confidence": 20})
	_act(r, 13.0, "respond", "T001", {"response": "request_identification"})
	var res: Dictionary = Rubric.evaluate(r)["entities"][0]
	assert_eq([res["credits"]["classification"], res["credits"]["evidence"], res["credits"]["response"]], [0.75, 1.0, 0.75], "unknown + weak evidence credits")
	assert_eq(res["evidence_s"], 1.0, "1 s of identification-quality availability counted")


func test_overconfident_wrong_call_is_penalised() -> void:
	var r := _record([["A01", "bird", false]], [["T001", 10.0, ["o1"]]], {"o1": "A01"}, {})
	_act(r, 11.0, "acknowledge", "T001")
	_act(r, 12.0, "classify", "T001", {"category": "unidentified_uav", "confidence": 90})
	_act(r, 13.0, "respond", "T001", {"response": "notify_supervisor"})
	var e := Rubric.evaluate(r)
	var res: Dictionary = e["entities"][0]
	assert_eq([res["credits"]["classification"], res["credits"]["evidence"], res["credits"]["response"]], [0.0, 0.25, 0.0], "wrong, weak, inappropriate")
	var rules := []
	for f in e["findings"]:
		if f["penalty"]:
			rules.append(f["rule"])
	rules.sort()
	assert_eq(rules, ["P1", "P2"], "over-confidence and false-alarm penalties")
	assert_near(e["penalty_points"], 12.0, 1e-6, "4 + 8 penalty points")


func test_missed_threat_and_clutter_false_alarm() -> void:
	var r := _record([["A01", "unidentified_uav", true]], [["T001", 10.0, ["o1"]], ["T002", 20.0, ["c1", "c2"]]], {"o1": "A01", "c1": "clutter", "c2": "clutter"}, {})
	_act(r, 21.0, "acknowledge", "T002")
	_act(r, 22.0, "classify", "T002", {"category": "unknown", "confidence": 10})
	_act(r, 23.0, "respond", "T002", {"response": "training_area_alert"})
	var e := Rubric.evaluate(r)
	var rules := []
	for f in e["findings"]:
		if f["penalty"]:
			rules.append(f["rule"])
	rules.sort()
	assert_eq(rules, ["P2", "P3"], "clutter alarm is a false alarm; the unanswered threat is missed")
	assert_eq(e["eligible_entities"], 1, "false tracks are not scored as objects")


func test_spam_penalty_is_capped_and_score_never_negative() -> void:
	var r := _threat_record()
	r["spam_count"] = 6
	assert_near(Rubric.evaluate(r)["findings"].filter(func(f): return f["rule"] == "P4")[0]["points"], 3.0, 1e-6, "6 spam actions: 3 over the allowance")
	r["spam_count"] = 50
	var e := Rubric.evaluate(r)
	assert_near(e["findings"].filter(func(f): return f["rule"] == "P4")[0]["points"], 5.0, 1e-6, "capped at 5")
	assert_eq(e["score"], 0.0, "score clamped at 0 (no actions plus penalties)")
	for key in e["components"]:
		var s: float = e["components"][key]["score"]
		assert_true(s >= 0.0 and s <= 100.0, "%s component within 0-100" % key)


func test_degraded_component_uses_objects_seen_during_degradation() -> void:
	var r := _record([["A01", "unidentified_uav", true], ["A02", "bird", false]],
		[["T001", 10.0, ["o1"]], ["T002", 70.0, ["o2"]]], {"o1": "A01", "o2": "A02"}, {"A01": _range(10, 20), "A02": _range(70, 80)},
		[{"start_s": 60.0, "end_s": 90.0, "severity": 0.5}])
	_act(r, 11.0, "acknowledge", "T001")
	_act(r, 12.0, "classify", "T001", {"category": "unidentified_uav", "confidence": 60})
	_act(r, 13.0, "respond", "T001", {"response": "notify_supervisor"})
	var e := Rubric.evaluate(r)
	assert_eq(e["components"]["degraded"]["n"], 1, "only the bird appeared near the degradation window")
	assert_eq(e["components"]["degraded"]["score"], 0.0, "bird was ignored under degradation")
	assert_eq(e["components"]["degraded"]["effective_weight"], 10.0, "degraded weight used as configured")


func test_swarm_is_one_entity_and_unconfirmed_objects_are_not_scored() -> void:
	var r := _record([["A01", "swarm_uav", true, "G01"], ["A02", "swarm_uav", true, "G01"], ["A03", "swarm_uav", true, "G01"], ["A04", "unidentified_uav", true]],
		[["T001", 10.0, ["o1"]], ["T002", 11.0, ["o2"]]], {"o1": "A01", "o2": "A02"}, {"A01": _range(10, 30)})
	_act(r, 12.0, "acknowledge", "T002")
	_act(r, 20.0, "classify", "T001", {"category": "swarm", "confidence": 80, "members": ["T001", "T002"]})
	_act(r, 21.0, "respond", "T001", {"response": "training_area_alert", "members": ["T001", "T002"]})
	var e := Rubric.evaluate(r)
	assert_eq(e["eligible_entities"], 1, "swarm is one entity; A04 never confirmed")
	assert_eq(e["entities"][0]["entity"], "G01", "scored as group G01")
	assert_near(e["entities"][0]["available_t"], 10.0, 1e-6, "available when the first member track was confirmed")
	assert_true(e["findings"].any(func(f): return f["rule"] == "N0" and f["entity"] == "A04"), "unconfirmed threat noted, not penalised")


func test_aborted_or_empty_sessions_are_not_comparable() -> void:
	var r := _threat_record()
	r["status"] = "aborted"
	assert_true(not Rubric.evaluate(r)["comparable"], "aborted is not comparable")
	var empty := _record([["A01", "bird", false]], [], {}, {})
	var e := Rubric.evaluate(empty)
	assert_true(not e["comparable"] and e["findings"].any(func(f): return f["rule"] == "E0"), "no confirmed objects: E0")


func test_scripted_trainee_end_to_end_is_deterministic() -> void:
	var results := []
	for run in 2:
		var session := ThreatSession.new(ScenarioConfig.load_file("res://scenarios/01_single_rural_day.json")["config"])
		session.start()
		while not session.is_finished():
			session.step()
			if session.tick() % 20 != 0:
				continue
			for track in session.tracker.confirmed_tracks():
				var state := session.trainee_state(track["id"])
				var advice: Dictionary = session.decisions.recommendation_for(track["id"])
				if advice.is_empty():
					continue
				if state.is_empty():
					session.acknowledge(track["id"])
				elif String(state["response"]).is_empty() and advice["rules"]["evidence"] != "insufficient":
					session.classify(track["id"], advice["rules"]["category"], int(advice["rules"]["confidence"] * 100))
					session.respond(track["id"], advice["policy"]["response"])
		var record := SessionRecord.build(session, "test", "2026-10-20T00:00:00Z")
		var e := Rubric.evaluate(record)
		results.append(e)
		assert_true(e["comparable"], "completed run is comparable")
		assert_true(e["score"] > 40.0, "a trainee following the baseline scores reasonably (%.1f)" % e["score"])
	assert_eq(results[0], results[1], "identical evaluation for identical inputs")
