extends Node3D
## Threat-observation exercise scene. The ThreatSession (pure simulation) is
## stepped at its fixed tick rate; this script renders it and routes input.
## Trainee-facing UI (HUD, markers) reads tracker output only, never ground truth.

const TITLE := "DroneAcharya — synthetic training only"
const AppState := preload("res://scripts/app/app_state.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const EnvironmentBuilder := preload("res://scripts/observation/environment_builder.gd")
const ActorVisuals := preload("res://scripts/observation/actor_visuals.gd")
const ObservationHud := preload("res://scripts/observation/observation_hud.gd")
const TrackOverlay := preload("res://scripts/observation/track_overlay.gd")
const DEFAULT_SCENARIO := "res://scenarios/01_single_rural_day.json"

var session: ThreatSession
var config: Dictionary = {}
var selected_track := ""
var sensor_view := false
var hud: ObservationHud
var overlay: TrackOverlay

var _accumulator := 0.0
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
	hud.restart_requested.connect(start_session)
	hud.exit_requested.connect(exit_to_menu)
	start_session()


## (Re)starts the exercise from the same config and seed.
func start_session() -> void:
	session = ThreatSession.new(config)
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
	session.start()


func _physics_process(delta: float) -> void:
	if session == null or get_tree().paused:
		return
	_accumulator += delta
	var dt := session.tick_seconds()
	while _accumulator >= dt and session.status == ThreatSession.Status.RUNNING:
		for record in session.world.actors:
			_previous[record["id"]] = record["state"].position
		session.step()
		_accumulator -= dt
	_render(clampf(_accumulator / dt, 0.0, 1.0), delta)


func _render(alpha: float, delta: float) -> void:
	for record in session.world.actors:
		var visual: Node3D = _visuals[record["id"]]
		if not record["active"]:
			visual.visible = false
			continue
		var current: Vector3 = record["state"].position
		var previous: Vector3 = _previous.get(record["id"], current)
		visual.show_state(previous.lerp(current, alpha), record["state"].yaw, delta)


func _process(delta: float) -> void:
	if session == null:
		return
	hud.refresh(session, selected_track, view_text(), delta)
	if session.is_finished() and not _end_shown:
		_end_shown = true
		hud.show_overlay("Exercise ended", "The scenario duration has been reached.")


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
		start_session()
	elif event.is_action_pressed("toggle_view"):
		set_sensor_view(not sensor_view)
	elif event.is_action_pressed("cycle_track"):
		cycle_track()
	else:
		return
	get_viewport().set_input_as_handled()


func toggle_pause() -> void:
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
	if session and not session.is_finished():
		session.abort()
	AppState.goto(get_tree(), "menu")
