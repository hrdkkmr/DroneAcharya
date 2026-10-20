extends SceneTree
## Screenshots of the redesigned screens for visual checks (needs a window).
## Usage:
##   Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path simulator --script res://tests/tools/capture_ui.gd -- --out=C:/folder [--size=1366x768] [--shots=menu,flight_pause]

const AppState := preload("res://scripts/app/app_state.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const SettingsStore := preload("res://scripts/app/settings_store.gd")

var out_dir := "user://captures"
var only: PackedStringArray = []
var suffix := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--shots="):
			only = arg.trim_prefix("--shots=").split(",")
		elif arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
			suffix = "_" + arg.trim_prefix("--size=")
	SettingsStore.path = "user://test_runs/capture_settings.cfg"
	SettingsStore.load_settings()
	AppState.sessions_dir = "user://test_runs/capture_sessions"
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	for shot in ["menu", "settings", "flight_briefing", "flight_hud", "flight_pause", "flight_controls", "observation", "observation_pause", "city", "village", "hostile", "tutorial", "threat_briefing", "observation_alarm", "report_threat"]:
		if only.is_empty() or shot in only:
			await call(shot)
	quit(0)


func menu() -> void:
	await _goto("menu")
	await _save("menu")


func settings() -> void:
	await _goto("settings")
	await _save("settings")


func flight_briefing() -> void:
	await _goto("flight_briefing")
	await _save("flight_briefing")


func flight_hud() -> void:
	var scene := await _goto("flight")
	Input.action_press("ascend")
	for i in 90:
		await physics_frame
	Input.action_release("ascend")
	await _save("flight_hud")
	scene.set_paused(true)


func flight_pause() -> void:
	var scene := await _goto("flight")
	scene.set_paused(true)
	await _save("flight_pause")


func flight_controls() -> void:
	var scene := await _goto("flight")
	scene.set_paused(true)
	scene.hud.overlay.press("controls")
	await _save("flight_controls")


func observation() -> void:
	AppState.selected_config = ScenarioConfig.load_file("res://scenarios/02_swarm_urban_day.json")["config"]
	var scene := await _goto("observation")
	while scene.session.time_s() < 70.0:
		scene.session.step()
	scene.cycle_track()
	scene.centre_on_selected()
	for i in 20:
		await process_frame
	await _save("observation")


func observation_pause() -> void:
	AppState.selected_config = ScenarioConfig.load_file("res://scenarios/02_swarm_urban_day.json")["config"]
	var scene := await _goto("observation")
	scene.toggle_pause()
	await _save("observation_pause")


func city() -> void:
	await _environment("city_delivery", "city", Vector3(-90, 3, -50), Vector3(-30, 60, 40), Vector3(30, 0, -150))


func village() -> void:
	await _environment("village_supply", "village", Vector3(-40, 3, 0), Vector3(-120, 70, 60), Vector3(40, 0, -150))


## Chase view after a short climb, then a high oblique overview from a scratch camera.
func _environment(mission: String, shot: String, start: Vector3, overview_from: Vector3, overview_to: Vector3) -> void:
	AppState.flight_mission = mission
	var scene := await _goto("flight")
	Input.action_press("ascend")
	for i in 150:
		await physics_frame
	Input.action_release("ascend")
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	Input.action_release("move_forward")
	await _save(shot + "_chase")
	var camera := Camera3D.new()
	camera.far = 2000.0
	scene.add_child(camera)
	camera.look_at_from_position(overview_from, overview_to)
	camera.make_current()
	await _save(shot + "_overview")
	AppState.flight_mission = "basic_course"


## Hostile village mission: hover near an emplacement until the incoming warning shows.
func hostile() -> void:
	AppState.flight_mission = "village_hostile"
	var scene := await _goto("flight")
	scene.mission.state.status = 1
	for i in 60 * 30:
		scene.drone.global_position = Vector3(-60, 14, -42)
		scene.drone.velocity = Vector3.ZERO
		await physics_frame
		if scene.hud.has_alert("incoming") and scene.incoming_warning.get("eta", 9.0) < 2.5:
			break
	await _save("hostile_incoming")
	AppState.flight_mission = "basic_course"


func tutorial() -> void:
	var scene := await _goto("tutorial")
	await _save("tutorial_step1")
	for i in 3:
		scene.panel.next()
	scene.panel.practice_radar.contact_clicked.emit("T2")
	await _save("tutorial_practice")


func threat_briefing() -> void:
	AppState.selected_config = ScenarioConfig.load_file("res://scenarios/02_swarm_urban_day.json")["config"]
	await _goto("briefing")
	await _save("threat_briefing")


## Swarm scenario: classify a contact, then highlight an alarm to show the confirmation.
func observation_alarm() -> void:
	AppState.selected_config = ScenarioConfig.load_file("res://scenarios/02_swarm_urban_day.json")["config"]
	var scene := await _goto("observation")
	while scene.session.time_s() < 75.0:
		scene.session.step()
	var groups: Dictionary = scene.session.tracker.groups
	if not groups.is_empty():
		scene.select_track("group:" + groups.keys()[0])
	else:
		scene.cycle_track()
	scene.centre_on_selected()
	scene.hud.highlight["classify"] = 4
	scene.hud.confirm()
	scene.hud._busy_until_ms = 0
	scene.hud.highlight["respond"] = 4
	scene.hud.confirm()
	for i in 20:
		await process_frame
	await _save("observation_alarm")


## Plays a scripted swarm exercise (acknowledge late, classify with the rule-based
## aid's call) into a scratch history folder and shows its report.
func report_threat() -> void:
	var ThreatSession = load("res://scripts/sim/threat_session.gd")
	var SessionRecord = load("res://scripts/training/session_record.gd")
	var Rubric = load("res://scripts/training/rubric.gd")
	var SessionIO = load("res://scripts/training/session_io.gd")
	DirAccess.make_dir_recursive_absolute(AppState.sessions_dir)
	for name in DirAccess.get_files_at(AppState.sessions_dir):
		DirAccess.remove_absolute(AppState.sessions_dir.path_join(name))
	var session = ThreatSession.new(ScenarioConfig.load_file("res://scenarios/03_mixed_rural_night_degraded.json")["config"], null)
	session.start()
	while not session.is_finished():
		session.step()
		if session.tick() % 20 != 0 or session.time_s() < 25.0:
			continue
		for track in session.tracker.confirmed_tracks():
			var advice: Dictionary = session.decisions.recommendation_for(track["id"])
			if advice.is_empty() or not session.trainee_state(track["id"]).is_empty():
				continue
			session.classify(track["id"], advice["rules"]["category"], 80, true)
			session.respond(track["id"], advice["policy"]["response"])
	var record: Dictionary = SessionRecord.build(session, "capture-report", "2026-10-20T12:00:00Z")
	record["evaluation"] = Rubric.evaluate(record)
	SessionIO.save(record, AppState.sessions_dir)
	AppState.review_session = record
	await _goto("history")
	await _save("report_threat")


func _goto(scene: String) -> Node:
	AppState.goto(self, scene)
	for i in 6:
		await process_frame
	return current_scene


func _save(shot: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(shot + suffix + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
