extends Node3D
## Threat-observation exercise scene. The ThreatSession (pure simulation) is
## stepped at its fixed tick rate; this script renders it and routes input.
## Trainee-facing UI (HUD, markers) reads tracker output only, never ground truth.
## Replay mode re-simulates a recorded session (scripts/training/replay.gd) with
## trainee input disabled; ground-truth labels may be shown there because the
## exercise is over.

const TITLE := "DroneAcharya — synthetic training only"
const AppState := preload("res://scripts/app/app_state.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const EnvironmentBuilder := preload("res://scripts/observation/environment_builder.gd")
const ActorVisuals := preload("res://scripts/observation/actor_visuals.gd")
const ObservationHud := preload("res://scripts/observation/observation_hud.gd")
const TrackOverlay := preload("res://scripts/observation/track_overlay.gd")
const SessionRecord := preload("res://scripts/training/session_record.gd")
const SessionIO := preload("res://scripts/training/session_io.gd")
const Replay := preload("res://scripts/training/replay.gd")
const Rubric := preload("res://scripts/training/rubric.gd")
const ReportBuilder := preload("res://scripts/training/report_builder.gd")
const MlClassifier := preload("res://scripts/ai/ml_classifier.gd")
const Vocabulary := preload("res://scripts/ai/vocabulary.gd")
const TutorialPanel := preload("res://scripts/menu/tutorial_panel.gd")
const SettingsStore := preload("res://scripts/app/settings_store.gd")
const AudioCues := preload("res://scripts/audio/audio_cues.gd")
## Session events with a sound cue during a live exercise (each also appears on screen).
const EVENT_CUES := {"track_confirmed": "contact_detected", "track_reacquired": "contact_detected", "track_lost": "contact_lost",
	"sensor_degraded": "sensor_alert"}
const CLICK_MAX_DRAG_PX := 6.0 ## a right-button press that moves less than this is a click (confirm), not a look-drag
const DEFAULT_SCENARIO := "res://scenarios/01_single_rural_day.json"

var session: ThreatSession
var config: Dictionary = {}
var selected_track := ""
var sensor_view := false
var hud: ObservationHud
var overlay: TrackOverlay
var record: Dictionary = {} ## built when a live exercise ends
var evaluation: Dictionary = {}
var saved_path := ""
## Replay mode (null during a live exercise).
var replay: Replay = null
var replay_record: Dictionary = {}
var replay_playing := true
var replay_speed := 1.0
var show_truth := false

var _accumulator := 0.0
var _replay_position := 0.0 ## fractional replay tick
var _previous := {} ## actor id -> position at the previous tick (smooth rendering only)
var _visuals := {}
var _end_shown := false
var _right_press := Vector2.ZERO
var _right_drag := 0.0
var _tutorial: TutorialPanel
var cues: Node
var _event_cursor := 0

@onready var world_root: Node3D = $World
@onready var actors_root: Node3D = $Actors
@onready var observer: Node3D = $Observer


func _ready() -> void:
	$Title.text = TITLE
	config = AppState.selected_config
	if config.is_empty():
		config = ScenarioConfig.load_file(DEFAULT_SCENARIO)["config"]
	cues = AudioCues.attach(self)
	overlay = TrackOverlay.new()
	overlay.camera = observer.eye_camera
	overlay.track_clicked.connect(select_track)
	$HUD.add_child(overlay)
	hud = ObservationHud.new()
	$HUD.add_child(hud)
	hud.track_selected.connect(select_track)
	hud.centre_requested.connect(centre_on_selected)
	hud.resume_requested.connect(toggle_pause)
	hud.restart_requested.connect(restart)
	hud.exit_requested.connect(exit_to_menu)
	hud.tutorial_requested.connect(open_tutorial)
	hud.deselect_requested.connect(select_track.bind(""))
	hud.review_requested.connect(open_review)
	hud.acknowledge_requested.connect(acknowledge_selected)
	hud.classify_requested.connect(classify_selected)
	hud.respond_requested.connect(respond_selected)
	hud.decision_support_toggled.connect(_on_decision_support_toggled)
	hud.replay_play_toggled.connect(func(): replay_playing = not replay_playing)
	hud.replay_speed_changed.connect(func(speed): replay_speed = speed)
	hud.replay_seek_requested.connect(seek_replay)
	hud.truth_labels_toggled.connect(set_truth_labels)
	if AppState.replay_requested and not AppState.review_session.is_empty():
		AppState.replay_requested = false
		start_replay(AppState.review_session)
	else:
		start_session()


## (Re)starts a live exercise from the same config and seed.
func start_session() -> void:
	replay = null
	session = ThreatSession.new(config, MlClassifier.shared() if AppState.use_ml else null)
	_build_world()
	record = {}
	evaluation = {}
	saved_path = ""
	hud.set_replay_mode(false, 0)
	session.start()
	_event_cursor = 0
	cues.start_loop("wind", -20.0, 1.0)


## Re-simulates a recorded session with the recorded trainee actions.
func start_replay(recorded: Dictionary) -> void:
	replay_record = recorded
	config = recorded["scenario"]
	replay = Replay.new(recorded, MlClassifier.shared())
	session = replay.session
	_build_world()
	_replay_position = 0.0
	replay_playing = true
	hud.set_replay_mode(true, replay.end_tick())
	if not replay.warnings.is_empty():
		hud.show_feedback(" ".join(replay.warnings), false)
	set_truth_labels(show_truth)


func _build_world() -> void:
	for child in world_root.get_children():
		child.free()
	for child in actors_root.get_children():
		child.free()
	_visuals.clear()
	_previous.clear()
	EnvironmentBuilder.build(session.definition, world_root)
	for actor_def in session.definition["actors"]:
		var visual := ActorVisuals.create(actor_def)
		actors_root.add_child(visual)
		_visuals[actor_def["id"]] = visual
	observer.position = session.definition["observer_position"]
	overlay.session = session
	selected_track = ""
	overlay.selected_id = ""
	observer.wheel_reserved = false
	hud.bind_card(session, "")
	_accumulator = 0.0
	_end_shown = false
	hud.hide_overlay()
	hud.set_review_available(false)
	get_tree().paused = false
	set_sensor_view(false)


func restart() -> void:
	if replay != null:
		seek_replay(0)
	else:
		start_session()


func _physics_process(delta: float) -> void:
	if session == null or get_tree().paused:
		return
	var dt := session.tick_seconds()
	if replay != null:
		if replay_playing and not replay.is_done():
			_remember_positions()
			_replay_position = minf(_replay_position + delta / dt * replay_speed, float(replay.end_tick()))
			replay.step_to(int(_replay_position))
		hud.update_replay(session.tick(), replay_playing)
		_render(clampf(_replay_position - floorf(_replay_position), 0.0, 1.0), delta)
		_update_truth_labels()
		return
	_accumulator += delta
	while _accumulator >= dt and session.status == ThreatSession.Status.RUNNING:
		_remember_positions()
		session.step()
		_accumulator -= dt
	_render(clampf(_accumulator / dt, 0.0, 1.0), delta)


func _remember_positions() -> void:
	for actor in session.world.actors:
		_previous[actor["id"]] = actor["state"].position


func _render(alpha: float, delta: float) -> void:
	for actor in session.world.actors:
		var visual: Node3D = _visuals[actor["id"]]
		if not actor["active"]:
			visual.visible = false
			continue
		var current: Vector3 = actor["state"].position
		var previous: Vector3 = _previous.get(actor["id"], current)
		visual.show_state(previous.lerp(current, alpha), actor["state"].yaw, delta)


## Jumps the replay to `tick` (re-simulating from the start when going backwards).
func seek_replay(tick: int) -> void:
	if replay == null:
		return
	if tick < session.tick():
		replay = Replay.new(replay_record, MlClassifier.shared())
		session = replay.session
		overlay.session = session
	replay.step_to(tick)
	_replay_position = float(session.tick())
	_previous.clear()
	_end_shown = false
	hud.hide_overlay()
	_update_truth_labels()
	hud.refresh(session, selected_track, view_text(), 1.0)


func set_truth_labels(enabled: bool) -> void:
	show_truth = enabled and replay != null
	_update_truth_labels()


## Review only: ground-truth identity of every active actor, drawn by the overlay.
func _update_truth_labels() -> void:
	overlay.truth_labels = []
	if not show_truth:
		return
	for actor in session.world.actors:
		if actor["active"]:
			var category: String = Vocabulary.TRUTH_CATEGORY_FOR_PROFILE[actor["def"]["profile"]]
			overlay.truth_labels.append({"position": actor["state"].position, "text": "%s · %s" % [actor["id"], Vocabulary.CATEGORY_LABELS[category]]})


func _process(delta: float) -> void:
	if session == null:
		return
	if replay == null:
		while _event_cursor < session.events.size():
			var cue: String = EVENT_CUES.get(session.events[_event_cursor]["type"], "")
			if not cue.is_empty():
				cues.play(cue)
			_event_cursor += 1
	hud.refresh(session, selected_track, view_text(), delta)
	hud.update_radar(session, observer.global_position, observer.yaw_degrees, observer.fov, selected_track)
	if replay != null:
		if replay.is_done() and not _end_shown:
			_end_shown = true
			hud.show_overlay("Replay finished", "The recorded exercise has been re-simulated to its end.")
			hud.set_review_available(true)
		return
	if session.is_finished() and not _end_shown:
		_end_shown = true
		finish_and_score()


## Builds the session record, scores it with da-rubric-1 and saves it to history.
func finish_and_score() -> void:
	var created := Time.get_datetime_string_from_system(true) + "Z"
	record = SessionRecord.build(session, "da-%d-%d" % [int(config["seed"]), int(Time.get_unix_time_from_system())], created)
	evaluation = Rubric.evaluate(record)
	record["evaluation"] = evaluation
	var saved := SessionIO.save(record, AppState.sessions_dir)
	saved_path = saved.get("path", "")
	# Short, data-backed summary; the full report is one click away.
	var report := ReportBuilder.build(record)
	var lines := PackedStringArray(["Score %.1f / 100%s" % [evaluation["score"], "" if evaluation["comparable"] else " (not comparable)"]])
	for row in report["result"]:
		if row[0] == "Contacts":
			lines.append(row[1])
	if not report["went_well"].is_empty():
		lines.append("✓ " + report["went_well"][0])
	if not report["improve"].is_empty():
		lines.append("✗ " + report["improve"][0])
	lines.append("Saved to training history." if saved["ok"] else "Not saved: " + saved["error"])
	hud.show_overlay("Exercise ended" if session.status == ThreatSession.Status.COMPLETED else "Exercise aborted", "\n".join(lines))
	cues.play("success" if session.status == ThreatSession.Status.COMPLETED else "failure")
	hud.set_review_available(saved["ok"])


func open_review() -> void:
	AppState.review_session = record if replay == null else replay_record
	AppState.replay_requested = false
	AppState.goto(get_tree(), "history")


func acknowledge_selected() -> void:
	if replay == null:
		_feedback(session.acknowledge(selected_track))


## Classification from the decision card. An unacknowledged contact is marked seen
## in the same step (one confirmation instead of two).
func classify_selected(category: String, confidence: int) -> void:
	if replay == null:
		var result := session.classify(selected_track, category, confidence, true)
		_feedback(result)
		hud.on_result("classify", result["ok"])


func respond_selected(response: String) -> void:
	if replay == null:
		var result := session.respond(selected_track, response)
		_feedback(result)
		hud.on_result("respond", result["ok"])


func _on_decision_support_toggled(on: bool) -> void:
	if replay == null:
		session.log_event("decision_support_visible", {"visible": on})


func _feedback(result: Dictionary) -> void:
	hud.show_feedback(result["message"], result["ok"])
	cues.play("decision_confirmed" if result["ok"] else "decision_rejected")
	hud.refresh(session, selected_track, view_text(), 1.0)


func view_text() -> String:
	if not sensor_view:
		return "eye, %.0f° field of view" % observer.fov
	var mode := "thermal (simulated)" if config["time_of_day"] == "night" else "TV (simulated)"
	return "sensor camera %s, %.1f° field of view" % [mode, observer.fov]


func set_sensor_view(enabled: bool) -> void:
	sensor_view = enabled
	observer.set_sensor_mode(enabled)
	var thermal: bool = enabled and config["time_of_day"] == "night"
	hud.set_sensor_view(enabled, thermal)
	overlay.high_contrast = enabled
	for id in _visuals:
		_visuals[id].set_thermal(thermal)


## Selects a contact (or a swarm group's first member) and binds the decision card to it.
func select_track(track_id: String) -> void:
	if track_id.begins_with("group:"):
		var group: Dictionary = session.tracker.groups.get(track_id.trim_prefix("group:"), {})
		track_id = group["members"][0] if not group.is_empty() else ""
	selected_track = track_id
	overlay.selected_id = track_id
	observer.wheel_reserved = not track_id.is_empty() and replay == null
	hud.select_row(track_id)
	hud.bind_card(session, track_id)
	hud.refresh(session, selected_track, view_text(), 1.0)


## Selects the next confirmed track in id order (Tab).
func cycle_track() -> void:
	var ids := []
	for track in session.tracker.confirmed_tracks():
		ids.append(track["id"])
	if ids.is_empty():
		return
	var index := ids.find(selected_track)
	select_track(ids[(index + 1) % ids.size()])


func centre_on_selected() -> void:
	var track: Dictionary = session.tracker.tracks.get(selected_track, {})
	if not track.is_empty():
		observer.look_at_point(session.tracker.estimated_position(track, session.time_s()))


func _unhandled_input(event: InputEvent) -> void:
	if _decision_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		toggle_pause()
	elif event.is_action_pressed("reset_mission"):
		restart()
	elif event.is_action_pressed("toggle_view"):
		set_sensor_view(not sensor_view)
	elif event.is_action_pressed("cycle_track"):
		cycle_track()
	elif event is InputEventKey and event.is_action_pressed("mark"):
		acknowledge_selected()
	elif event.is_action_pressed("classify") or event.is_action_pressed("report"):
		hud.confirm()
	else:
		return
	get_viewport().set_input_as_handled()


## Mouse-first decision input. Returns true when the event was used.
##  * wheel (no Shift) with a contact selected: change the highlighted option;
##  * right-button click without dragging: confirm the highlighted option
##    (a right-button drag still looks around; observer_rig handles that);
##  * ↑/↓, Backspace, 1/2/3: keyboard equivalents.
func _decision_input(event: InputEvent) -> bool:
	if replay != null or session == null or get_tree().paused:
		return false
	if event is InputEventMouseButton:
		if event.pressed and not event.shift_pressed and not selected_track.is_empty() 				and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			return hud.cycle_option(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_right_press = event.position
				_right_drag = 0.0
				return false
			if _right_drag < CLICK_MAX_DRAG_PX:
				hud.confirm()
				return true
		return false
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_right_drag = maxf(_right_drag, event.position.distance_to(_right_press))
		return false
	if event.is_action_pressed("option_prev"):
		return hud.cycle_option(-1)
	if event.is_action_pressed("option_next"):
		return hud.cycle_option(1)
	if event.is_action_pressed("decision_back"):
		hud.back()
		return true
	for level in [["confidence_low", 30], ["confidence_medium", 60], ["confidence_high", 90]]:
		if event.is_action_pressed(level[0]):
			hud.set_confidence(level[1])
			return true
	return false


## Shows the tutorial over the paused exercise; closing it returns to the pause menu.
func open_tutorial() -> void:
	if _tutorial != null:
		return
	_tutorial = TutorialPanel.new()
	_tutorial.embedded = true
	$HUD.add_child(_tutorial)
	_tutorial.finished.connect(_close_tutorial)


func _close_tutorial(_skipped := false) -> void:
	if _tutorial == null:
		return
	SettingsStore.set_value("tutorial_done", true)
	SettingsStore.save()
	_tutorial.queue_free()
	_tutorial = null


func toggle_pause() -> void:
	if _tutorial != null:
		_close_tutorial()
		return
	if replay != null:
		replay_playing = not replay_playing
		return
	if session.is_finished():
		return
	if get_tree().paused:
		session.resume()
		get_tree().paused = false
		cues.set_paused_mix(false)
		hud.hide_overlay()
	else:
		session.pause()
		get_tree().paused = true
		cues.set_paused_mix(true)
		hud.show_pause()


func exit_to_menu() -> void:
	if replay != null:
		open_review()
		return
	if session and not session.is_finished():
		session.abort()
	AppState.goto(get_tree(), "menu")
