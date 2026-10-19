extends "res://tests/test_case.gd"
## Session records: schema validation, save/load, history, export/import,
## deterministic replay and after-action review content.

const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const SessionRecord := preload("res://scripts/training/session_record.gd")
const SessionIO := preload("res://scripts/training/session_io.gd")
const Replay := preload("res://scripts/training/replay.gd")
const Aar := preload("res://scripts/training/aar.gd")
const Rubric := preload("res://scripts/training/rubric.gd")
const MlClassifier := preload("res://scripts/ai/ml_classifier.gd")

const DIR := "user://test_runs/session_files"


## Plays a scenario with a scripted trainee that also pauses, makes invalid and
## repeated actions and toggles decision support. Returns the evaluated record.
func _play(path: String, session_id: String, abort_at_s := -1.0) -> Dictionary:
	var session := ThreatSession.new(ScenarioConfig.load_file(path)["config"], MlClassifier.shared())
	session.start()
	var paused_once := false
	while not session.is_finished():
		session.step()
		if abort_at_s > 0.0 and session.time_s() >= abort_at_s:
			session.abort()
			break
		if session.tick() % 20 != 0:
			continue
		if not paused_once and session.time_s() >= 20.0:
			paused_once = true
			session.pause()
			session.acknowledge("T001")
			session.resume()
			session.log_event("decision_support_visible", {"visible": false})
			session.acknowledge("T999")
		for track in session.tracker.confirmed_tracks():
			var state := session.trainee_state(track["id"])
			var advice: Dictionary = session.decisions.recommendation_for(track["id"])
			if advice.is_empty():
				continue
			if state.is_empty():
				session.acknowledge(track["id"])
				session.acknowledge(track["id"])
			elif String(state["response"]).is_empty() and advice["rules"]["evidence"] != "insufficient":
				session.classify(track["id"], "fighter", 50)
				session.classify(track["id"], advice["rules"]["category"], 90)
				session.respond(track["id"], advice["policy"]["response"])
	var record := SessionRecord.build(session, session_id, "2026-10-20T10:00:00Z")
	record["evaluation"] = Rubric.evaluate(record)
	return record


func _clean_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(name))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_record_validates_and_survives_a_file_round_trip() -> void:
	_clean_dir()
	var record := _play("res://scenarios/01_single_rural_day.json", "rt-1")
	var check := SessionIO.validate(record)
	assert_true(check["ok"], "fresh record valid: " + "; ".join(check["errors"]))
	var saved := SessionIO.save(record, DIR)
	assert_true(saved["ok"], "saved: " + str(saved.get("error", "")))
	var loaded := SessionIO.load_file(saved["path"])
	assert_true(loaded["ok"], "reloaded file valid: " + "; ".join(loaded["errors"]))
	assert_eq(SessionIO.canonical(loaded["record"]), SessionIO.canonical(record), "identical content after reload")
	var bytes := FileAccess.get_file_as_bytes(saved["path"]).size()
	print("     session file size: %.0f KB (%d events, %d observations)" % [bytes / 1024.0, record["events"].size(), record["observations"]["rows"].size()])
	assert_true(bytes < SessionIO.MAX_FILE_BYTES, "within the size limit")
	assert_true(SessionIO.save(record, DIR)["ok"], "saving identical content again is harmless")
	var changed := record.duplicate(true)
	changed["created_at"] = "2026-10-21T00:00:00Z"
	assert_true(not SessionIO.save(changed, DIR)["ok"], "a different session with the same id is not overwritten")


func test_invalid_or_tampered_records_are_rejected() -> void:
	var record := _play("res://scenarios/01_single_rural_day.json", "bad-1")
	var cases := {
		"stored evaluation does not match": func(r): r["evaluation"]["score"] = 100.0,
		"format must be": func(r): r["format_version"] = 2,
		"missing field: truth": func(r): r.erase("truth"),
		"contiguous": func(r): r["events"][3]["seq"] = 99,
		"must not decrease": func(r): r["events"][-2]["tick"] = 0,
		"unknown observation": func(r): r["tracks"][0]["obs_ids"].append("O999999"),
		"status": func(r): r["status"] = "won",
		"scenario invalid": func(r): r["scenario"]["environment"] = "moon",
		"unknown actor": func(r): r["truth"]["links"][r["truth"]["links"].keys()[0]] = "A99",
	}
	for expected in cases:
		var copy: Dictionary = record.duplicate(true)
		cases[expected].call(copy)
		var check := SessionIO.validate(copy)
		assert_true(not check["ok"], "rejected: " + expected)
		assert_true(", ".join(check["errors"]).contains(expected), "reason mentions '%s': %s" % [expected, "; ".join(check["errors"])])
	_clean_dir()
	_write(DIR + "/truncated.json", JSON.stringify(record).substr(0, 500))
	assert_true(not SessionIO.load_file(DIR + "/truncated.json")["ok"], "truncated JSON rejected")


func test_history_lists_valid_sessions_and_quarantines_invalid_files() -> void:
	_clean_dir()
	var a := _play("res://scenarios/01_single_rural_day.json", "hist-a")
	var b := a.duplicate(true)
	b["session_id"] = "hist-b"
	b["created_at"] = "2026-10-20T11:00:00Z"
	SessionIO.save(a, DIR)
	SessionIO.save(b, DIR)
	_write(DIR + "/broken.json", "{oops")
	var history := SessionIO.list_history(DIR)
	assert_eq(history["sessions"].size(), 2, "two valid sessions")
	assert_eq(history["sessions"][0]["session_id"], "hist-b", "newest first")
	assert_eq(history["invalid"].size(), 1, "one invalid file listed")
	assert_eq(FileAccess.get_file_as_string(DIR + "/broken.json"), "{oops", "invalid file left untouched")


func test_export_and_import_bundles_merge_without_overwriting() -> void:
	_clean_dir()
	var a := _play("res://scenarios/01_single_rural_day.json", "bundle-a")
	var bundle_path := "user://test_runs/exports/history.json"
	assert_true(SessionIO.export_bundle([a], bundle_path)["ok"], "exported")
	var first := SessionIO.import_bundle(bundle_path, DIR)
	assert_eq([first["ok"], first.get("added")], [true, 1], "imported into an empty history")
	var again := SessionIO.import_bundle(bundle_path, DIR)
	assert_eq([again["ok"], again.get("added"), again.get("skipped")], [true, 0, 1], "identical duplicate skipped")
	var conflicting := a.duplicate(true)
	conflicting["created_at"] = "2026-10-22T00:00:00Z"
	SessionIO.export_bundle([conflicting], bundle_path)
	var conflict := SessionIO.import_bundle(bundle_path, DIR)
	assert_true(not conflict["ok"] and "conflicts" in conflict["error"], "conflict rejected: " + str(conflict.get("error")))
	var tampered := a.duplicate(true)
	tampered["session_id"] = "bundle-b"
	tampered["evaluation"]["score"] = 0.0
	SessionIO.export_bundle([tampered], bundle_path)
	assert_true(not SessionIO.import_bundle(bundle_path, DIR)["ok"], "tampered session rejected")
	assert_eq(SessionIO.list_history(DIR)["sessions"].size(), 1, "nothing partially imported")


func test_replay_reproduces_events_and_evaluation_exactly() -> void:
	var record := _play("res://scenarios/02_swarm_urban_day.json", "replay-1")
	var result := Replay.new(record, MlClassifier.shared()).verify()
	assert_true(result["identical"], "identical replay: " + result["first_difference"])
	assert_true(result["warnings"].is_empty(), "no version warnings")
	_clean_dir()
	var loaded := SessionIO.load_file(SessionIO.save(record, DIR)["path"])
	assert_true(Replay.new(loaded["record"], MlClassifier.shared()).verify()["identical"], "replay from the saved file is identical too")
	var aborted := _play("res://scenarios/01_single_rural_day.json", "replay-2", 45.0)
	assert_eq(aborted["status"], "aborted", "aborted run recorded")
	assert_true(Replay.new(aborted, MlClassifier.shared()).verify()["identical"], "aborted run replays identically")


func test_replay_reports_a_missing_ml_model() -> void:
	var record := _play("res://scenarios/01_single_rural_day.json", "replay-3")
	var runner := Replay.new(record, null)
	assert_true(runner.warnings.size() > 0 and "not available" in runner.warnings[0], "missing model reported")
	assert_true(not runner.verify()["identical"], "outputs differ without the recorded model, and the difference is reported")


func test_after_action_review_explains_the_result() -> void:
	var record := _play("res://scenarios/03_mixed_rural_night_degraded.json", "aar-1")
	var text := Aar.report(record)
	for fragment in ["/ 100", "Objects (ground truth revealed)", "Missed threats:", "False alarms:", "Decision timeline",
			"Model recommendation vs your response", "Why points were lost", "Suggested areas for improvement", "Rejected:"]:
		assert_true(fragment in text, "review contains '%s'" % fragment)
	assert_true(Aar.suggestions(record).size() >= 1, "at least one suggestion")


func test_committed_example_session_is_valid_and_reproducible() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../schemas/examples/session_example.json").simplify_path()
	var loaded := SessionIO.load_file(path)
	assert_true(loaded["ok"], "example passes the GDScript validator: " + "; ".join(loaded["errors"]))
	var rebuilt: Dictionary = load("res://tools/export_sample_session.gd").build()
	assert_eq(SessionIO.canonical(rebuilt), SessionIO.canonical(loaded["record"]), "the export tool reproduces the committed example exactly")
