extends "res://tests/test_case.gd"
## Phase 3: tutorial, mouse-first decision card, observation radar and swarm groups.

const AppState := preload("res://scripts/app/app_state.gd")
const SettingsStore := preload("res://scripts/app/settings_store.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const SessionRecord := preload("res://scripts/training/session_record.gd")
const Rubric := preload("res://scripts/training/rubric.gd")
const Vocabulary := preload("res://scripts/ai/vocabulary.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")


func _wait_scene(path: String) -> Node:
	for i in 10:
		await tree.process_frame
		if tree.current_scene != null and tree.current_scene.scene_file_path == path:
			return tree.current_scene
	failures.append("scene did not change to " + path)
	return null


func _observe(path: String, seconds: float) -> Node:
	AppState.selected_config = ScenarioConfig.load_file(path)["config"]
	AppState.goto(tree, "observation")
	var scene: Node = await _wait_scene(AppState.SCENES["observation"])
	while scene.session.time_s() < seconds:
		scene.session.step()
	await tree.process_frame
	return scene


func _mouse(button: MouseButton, pressed: bool, position := Vector2(800, 450), shift := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	event.global_position = position
	event.shift_pressed = shift
	Input.parse_input_event(event)
	await tree.process_frame


func _motion(position: Vector2, held: MouseButtonMask) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = held
	Input.parse_input_event(event)
	await tree.process_frame


func _actions(session: RefCounted) -> Array:
	return session.events.filter(func(e): return e["type"] == "action")


func test_first_visit_opens_the_tutorial_which_can_be_skipped_with_confirmation() -> void:
	SettingsStore.set_value("tutorial_done", false)
	AppState.selected_config = {}
	var menu := add_scene("res://scenes/main.tscn")
	await tree.process_frame
	assert_true(not menu.buttons["tutorial"].disabled, "tutorial link enabled")
	menu.buttons["briefing"].pressed.emit()
	var tutorial := await _wait_scene(AppState.SCENES["tutorial"])
	assert_true(tutorial != null, "first threat-detection visit opens the tutorial")
	var panel = tutorial.panel
	var finished := []
	panel.finished.connect(func(skipped): finished.append(skipped))
	panel.request_skip()
	assert_true(panel.skip_confirm.visible and finished.is_empty(), "skip asks for confirmation first")
	panel.confirm_skip()
	await _wait_scene(AppState.SCENES["briefing"])
	assert_eq(finished, [true], "skipped")
	assert_eq(SettingsStore.get_value("tutorial_done"), true, "tutorial remembered as done")
	assert_eq(AppState.selected_config.get("id"), "single-rural-day", "briefing has the default scenario")
	SettingsStore.set_value("tutorial_done", false)


func test_tutorial_steps_and_practice_interactions() -> void:
	AppState.goto(tree, "tutorial")
	var tutorial := await _wait_scene(AppState.SCENES["tutorial"])
	var panel = tutorial.panel
	assert_eq(panel.step_index, 0, "starts at step 1")
	assert_true(panel.back_button.disabled, "no Back on the first step")
	panel.next()
	panel.next()
	panel.next()
	assert_eq(panel.STEPS[panel.step_index]["diagram"], "practice_select", "practice: select a contact")
	panel.practice_radar.contact_clicked.emit("T1")
	assert_true(not panel.practice_done["practice_select"], "the wrong contact does not count")
	panel.practice_radar.contact_clicked.emit("T2")
	assert_true(panel.practice_done["practice_select"], "clicking T2 completes the practice")
	panel.next()
	assert_true(not panel.practice_confirm(), "confirming the wrong option is explained, not accepted")
	panel.practice_scroll(Vocabulary.CATEGORIES.find("unknown") - panel.practice_highlight)
	assert_true(panel.practice_confirm(), "scroll to Unknown + right-click completes the practice")
	panel.previous()
	assert_eq(panel.step_index, 3, "Back returns one step")
	while panel.step_index < panel.STEPS.size() - 1:
		panel.next()
	assert_eq(panel.next_button.text, "Start training", "last step starts training")
	for step in panel.STEPS:
		assert_true(String(step["text"]).length() < 420, "step '%s' is short" % step["title"])
	panel.next()
	await _wait_scene(AppState.SCENES["briefing"])
	SettingsStore.set_value("tutorial_done", false)


func test_tutorial_replays_from_the_pause_screen() -> void:
	var scene := await _observe("res://scenarios/01_single_rural_day.json", 2.0)
	scene.toggle_pause()
	assert_true(scene.hud.overlay.buttons.has("tutorial"), "pause menu offers the tutorial")
	scene.hud.overlay.press("tutorial")
	assert_true(scene._tutorial != null and scene._tutorial.embedded, "tutorial shown over the paused exercise")
	assert_true(tree.paused, "exercise stays paused")
	scene._tutorial.confirm_skip()
	assert_true(scene._tutorial == null, "closing the tutorial returns to the pause menu")
	assert_true(scene.hud.overlay.visible, "pause menu still open")
	SettingsStore.set_value("tutorial_done", false)


func test_wheel_changes_only_the_selected_contact_and_never_acts() -> void:
	var scene := await _observe("res://scenarios/02_swarm_urban_day.json", 60.0)
	var tracks: Array = scene.session.tracker.confirmed_tracks()
	assert_true(tracks.size() >= 2, "two contacts available")
	var fov: float = scene.observer.fov
	await _mouse(MOUSE_BUTTON_WHEEL_UP, true)
	assert_true(scene.observer.fov < fov, "with nothing selected, the wheel zooms")
	scene.select_track(tracks[0]["id"])
	var before := _actions(scene.session).size()
	var start: int = scene.hud.highlight["classify"]
	await _mouse(MOUSE_BUTTON_WHEEL_DOWN, true)
	await _mouse(MOUSE_BUTTON_WHEEL_DOWN, true)
	assert_eq(scene.hud.highlight["classify"], posmod(start + 2, Vocabulary.CATEGORIES.size()), "wheel moved the highlight twice")
	assert_eq(scene.hud.card_track, tracks[0]["id"], "card bound to the selected contact")
	fov = scene.observer.fov
	await _mouse(MOUSE_BUTTON_WHEEL_UP, true, Vector2(800, 450), true)
	assert_true(scene.observer.fov < fov, "Shift + wheel still zooms while a contact is selected")
	scene.select_track(tracks[1]["id"])
	assert_eq(scene.hud.highlight["classify"], Vocabulary.CATEGORIES.find("unknown"), "another contact starts from its own state")
	assert_eq(_actions(scene.session).size(), before, "scrolling never submits anything")
	assert_true(scene.session.trainee_state(tracks[0]["id"]).is_empty(), "first contact untouched")


func test_right_click_confirms_and_right_drag_only_looks() -> void:
	var scene := await _observe("res://scenarios/01_single_rural_day.json", 30.0)
	scene.cycle_track()
	var id: String = scene.selected_track
	scene.hud.highlight["classify"] = Vocabulary.CATEGORIES.find("unidentified_uav")
	await _mouse(MOUSE_BUTTON_RIGHT, true)
	await _motion(Vector2(880, 470), MOUSE_BUTTON_MASK_RIGHT)
	await _mouse(MOUSE_BUTTON_RIGHT, false, Vector2(880, 470))
	assert_true(scene.session.trainee_state(id).is_empty(), "a right-drag looks around and confirms nothing")
	await _mouse(MOUSE_BUTTON_RIGHT, true)
	await _mouse(MOUSE_BUTTON_RIGHT, false)
	var state: Dictionary = scene.session.trainee_state(id)
	assert_eq(state.get("category"), "unidentified_uav", "right-click confirmed the highlighted classification")
	assert_true(float(state.get("acknowledged_t", -1.0)) >= 0.0, "contact marked seen in the same step")
	var kinds: Array = _actions(scene.session).map(func(e): return e["data"]["kind"])
	assert_eq(kinds, ["acknowledge", "classify"], "logged as acknowledge then classify")
	assert_eq(scene.hud.card_step, "respond", "card moves on to the response")


func test_alarm_responses_need_one_explicit_confirmation() -> void:
	var scene := await _observe("res://scenarios/01_single_rural_day.json", 30.0)
	scene.cycle_track()
	var id: String = scene.selected_track
	scene.hud.confirm()
	scene.hud._busy_until_ms = 0
	scene.hud.highlight["respond"] = Vocabulary.RESPONSES.find("notify_supervisor")
	assert_eq(scene.hud.confirm(), "confirm_needed", "alarm asks for confirmation")
	assert_true(scene.hud.confirm_row.visible and "This is final" in scene.hud.confirm_text.text, "confirmation shown with consequences")
	assert_eq(String(scene.session.trainee_state(id)["response"]), "", "nothing submitted yet")
	scene.hud.back()
	assert_eq(scene.hud.card_step, "respond", "Cancel returns to the response list")
	scene.hud._busy_until_ms = 0
	scene.hud.confirm()
	scene.hud._busy_until_ms = 0
	assert_eq(scene.hud.confirm(), "respond", "second, explicit confirmation submits")
	assert_eq(scene.session.trainee_state(id)["response"], "notify_supervisor", "alarm response recorded")


func test_double_submission_is_blocked_without_penalty() -> void:
	var scene := await _observe("res://scenarios/01_single_rural_day.json", 30.0)
	scene.cycle_track()
	assert_eq(scene.hud.confirm(), "classify", "first confirm classifies")
	assert_eq(scene.hud.confirm(), "busy", "an immediate second confirm is ignored")
	scene.hud._busy_until_ms = 0
	scene.hud.highlight["respond"] = Vocabulary.RESPONSES.find("log_observation")
	assert_eq(scene.hud.confirm(), "respond", "routine response needs one confirmation")
	scene.hud._busy_until_ms = 0
	var spam: int = scene.session.spam_count
	var count := _actions(scene.session).size()
	assert_eq(scene.hud.confirm(), "final", "a final response cannot be submitted again")
	assert_eq(scene.session.spam_count, spam, "no repeated-action penalty from the UI guard")
	assert_eq(_actions(scene.session).size(), count, "nothing logged")


func test_keyboard_fallback_for_every_step() -> void:
	var scene := await _observe("res://scenarios/01_single_rural_day.json", 30.0)
	var tab := InputEventAction.new()
	tab.action = "cycle_track"
	tab.pressed = true
	Input.parse_input_event(tab)
	await tree.process_frame
	var id: String = scene.selected_track
	assert_true(not id.is_empty(), "Tab selects")
	for action in ["option_next", "confidence_high", "report"]:
		var press := InputEventAction.new()
		press.action = action
		press.pressed = true
		Input.parse_input_event(press)
		await tree.process_frame
	var state: Dictionary = scene.session.trainee_state(id)
	assert_eq(state.get("category"), Vocabulary.CATEGORIES[(Vocabulary.CATEGORIES.find("unknown") + 1) % Vocabulary.CATEGORIES.size()], "↓ then Enter classifies")
	assert_eq(state.get("confidence"), 90, "3 sets high confidence")
	var back := InputEventAction.new()
	back.action = "decision_back"
	back.pressed = true
	Input.parse_input_event(back)
	await tree.process_frame
	assert_eq(scene.hud.card_step, "classify", "Backspace returns to the classification")


func test_observation_radar_shows_tracker_output_only() -> void:
	var scene := await _observe("res://scenarios/02_swarm_urban_day.json", 70.0)
	scene._process(0.0)
	var radar = scene.hud.radar
	var confirmed: Array = scene.session.tracker.confirmed_tracks()
	var expected: int = confirmed.size() + scene.session.tracker.groups.size()
	assert_eq(radar.contacts.size(), expected, "one radar item per confirmed track and per swarm group")
	for c in radar.contacts:
		var id: String = c["id"]
		assert_true(scene.session.tracker.tracks.has(id) or id.trim_prefix("group:") in scene.session.tracker.groups, "radar item %s comes from the tracker" % id)
		assert_true(c["kind"] in ["track", "group"], "radar kinds are tracker kinds")
		assert_true(not "A0" in str(c) and not "unidentified" in str(c), "no ground truth on the radar")
	radar.contact_clicked.emit(confirmed[0]["id"])
	await tree.process_frame
	assert_eq(scene.selected_track, confirmed[0]["id"], "clicking a radar symbol selects the contact")


## Regression: when the selected contact joined a swarm group, its Contacts-list row was
## re-created and re-selected, which re-bound the card: a pending alarm confirmation
## fell back to the response list with "continue observing" highlighted, so the next
## right-click submitted a different response from the one being confirmed.
func test_card_keeps_a_pending_decision_when_the_contact_joins_a_group() -> void:
	var config: Dictionary = ScenarioConfig.load_file("res://scenarios/02_swarm_urban_day.json")["config"]
	# Same seed, same simulation: find a contact confirmed alone that joins a group later.
	var pre := ThreatSession.new(config, null)
	pre.start()
	var alone_since := {}
	var target := ""
	var select_t := 0.0
	while pre.status == ThreatSession.Status.RUNNING and target.is_empty():
		pre.step()
		for track in pre.tracker.confirmed_tracks():
			if String(track["swarm_group"]).is_empty():
				if not alone_since.has(track["id"]):
					alone_since[track["id"]] = pre.time_s()
			elif alone_since.has(track["id"]) and pre.time_s() - float(alone_since[track["id"]]) > 0.5:
				target = track["id"]
				select_t = float(alone_since[track["id"]]) + 0.2
				break
	assert_true(not target.is_empty(), "the scenario has a contact that joins a group after it is confirmed")
	var scene := await _observe("res://scenarios/02_swarm_urban_day.json", select_t)
	var session = scene.session
	assert_true(String(session.tracker.tracks[target]["swarm_group"]).is_empty(), "%s not grouped yet" % target)
	scene.select_track(target)
	scene.hud.highlight["classify"] = Vocabulary.CATEGORIES.find("unidentified_uav")
	scene.hud.confirm()
	scene.hud._busy_until_ms = 0
	scene.hud.highlight["respond"] = Vocabulary.RESPONSES.find("notify_supervisor")
	assert_eq(scene.hud.confirm(), "confirm_needed", "alarm waiting for confirmation")
	while session.status == ThreatSession.Status.RUNNING and String(session.tracker.tracks.get(target, {}).get("swarm_group", "")).is_empty():
		session.step()
	assert_true(not String(session.tracker.tracks.get(target, {}).get("swarm_group", "")).is_empty(), "%s joined a group" % target)
	scene.hud._refresh_left = 0.0
	scene.hud.refresh(session, scene.selected_track, scene.view_text(), 1.0)
	await tree.process_frame
	assert_eq([scene.hud.card_track, scene.hud.card_step, scene.hud.highlighted_response()], [target, "confirm", "notify_supervisor"],
		"card still bound to the same contact with the same pending alarm")
	scene.hud._busy_until_ms = 0
	assert_eq(scene.hud.confirm(), "respond", "confirming submits")
	assert_eq(session.trainee_state(target)["response"], "notify_supervisor", "the response that was being confirmed is recorded")


func test_swarm_group_decision_applies_to_the_group_and_is_scored_once() -> void:
	var scene := await _observe("res://scenarios/02_swarm_urban_day.json", 80.0)
	var groups: Dictionary = scene.session.tracker.groups
	assert_true(not groups.is_empty(), "a swarm group formed")
	var gid: String = groups.keys()[0]
	var members: Array = groups[gid]["members"]
	scene.select_track("group:" + gid)
	assert_true(scene.selected_track in members, "selecting the group row selects a member")
	scene.hud.highlight["classify"] = Vocabulary.CATEGORIES.find("swarm")
	scene.hud._render_card()
	assert_true("whole swarm group" in scene.hud.card_scope.text, "card says the decision applies to the group: " + scene.hud.card_scope.text)
	scene.hud.confirm()
	scene.hud._busy_until_ms = 0
	scene.hud.highlight["respond"] = Vocabulary.RESPONSES.find("request_identification")
	scene.hud.confirm()
	for m in members:
		var state: Dictionary = scene.session.trainee_state(m)
		assert_eq([state.get("category"), state.get("response")], ["swarm", "request_identification"], "member %s shares the group decision" % m)
	while not scene.session.is_finished():
		scene.session.step()
	var record := SessionRecord.build(scene.session, "group-test", "2026-10-20T00:00:00Z")
	var evaluation := Rubric.evaluate(record)
	var swarm_entities: Array = evaluation["entities"].filter(func(e): return e["expected_category"] == "swarm")
	assert_eq(swarm_entities.size(), 1, "the swarm is one assessed entity, not one per drone")
	assert_true(swarm_entities[0]["correct"], "group classification scored as correct once")
