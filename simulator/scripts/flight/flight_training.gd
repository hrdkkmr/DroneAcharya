extends Node3D
## Stage 1 root: wires the course, drone, camera, mission and HUD together and handles
## pause (Esc) and restart (R). Runs while the game is paused so those keys always work.

const TITLE := "DroneAcharya — synthetic training only"
const MissionState := preload("res://scripts/mission/mission_state.gd")

var spawn_transform := Transform3D.IDENTITY

var _finished_shown := false

@onready var _title: Label = $Title
@onready var drone: CharacterBody3D = get_node_or_null("Drone")
@onready var camera_rig: Node3D = get_node_or_null("CameraRig")
@onready var mission: Node = get_node_or_null("Mission")
@onready var hud: CanvasLayer = get_node_or_null("HUD")


func _ready() -> void:
	_title.text = TITLE
	if drone == null or mission == null or hud == null:
		push_warning("Main scene is missing Drone, Mission or HUD; simulator controls are disabled.")
		set_process(false)
		set_process_unhandled_input(false)
		return
	spawn_transform = drone.global_transform
	mission.message.connect(hud.show_message)
	hud.hide_overlay()
	hud.show_message("Hold Space to take off. Fly through the rings in order, then land.", 6.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_mission"):
		reset_mission()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func set_paused(paused: bool) -> void:
	if mission and mission.state.is_finished():
		paused = false
	get_tree().paused = paused
	if hud == null:
		return
	if paused:
		hud.show_overlay("Paused", "Esc: resume    R: restart mission")
	else:
		hud.hide_overlay()


## Puts the drone back on the launch pad and restarts the mission from checkpoint 1.
func reset_mission() -> void:
	if drone == null or mission == null:
		return
	get_tree().paused = false
	drone.reset_to(spawn_transform)
	mission.reset()
	if camera_rig and camera_rig.has_method("snap"):
		camera_rig.snap()
	_finished_shown = false
	if hud:
		hud.hide_overlay()
		hud.show_message("Mission restarted. Hold Space to take off.")


func _process(_delta: float) -> void:
	var state: MissionState = mission.state
	var view_name := "Onboard" if camera_rig and camera_rig.get("mode") == 1 else "Follow"
	hud.show_telemetry(drone.altitude(), drone.horizontal_speed(), drone.vertical_speed(),
			drone.heading_degrees(), state.elapsed_seconds, view_name)
	var status: String = mission.status_text()
	if get_tree().paused:
		status = "Paused"
	hud.show_mission(mission.objective_text(), status)
	if state.is_finished() and not _finished_shown:
		_finished_shown = true
		if state.status == MissionState.Status.COMPLETED:
			hud.show_overlay("Mission complete", "Time %s    R: fly again" % hud.format_time(state.elapsed_seconds))
		else:
			var reason := state.failure_reason.left(1).to_upper() + state.failure_reason.substr(1)
			hud.show_overlay("Mission failed", "%s\nR: restart" % reason)
