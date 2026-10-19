extends Node3D
## Threat-observation exercise scene. The ThreatSession (pure simulation) is
## stepped at its fixed tick rate; this script only renders it and handles input.

const TITLE := "DroneAcharya — synthetic training only"
const AppState := preload("res://scripts/app/app_state.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const EnvironmentBuilder := preload("res://scripts/observation/environment_builder.gd")
const ActorVisuals := preload("res://scripts/observation/actor_visuals.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const DEFAULT_SCENARIO := "res://scenarios/01_single_rural_day.json"

var session: ThreatSession
var config: Dictionary = {}

var _accumulator := 0.0
var _previous := {} ## actor id -> position at the previous tick (for smooth rendering)
var _visuals := {}
var _info: Label
var _overlay: PanelContainer
var _overlay_title: Label
var _overlay_detail: Label
var _end_shown := false

@onready var world_root: Node3D = $World
@onready var actors_root: Node3D = $Actors
@onready var observer: Node3D = $Observer


func _ready() -> void:
	$Title.text = TITLE
	config = AppState.selected_config
	if config.is_empty():
		var result := ScenarioConfig.load_file(DEFAULT_SCENARIO)
		config = result["config"]
	_build_hud()
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
	_accumulator = 0.0
	_end_shown = false
	_overlay.visible = false
	get_tree().paused = false
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


func _process(_delta: float) -> void:
	if session == null:
		return
	var c := config
	_info.text = "%s\nTime remaining %s · %s · %s · visibility %s" % [
		c["title"], _clock(session.remaining_s()), c["environment"], c["time_of_day"], c["visibility"]]
	if session.is_finished() and not _end_shown:
		_end_shown = true
		_show_overlay("Exercise ended", "The scenario duration has been reached.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_mission"):
		start_session()
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	if session.is_finished():
		return
	if get_tree().paused:
		session.resume()
		get_tree().paused = false
		_overlay.visible = false
	else:
		session.pause()
		get_tree().paused = true
		_show_overlay("Paused", "Esc: resume · R: restart")


func exit_to_menu() -> void:
	if session and not session.is_finished():
		session.abort()
	AppState.goto(get_tree(), "menu")


func _show_overlay(title: String, detail: String) -> void:
	_overlay_title.text = title
	_overlay_detail.text = detail
	_overlay.visible = true


func _build_hud() -> void:
	var hud: CanvasLayer = $HUD
	var info_panel := UiKit.panel()
	info_panel.position = Vector2(16, 48)
	_info = UiKit.label("", 17)
	info_panel.add_child(_info)
	hud.add_child(info_panel)
	var help := UiKit.label("Right-drag or W/A/S/D: look · Wheel: zoom · Esc: pause · R: restart", 15, UiKit.MUTED)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	hud.add_child(help)
	_overlay = UiKit.panel(0.9)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_overlay.custom_minimum_size = Vector2(520, 0)
	_overlay.position -= Vector2(260, 80)
	var rows := UiKit.vbox(10)
	_overlay_title = UiKit.label("", 32)
	_overlay_detail = UiKit.label("", 17, UiKit.MUTED, true)
	rows.add_child(_overlay_title)
	rows.add_child(_overlay_detail)
	var buttons := UiKit.hbox(10)
	buttons.add_child(UiKit.button("Resume", toggle_pause, 140))
	buttons.add_child(UiKit.button("Restart", start_session, 140))
	buttons.add_child(UiKit.button("Exit to menu", exit_to_menu, 160))
	rows.add_child(buttons)
	_overlay.add_child(rows)
	_overlay.visible = false
	hud.add_child(_overlay)


static func _clock(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
