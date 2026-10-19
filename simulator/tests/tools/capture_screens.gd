extends SceneTree
## Visual check of menus and observation scenarios (needs a window, not --headless).
## Test aid only: it may read actor positions to aim the camera for screenshots.
## Usage:
##   Godot_v4.7.2-stable_win64_console.exe --path simulator --script res://tests/tools/capture_screens.gd -- --out=C:/some/folder

const AppState := preload("res://scripts/app/app_state.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")

var out_dir := "user://captures"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await process_frame
	await _visit("menu", "menu")
	AppState.selected_config = ScenarioConfig.load_file("res://scenarios/02_swarm_urban_day.json")["config"]
	await _visit("scenario_select", "scenario_select")
	await _visit("briefing", "briefing")
	await _observe("res://scenarios/02_swarm_urban_day.json", "swarm_urban_day", "swarm_uav", 40.0, 8.0)
	await _observe("res://scenarios/02_swarm_urban_day.json", "swarm_urban_day_wide", "", 40.0, 70.0)
	await _observe("res://scenarios/03_mixed_rural_night_degraded.json", "mixed_rural_night", "unidentified_uav", 30.0, 10.0)
	await _observe("res://scenarios/04_single_urban_fog.json", "single_urban_fog", "unidentified_uav", 30.0, 30.0)
	quit(0)


func _visit(scene: String, shot: String) -> void:
	AppState.goto(self, scene)
	for i in 5:
		await process_frame
	await _save(shot)


## Runs a scenario for `seconds`, aims at the first actor of `profile` (or the zone) and saves.
func _observe(path: String, shot: String, profile: String, seconds: float, fov: float) -> void:
	AppState.selected_config = ScenarioConfig.load_file(path)["config"]
	AppState.goto(self, "observation")
	for i in 5:
		await process_frame
	var scene: Node = current_scene
	var start := Time.get_ticks_msec()
	var frames := 0
	while scene.session.time_s() < seconds:
		await physics_frame
		frames += 1
	var sim_fps := frames * 1000.0 / maxf(Time.get_ticks_msec() - start, 1.0)
	var target := Vector3(0, 0, -300)
	for record in scene.session.world.actors:
		if record["active"] and (profile.is_empty() or record["def"]["profile"] == profile):
			target = record["state"].position
			break
	scene.observer.look_at_point(target)
	scene.observer.set_fov(fov)
	var fps := []
	for i in 120:
		await process_frame
		if i > 30:
			fps.append(Engine.get_frames_per_second())
	await _save(shot)
	print("%s: active=%d fps=%.0f (physics loop %.0f/s)" % [shot, scene.session.world.active_ids().size(), fps.max(), sim_fps])


func _save(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(shot + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
