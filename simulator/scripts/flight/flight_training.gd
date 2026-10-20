extends Node3D
## Flight-training root: applies the chosen drone profile and mission, wires the
## course, drone, camera, mission and HUD together, handles the pause menu (Esc) and
## restart (R), and saves a flight record when a mission ends. Runs while the game is
## paused so those keys always work; everything that simulates is PAUSABLE.

const TITLE := "DroneAcharya — synthetic training only"
const MissionState := preload("res://scripts/mission/mission_state.gd")
const AppState := preload("res://scripts/app/app_state.gd")
const ControlsReference := preload("res://scripts/ui/controls_reference.gd")
const SettingsStore := preload("res://scripts/app/settings_store.gd")
const DroneProfiles := preload("res://scripts/flight/drone_profiles.gd")
const FlightMissions := preload("res://scripts/flight/flight_missions.gd")
const FlightRecord := preload("res://scripts/flight/flight_record.gd")
const PAUSE_ACTIONS := [["resume", "Resume"], ["restart", "Restart mission"], ["controls", "Controls"], ["settings", "Settings"], ["menu", "Back to menu"]]
const RESULT_ACTIONS := [["restart", "Fly again"], ["report", "Open report"], ["menu", "Back to menu"]]

var spawn_transform := Transform3D.IDENTITY
var mission_def: Dictionary = {}
var profile_id := DroneProfiles.DEFAULT
var record: Dictionary = {} ## the saved record of the last finished mission
var saved_path := ""

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
	mission_def = FlightMissions.get_mission(AppState.flight_mission)
	profile_id = DroneProfiles.resolve_id(AppState.flight_profile)
	_apply_quality()
	spawn_transform = drone.global_transform
	apply_profile()
	mission.configure_limits(float(mission_def["time_limit_s"]), float(DroneProfiles.get_profile(profile_id)["endurance_s"]))
	mission.message.connect(hud.show_message)
	hud.overlay.action_pressed.connect(_on_menu_action)
	hud.set_mission_title("%s · %s" % [mission_def["title"], DroneProfiles.get_profile(profile_id)["title"]])
	hud.hide_overlay()
	hud.show_message("Hold Space to take off. Fly through the rings in order, then land.", 6.0)


func _apply_quality() -> void:
	var sun := find_child("Sun", true, false) as DirectionalLight3D
	if sun and SettingsStore.effects_reduced():
		sun.shadow_enabled = false


## Applies the selected drone profile to the controller and the chase camera.
func apply_profile() -> void:
	var profile := DroneProfiles.get_profile(profile_id)
	drone.apply_profile(profile_id, profile)
	if camera_rig:
		for key in DroneProfiles.CAMERA_KEYS:
			camera_rig.set(key, float(profile[key]))


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
		hud.show_overlay("Paused", "The mission clock is stopped while paused.", PAUSE_ACTIONS, ControlsReference.FLIGHT)
	elif not (mission and mission.state.is_finished()):
		hud.hide_overlay()


func _on_menu_action(id: String) -> void:
	match id:
		"resume":
			set_paused(false)
		"restart":
			reset_mission()
		"menu":
			back_to_menu()
		"report":
			open_report()


## Leaves flight training. The scene (drone, mission, sounds) is freed by the change.
func back_to_menu() -> void:
	get_tree().paused = false
	AppState.goto(get_tree(), "menu")


## Opens the history screen with this mission's report selected.
func open_report() -> void:
	AppState.review_session = record
	AppState.replay_requested = false
	AppState.goto(get_tree(), "history")


## Puts the drone back on the launch pad with the selected profile and restarts the
## mission from checkpoint 1 (clock, battery and integrity reset).
func reset_mission() -> void:
	if drone == null or mission == null:
		return
	get_tree().paused = false
	drone.reset_to(spawn_transform)
	apply_profile()
	mission.reset()
	if camera_rig and camera_rig.has_method("snap"):
		camera_rig.snap()
	_finished_shown = false
	record = {}
	saved_path = ""
	if hud:
		hud.hide_overlay()
		hud.show_message("Mission restarted. Hold Space to take off.")


func _process(_delta: float) -> void:
	var state: MissionState = mission.state
	var view_name := "Onboard" if camera_rig and camera_rig.get("mode") == 1 else "Follow"
	hud.show_telemetry(drone.altitude(), drone.horizontal_speed(), drone.vertical_speed(),
			drone.heading_degrees(), state.elapsed_seconds, view_name)
	hud.show_limits(state.time_limit_s, state.time_remaining(), state.time_warning_active(),
			state.battery_fraction(), state.battery_warning_active(), state.integrity)
	var status: String = mission.status_text()
	if get_tree().paused:
		status = "Paused"
	hud.show_mission(mission.objective_text(), status)
	if state.is_finished() and not _finished_shown:
		_finished_shown = true
		_finish()


## Saves the record and shows the result screen.
func _finish() -> void:
	var state: MissionState = mission.state
	var created := Time.get_datetime_string_from_system(true) + "Z"
	var session_id := "flight-%s-%d-%d" % [mission_def["id"], Time.get_unix_time_from_system(), Time.get_ticks_msec() % 1000]
	record = FlightRecord.build(state, mission_def, profile_id, DroneProfiles.get_profile(profile_id), session_id, created)
	var saved := FlightRecord.save(record, AppState.flight_sessions_dir)
	saved_path = saved.get("path", "")
	var lines := PackedStringArray()
	if state.status == MissionState.Status.COMPLETED:
		lines.append("Landed in the zone after %s." % hud.format_time(state.elapsed_seconds))
	else:
		lines.append(state.failure_reason.left(1).to_upper() + state.failure_reason.substr(1) + ".")
	lines.append("Checkpoints %d of %d · minor collisions %d · simulated hits %d" % [
		state.next_checkpoint, state.checkpoint_count, state.bump_count, state.hit_count])
	lines.append("Saved to training history." if saved["ok"] else "Not saved: " + saved["error"])
	var title := "Mission complete" if state.status == MissionState.Status.COMPLETED else "Mission failed"
	hud.show_overlay(title, "\n".join(lines), RESULT_ACTIONS if saved["ok"] else [RESULT_ACTIONS[0], RESULT_ACTIONS[2]], ControlsReference.FLIGHT)
