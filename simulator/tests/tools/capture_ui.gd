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
	for shot in ["menu", "settings", "flight_hud", "flight_pause", "flight_controls", "observation", "observation_pause"]:
		if only.is_empty() or shot in only:
			await call(shot)
	quit(0)


func menu() -> void:
	await _goto("menu")
	await _save("menu")


func settings() -> void:
	await _goto("settings")
	await _save("settings")


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
