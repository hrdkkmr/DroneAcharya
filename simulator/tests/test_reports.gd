extends "res://tests/test_case.gd"
## Plain-language reports: every statement comes from the record, no filler, limits
## respected, old/unknown versions handled, and reports reload from disk.

const AppState := preload("res://scripts/app/app_state.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const SessionRecord := preload("res://scripts/training/session_record.gd")
const SessionIO := preload("res://scripts/training/session_io.gd")
const Rubric := preload("res://scripts/training/rubric.gd")
const ReportBuilder := preload("res://scripts/training/report_builder.gd")
const FlightRecord := preload("res://scripts/flight/flight_record.gd")
const FlightMissions := preload("res://scripts/flight/flight_missions.gd")
const DroneProfiles := preload("res://scripts/flight/drone_profiles.gd")
const MissionState := preload("res://scripts/mission/mission_state.gd")
const Vocabulary := preload("res://scripts/ai/vocabulary.gd")


## Runs a scenario to the end; `decide(session, track)` is called once per second for
## every confirmed track after `start_s`.
func _session(path: String, decide: Callable, start_s := 20.0) -> Dictionary:
	var session := ThreatSession.new(ScenarioConfig.load_file(path)["config"], null)
	session.start()
	while not session.is_finished():
		session.step()
		if session.tick() % 20 == 0 and session.time_s() >= start_s:
			for track in session.tracker.confirmed_tracks():
				decide.call(session, track)
	var record := SessionRecord.build(session, "report-test-%d" % session.tick(), "2026-10-20T10:00:00Z")
	record["evaluation"] = Rubric.evaluate(record)
	return record


func _text(report: Dictionary) -> String:
	return ReportBuilder.to_text(report)


func _check_limits_and_language(report: Dictionary) -> void:
	assert_true(report["went_well"].size() <= 3 and report["improve"].size() <= 3, "at most three strengths and three improvements")
	assert_true(report["next"].size() >= 1 and report["next"].size() <= 3, "one to three next steps")
	var lower := _text(report).to_lower() + String(report["details"]).to_lower()
	for phrase in ReportBuilder.BANNED:
		assert_true(not phrase in lower, "report avoids '%s'" % phrase)


## Test-only helper: the category a correct trainee would choose for a track (from
## the truth links, which the trainee never sees).
func _truth_category(session: RefCounted, track: Dictionary) -> String:
	var votes := {}
	for obs_id in track["obs_ids"]:
		var source: String = session.sensor.truth_links.get(obs_id, "clutter")
		votes[source] = votes.get(source, 0) + 1
	var best := ""
	for source in votes:
		if best.is_empty() or votes[source] > votes[best]:
			best = source
	for actor in session.definition["actors"]:
		if actor["id"] == best:
			return Vocabulary.TRUTH_CATEGORY_FOR_PROFILE[actor["profile"]]
	return "unknown"


func test_correct_decisions_are_reported_with_their_numbers() -> void:
	var record := _session("res://scenarios/01_single_rural_day.json", func(s, t):
		if s.trainee_state(t["id"]).is_empty() and t["hits"] >= 6:
			var category := _truth_category(s, t)
			s.classify(t["id"], category, 60, true)
			s.respond(t["id"], "notify_supervisor" if category == "unidentified_uav" else "log_observation"))
	var report := ReportBuilder.build(record)
	var e: Dictionary = record["evaluation"]
	var correct: int = e["entities"].filter(func(x): return x["correct"]).size()
	assert_true(correct >= 1, "the scripted decision was correct")
	assert_true("You identified %d of %d contacts correctly." % [correct, e["entities"].size()] in report["went_well"], "strength backed by the count: %s" % str(report["went_well"]))
	assert_true(report["timeline"].any(func(row): return row["result"] == "correct" and "Unidentified UAV" in row["decision"]), "timeline shows the decision and its assessment")
	assert_true("%.1f / 100" % e["score"] in _text(report), "final score from the evaluation")
	assert_true(not report["improve"].any(func(line): return "classified" in line and "it was" in line), "no invented errors")
	_check_limits_and_language(report)


func test_errors_missed_contacts_and_false_alarms_are_named() -> void:
	var record := _session("res://scenarios/03_mixed_rural_night_degraded.json", func(s, t):
		if s.trainee_state(t["id"]).is_empty() and t["id"] < "T004":
			s.classify(t["id"], "bird", 90, true)
			s.respond(t["id"], "training_area_alert"))
	var report := ReportBuilder.build(record)
	var e: Dictionary = record["evaluation"]
	var text := _text(report)
	var p2: int = e["findings"].filter(func(f): return f["rule"] == "P2").size()
	var wrong: int = e["entities"].filter(func(x): return not String(x["category"]).is_empty() and x["category"] != "unknown" and not x["correct"]).size()
	var never: Array = e["entities"].filter(func(x): return float(x["ack_t"]) < 0.0)
	if p2 > 0:
		assert_true(report["improve"].any(func(line): return line.begins_with("You raised an alarm for")), "unnecessary alert named")
	var p3: int = e["findings"].filter(func(f): return f["rule"] == "P3").size()
	if wrong > 0 and int(p3 > 0) + int(p2 > 0) < 3:
		assert_true(report["improve"].any(func(line): return line.begins_with("You classified") and "Bird (biological)" in line), "wrong classification named with the truth: %s" % str(report["improve"]))
	if not never.is_empty() and report["improve"].size() < 3:
		var expected := "You missed a contact that appeared at %02d:%02d" % [int(never[0]["available_t"]) / 60, int(never[0]["available_t"]) % 60]
		assert_true(report["improve"].any(func(line): return line.begins_with(expected)), "missed contact with its real time: %s" % str(report["improve"]))
	assert_true(p2 + wrong + never.size() > 0, "the scripted run produced errors to report")
	assert_true("Contacts" in text and "unnecessary alert" in text, "summary distinguishes outcome kinds")
	assert_true(not report["next"].is_empty(), "next practice suggested from the errors")
	_check_limits_and_language(report)


func test_no_actions_gives_missed_contacts_and_no_praise() -> void:
	var record := _session("res://scenarios/01_single_rural_day.json", func(_s, _t): pass)
	var report := ReportBuilder.build(record)
	assert_true(not report["went_well"].any(func(line): return "identified" in line), "no strength without a correct decision")
	assert_true(report["improve"].any(func(line): return line.begins_with("You missed a contact")), "missed contact reported")
	assert_true(report["timeline"].any(func(row): return row["result"] == "missed"), "missed contact on the timeline")
	_check_limits_and_language(report)


func test_reports_reload_identically_from_disk() -> void:
	var dir := "user://test_runs/report_sessions"
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	var record := _session("res://scenarios/01_single_rural_day.json", func(s, t):
		if s.trainee_state(t["id"]).is_empty():
			s.classify(t["id"], "unknown", 30, true))
	assert_true(SessionIO.save(record, dir)["ok"], "saved")
	var loaded: Array = SessionIO.list_history(dir)["sessions"]
	assert_eq(loaded.size(), 1, "reloaded after a restart")
	assert_eq(_text(ReportBuilder.build(loaded[0])), _text(ReportBuilder.build(record)), "same report from the saved file")


func _flight_record(completed: bool) -> Dictionary:
	var state := MissionState.new(4, 180.0, 600.0)
	state.update(2.0, false, false, 3.0, 0.1)
	for i in 4:
		for k in 60:
			state.update(8.0, false, false, 6.0, 0.1)
		state.pass_checkpoint(i)
		if i == 1:
			state.record_bump("Streetlight", 1.6)
	if completed:
		for k in 30:
			state.update(0.0, true, true, 0.0, 0.1)
	else:
		state.fail("collided with Building at 4.2 m/s")
	var mission := FlightMissions.get_mission("city_delivery")
	return FlightRecord.build(state, mission, "scout", DroneProfiles.get_profile("scout"), "flight-test-%s" % completed, "2026-10-20T11:00:00Z")


func test_flight_report_reports_time_checkpoints_collisions_and_landing() -> void:
	var record := _flight_record(true)
	var report := ReportBuilder.build(record)
	var elapsed := float(record["result"]["elapsed_s"])
	assert_true("You reached the landing zone in %02d:%02d." % [int(elapsed) / 60, int(elapsed) % 60] in report["went_well"], "landing time stated: %s" % str(report["went_well"]))
	assert_true(report["improve"].any(func(line): return "touched obstacles 1 time (Streetlight)" in line), "minor collision named")
	assert_true(report["timeline"].any(func(row): return row["subject"] == "Ring 4 of 4" and row["result"] == "passed"), "checkpoint on the timeline")
	var categories := {}
	for row in report["categories"]:
		categories[row[0]] = row[1]
	assert_eq(categories.get("Landing"), "landed in the zone", "landing result")
	assert_eq(categories.get("Checkpoints"), "4 of 4", "checkpoints")
	_check_limits_and_language(report)
	var failed := ReportBuilder.build(_flight_record(false))
	assert_true(failed["improve"][0].begins_with("The mission failed at") and "collided with Building" in failed["improve"][0], "failure and its cause")
	assert_true(failed["next"].any(func(line): return "Slow down near buildings" in line), "next practice follows from the crash")
	_check_limits_and_language(failed)


func test_unknown_record_versions_are_not_guessed() -> void:
	var record := _flight_record(true)
	record["format_version"] = 7
	var report := ReportBuilder.build(record)
	assert_eq(report["kind"], "unsupported", "unknown version recognised")
	assert_true(report["improve"].is_empty() and report["went_well"].is_empty(), "no statements invented for it")


func test_history_lists_flight_and_threat_reports() -> void:
	var dir: String = AppState.flight_sessions_dir
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	var flight := _flight_record(true)
	assert_true(FlightRecord.save(flight, dir)["ok"], "flight record saved")
	AppState.review_session = flight
	AppState.goto(tree, "history")
	var history: Node = null
	for i in 10:
		await tree.process_frame
		if tree.current_scene and tree.current_scene.scene_file_path == AppState.SCENES["history"]:
			history = tree.current_scene
			break
	assert_true(history != null, "history opened")
	assert_true(history.flights.size() == 1, "flight record listed")
	assert_eq(history.selected.get("session_id"), flight["session_id"], "the flight report is selected")
	assert_true("Mission result" in history.report_label.text and "City delivery" in history.report_label.text, "flight report shown")
	assert_true(history.replay_button.disabled, "no 3D replay for flight records")
	history.toggle_details()
	assert_true(history.details_label.visible and "Event log" in history.details_label.text, "details on request")
	AppState.review_session = {}


## Regression: a flight record with the right keys but wrong contents passed validation
## and stopped the history screen with a script error, hiding every other report.
func test_malformed_flight_records_are_listed_as_invalid_not_shown() -> void:
	var dir: String = AppState.flight_sessions_dir
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	var good := _flight_record(true)
	assert_true(FlightRecord.validate(good)["ok"], "a record built by the simulator is valid")
	assert_true(FlightRecord.save(good, dir)["ok"], "valid record saved")
	var bad_mission := _flight_record(false)
	bad_mission["session_id"] = "flight-bad-mission"
	bad_mission["mission"] = "not a dictionary"
	var bad_event := _flight_record(false)
	bad_event["session_id"] = "flight-bad-event"
	bad_event["events"].append({"t": 1.0, "type": "bump", "data": {}})
	for record in [bad_mission, bad_event]:
		assert_true(not FlightRecord.validate(record)["ok"], "%s refused" % record["session_id"])
		var file := FileAccess.open(dir.path_join(record["session_id"] + ".json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(record))
		file.close()
	AppState.review_session = {}
	AppState.goto(tree, "history")
	var history: Node = null
	for i in 10:
		await tree.process_frame
		if tree.current_scene and tree.current_scene.scene_file_path == AppState.SCENES["history"]:
			history = tree.current_scene
			break
	assert_true(history != null, "history opened")
	assert_eq(history.flights.size(), 1, "the valid flight record is still listed")
	var refused: Array = history.invalid.filter(func(i): return String(i["file"]).begins_with("flight-bad-"))
	assert_eq(refused.size(), 2, "both malformed files reported as invalid")
	assert_true("flight-bad-mission.json" in history.invalid_label.text, "invalid files named on screen")
	assert_true("Mission result" in history.report_label.text, "the valid report is shown")
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
