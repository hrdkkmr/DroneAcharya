extends SceneTree
## Visual check (needs a window, not --headless). The test autopilot flies the real
## main scene with real input actions and screenshots are saved along the way.
## Usage:
##   Godot_v4.7.2-stable_win64_console.exe --path simulator --script res://tests/tools/capture_flythrough.gd -- --out=C:/some/folder

const Autopilot := preload("res://tests/tools/autopilot.gd")
const SHOT_TIMES := [1.0, 6.0, 12.0] ## seconds after start, follow camera
const ONBOARD_WINDOW := Vector2(16.0, 19.0) ## seconds during which the onboard camera is used


func _initialize() -> void:
	var out_dir := "user://captures"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Measure real rendering headroom rather than the monitor's refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await process_frame
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var pilot := Autopilot.new()
	var start := Time.get_ticks_msec()
	var shots := SHOT_TIMES.duplicate()
	var onboard_taken := false
	var fps_samples: Array[float] = []
	var frames := 0
	while frames < 60 * 90 and not main.mission.state.is_finished():
		pilot.fly_mission(main.drone, main.mission)
		await physics_frame
		frames += 1
		var t := frames / 60.0
		var in_onboard := t >= ONBOARD_WINDOW.x and t < ONBOARD_WINDOW.y
		if in_onboard != (main.camera_rig.mode == main.camera_rig.Mode.ONBOARD):
			main.camera_rig.toggle_mode()
		if frames % 30 == 0 and t > 2.0:  # skip start-up shader compilation
			fps_samples.append(Engine.get_frames_per_second())
		if not shots.is_empty() and t >= shots[0]:
			await _save(out_dir, "follow_%02ds" % int(shots.pop_front()))
		if in_onboard and not onboard_taken and t >= ONBOARD_WINDOW.x + 1.0:
			onboard_taken = true
			await _save(out_dir, "onboard")
	pilot.release_all()
	for i in 60:
		await physics_frame
	await _save(out_dir, "finish")
	fps_samples.sort()
	var average := 0.0
	for value in fps_samples:
		average += value
	average /= maxf(fps_samples.size(), 1.0)
	print("CAPTURE status=%d elapsed=%.1fs wall=%.1fs fps_avg=%.0f fps_min=%.0f" % [
		main.mission.state.status, main.mission.state.elapsed_seconds,
		(Time.get_ticks_msec() - start) / 1000.0, average, fps_samples[0] if fps_samples.size() else 0.0])
	quit(0 if main.mission.state.status == 2 else 1)


func _save(out_dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
