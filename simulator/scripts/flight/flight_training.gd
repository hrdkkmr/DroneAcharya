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
const FlightWorld := preload("res://scripts/world/flight_world.gd")
const FlightTraffic := preload("res://scripts/flight/flight_traffic.gd")
const FlightSensor := preload("res://scripts/flight/flight_sensor.gd")
const TrafficVisuals := preload("res://scripts/flight/traffic_visuals.gd")
const PAUSE_ACTIONS := [["resume", "Resume"], ["restart", "Restart mission"], ["controls", "Controls"], ["settings", "Settings"], ["menu", "Back to menu"]]
const RESULT_ACTIONS := [["restart", "Fly again"], ["report", "Open report"], ["menu", "Back to menu"]]

var spawn_transform := Transform3D.IDENTITY
var mission_def: Dictionary = {}
var profile_id := DroneProfiles.DEFAULT
var record: Dictionary = {} ## the saved record of the last finished mission
var saved_path := ""
## Other traffic and synthetic hazards (null when the mission has none).
var traffic: FlightTraffic = null
var sensor: FlightSensor = null
var traffic_visuals: Node3D = null
var threat_stats := {}
var incoming_warning: Dictionary = {}

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
	if FlightWorld.supports(mission_def["environment"]):
		_build_environment()
	_apply_quality()
	spawn_transform = drone.global_transform
	apply_profile()
	mission.configure_limits(float(mission_def["time_limit_s"]), float(DroneProfiles.get_profile(profile_id)["endurance_s"]))
	mission.message.connect(hud.show_message)
	_setup_traffic()
	hud.overlay.action_pressed.connect(_on_menu_action)
	hud.set_mission_title("%s · %s" % [mission_def["title"], DroneProfiles.get_profile(profile_id)["title"]])
	hud.hide_overlay()
	hud.show_message("Hold Space to take off. Fly through the rings in order, then land.", 6.0)


## Replaces the hand-built course with the mission's procedural environment and
## points the mission at the new rings and landing zone.
func _build_environment() -> void:
	var course := get_node_or_null("Course")
	if course:
		remove_child(course)
		course.free()
	var world := Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	move_child(world, 0)
	var built := FlightWorld.build(world, mission_def, SettingsStore.effects_reduced())
	drone.global_transform = built["spawn"]
	drone.reset_physics_interpolation()
	mission.checkpoints_path = mission.get_path_to(world.get_node("Checkpoints"))
	mission.landing_zone_path = mission.get_path_to(world.get_node("LandingZone"))
	mission.training_area = built["area"]
	mission.setup()
	if camera_rig and camera_rig.has_method("snap"):
		camera_rig.snap()


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


## (Re)creates the traffic simulation and sensor from the mission seed, so a restart
## replays the same traffic for the same flying.
func _setup_traffic() -> void:
	if not (mission_def.get("traffic", false) or mission_def.get("hostile", false)):
		return
	var seed := int(mission_def.get("seed", 1))
	traffic = FlightTraffic.new(mission_def, mission.training_area, seed + 17)
	traffic.blocker = _blocked
	sensor = FlightSensor.new(seed + 29)
	threat_stats = {"projectiles_launched": 0, "incoming_warnings": 0, "projectile_hits": 0, "hostile_drone_hits": 0}
	incoming_warning = {}
	if traffic_visuals:
		traffic_visuals.free()
	traffic_visuals = TrafficVisuals.new()
	traffic_visuals.name = "Traffic"
	traffic_visuals.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(traffic_visuals)
	traffic_visuals.add_sites(traffic.sites)
	if hud.radar == null:
		hud.add_radar(float(sensor.config["range_m"]))
	hud.radar.contacts = []
	if hud.has_method("show_incoming"):
		hud.show_incoming({}, Vector2.ZERO, "")


## Line-of-sight test for the hazard layer: true when a structure is in the way.
func _blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [drone.get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _physics_process(delta: float) -> void:
	if traffic == null or get_tree().paused or mission.state.is_finished():
		return
	var own := drone.global_position + Vector3.UP * 0.2
	traffic.step(delta, own)
	for event in traffic.take_events():
		match event["type"]:
			"launched":
				threat_stats["projectiles_launched"] += 1
			"hit":
				var by_drone: bool = event["data"]["kind"] == "hostile_drone"
				threat_stats["hostile_drone_hits" if by_drone else "projectile_hits"] += 1
				mission.register_hit("the hostile drone" if by_drone else "a simulated projectile", float(traffic.config["damage"]))
				hud.flash_hit()
	sensor.step(delta, own, traffic.active_entities())
	var warnings := sensor.incoming(own, drone.velocity)
	var warning: Dictionary = warnings[0] if not warnings.is_empty() else {}
	if not warning.is_empty() and incoming_warning.is_empty():
		threat_stats["incoming_warnings"] += 1
		mission.state.log_event("incoming_warning", {"eta_s": snappedf(warning["eta"], 0.1)})
	incoming_warning = warning
	traffic_visuals.sync(traffic.active_entities())


## Radar picture and incoming warning for the HUD (sensor output only).
func _update_radar() -> void:
	if sensor == null or hud.radar == null:
		return
	var radar = hud.radar
	radar.own_position = drone.global_position
	radar.own_yaw = drone.rotation.y
	radar.contacts = sensor.contact_list()
	var marks: Array = [{"kind": "destination", "position": mission.landing_zone.global_position, "label": "LZ"}]
	var next: int = mission.state.next_checkpoint
	if next < mission.checkpoints.size():
		marks.append({"kind": "waypoint", "position": mission.checkpoints[next].global_position, "label": str(next + 1)})
	for site in traffic.sites:
		marks.append({"kind": "threat_area", "position": site, "radius": float(traffic.config["site_range_m"])})
	radar.marks = marks
	radar.status_text = "%d contact%s" % [radar.contacts.size(), "" if radar.contacts.size() == 1 else "s"]
	if incoming_warning.is_empty():
		hud.show_incoming({}, Vector2.ZERO, "")
		return
	var from: Vector3 = incoming_warning["from"]
	var screen := Vector2(from.x, from.z).rotated(drone.rotation.y)
	var angle := rad_to_deg(screen.angle_to(Vector2(0, -1)))
	var side := "ahead"
	if absf(angle) > 135.0:
		side = "behind"
	elif angle > 45.0:
		side = "left"
	elif angle < -45.0:
		side = "right"
	hud.show_incoming(incoming_warning, screen, "from " + side)


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
	_setup_traffic()
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
	_update_radar()
	if state.is_finished() and not _finished_shown:
		_finished_shown = true
		_finish()


## Saves the record and shows the result screen.
func _finish() -> void:
	var state: MissionState = mission.state
	var created := Time.get_datetime_string_from_system(true) + "Z"
	var session_id := "flight-%s-%d-%d" % [mission_def["id"], Time.get_unix_time_from_system(), Time.get_ticks_msec() % 1000]
	var extra := {}
	if traffic != null:
		extra["threats"] = threat_stats.duplicate()
		extra["radar_contacts_seen"] = sensor.contacts_seen()
	record = FlightRecord.build(state, mission_def, profile_id, DroneProfiles.get_profile(profile_id), session_id, created, extra)
	if traffic != null:
		hud.show_incoming({}, Vector2.ZERO, "")
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
