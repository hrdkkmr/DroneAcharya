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
const MlClassifier := preload("res://scripts/ai/ml_classifier.gd")
const Vocabulary := preload("res://scripts/ai/vocabulary.gd")
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

@onready var world_root: Node3D = $World
@onready var actors_root: Node3D = $Actors
@onready var observer: Node3D = $Observer


func _ready() -> void:
	$Title.text = TITLE
	config = AppState.selected_config
	if config.is_empty():
		config = ScenarioConfig.load_file(DEFAULT_SCENARIO)["config"]
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
	_accumulator = 0.0
	_end_shown = false
	hud.overlay.visible = false
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
	hud.overlay.visible = false
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
	hud.refresh(session, selected_track, view_text(), delta)
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
	var c: Dictionary = evaluation["components"]
	var degraded_text: String = "%.0f" % c["degraded"]["score"] if c["degraded"]["n"] > 0 else "n/a"
	var detail := "Score %.1f / 100 (%.1f weighted − %.1f penalties)%s\nDetection %.0f · Classification %.0f · Evidence %.0f · Response %.0f · Timing %.0f · Degraded %s\n%s" % [
		evaluation["score"], evaluation["weighted_score"], evaluation["penalty_points"],
		"" if evaluation["comparable"] else " · not comparable",
		c["detection"]["score"], c["classification"]["score"], c["evidence"]["score"], c["response"]["score"], c["response_time"]["score"],
		degraded_text, "Saved to training history." if saved["ok"] else "Not saved: " + saved["error"]]
	hud.show_overlay("Exercise ended" if session.status == ThreatSession.Status.COMPLETED else "Exercise aborted", detail)
	hud.set_review_available(saved["ok"])


func open_review() -> void:
	AppState.review_session = record if replay == null else replay_record
	AppState.replay_requested = false
	AppState.goto(get_tree(), "history")


func acknowledge_selected() -> void:
	if replay == null:
		_feedback(session.acknowledge(selected_track))


func classify_selected(category: String, confidence: int) -> void:
	if replay == null:
		_feedback(session.classify(selected_track, category, confidence))


func respond_selected(response: String) -> void:
	if replay == null:
		_feedback(session.respond(selected_track, response))


func _on_decision_support_toggled(on: bool) -> void:
	if replay == null:
		session.log_event("decision_support_visible", {"visible": on})


func _feedback(result: Dictionary) -> void:
	hud.show_feedback(result["message"], result["ok"])
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
	for id in _visuals:
		_visuals[id].set_thermal(thermal)


func select_track(track_id: String) -> void:
	selected_track = track_id
	overlay.selected_id = track_id
	hud.select_row(track_id)
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
	else:
		return
	get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	if replay != null:
		replay_playing = not replay_playing
		return
	if session.is_finished():
		return
	if get_tree().paused:
		session.resume()
		get_tree().paused = false
		hud.overlay.visible = false
	else:
		session.pause()
		get_tree().paused = true
		hud.show_overlay("Paused", "Esc: resume · R: restart")


func exit_to_menu() -> void:
	if replay != null:
		open_review()
		return
	if session and not session.is_finished():
		session.abort()
	AppState.goto(get_tree(), "menu")
