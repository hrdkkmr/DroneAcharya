extends SceneTree
## Visual check of menus and observation scenarios (needs a window, not --headless).
## Test aid only: it may read actor positions to aim the camera for screenshots.
## Usage:
##   Godot_v4.7.2-stable_win64_console.exe --path simulator --script res://tests/tools/capture_screens.gd -- --out=C:/some/folder

const AppState := preload("res://scripts/app/app_state.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const SessionRecord := preload("res://scripts/training/session_record.gd")
const SessionIO := preload("res://scripts/training/session_io.gd")
const Rubric := preload("res://scripts/training/rubric.gd")
const MlClassifier := preload("res://scripts/ai/ml_classifier.gd")

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
	await _visit("settings", "settings")
	await _observe("res://scenarios/02_swarm_urban_day.json", "swarm_urban_day_sensor", "swarm_uav", 70.0, 6.0, true)
	await _observe("res://scenarios/02_swarm_urban_day.json", "swarm_urban_day_eye", "", 70.0, 60.0, false)
	await _observe("res://scenarios/03_mixed_rural_night_degraded.json", "mixed_rural_night_thermal", "unidentified_uav", 60.0, 8.0, true)
	await _observe("res://scenarios/04_single_urban_fog.json", "single_urban_fog_eye", "unidentified_uav", 40.0, 40.0, false)
	await _review_and_replay()
	quit(0)


## Plays a scripted session into a scratch history folder, then captures the
## after-action review and the 3D replay with truth labels.
func _review_and_replay() -> void:
	AppState.sessions_dir = "user://test_runs/capture_sessions"
	DirAccess.make_dir_recursive_absolute(AppState.sessions_dir)
	for name in DirAccess.get_files_at(AppState.sessions_dir):
		DirAccess.remove_absolute(AppState.sessions_dir.path_join(name))
	var session := ThreatSession.new(ScenarioConfig.load_file("res://scenarios/02_swarm_urban_day.json")["config"], MlClassifier.shared())
	session.start()
	while not session.is_finished():
		session.step()
		if session.tick() % 20 != 0:
			continue
		for track in session.tracker.confirmed_tracks():
			var state := session.trainee_state(track["id"])
			var advice: Dictionary = session.decisions.recommendation_for(track["id"])
			if advice.is_empty() or session.time_s() < 30.0:
				continue
			if state.is_empty():
				session.acknowledge(track["id"])
			elif String(state["response"]).is_empty() and advice["rules"]["evidence"] == "good":
				session.classify(track["id"], advice["rules"]["category"], 75)
				session.respond(track["id"], advice["policy"]["response"])
	var record := SessionRecord.build(session, "capture-review", "2026-10-20T12:00:00Z")
	record["evaluation"] = Rubric.evaluate(record)
	print("capture session saved: ", SessionIO.save(record, AppState.sessions_dir)["ok"])
	AppState.review_session = record
	await _visit("history", "history_review")
	current_scene.replay_in_3d()
	for i in 5:
		await process_frame
	var scene: Node = current_scene
	scene.seek_replay(20 * 75)
	scene.replay_playing = false
	scene.set_truth_labels(true)
	scene.hud.truth_toggle.set_pressed_no_signal(true)
	scene.observer.set_sensor_mode(false)
	var target := Vector3(0, 0, -300)
	for actor in scene.session.world.actors:
		if actor["active"] and actor["def"]["profile"] == "swarm_uav":
			target = actor["state"].position
			break
	scene.observer.look_at_point(target)
	scene.observer.set_fov(25.0)
	for i in 30:
		await process_frame
	await _save("replay_truth_labels")


func _visit(scene: String, shot: String) -> void:
	AppState.goto(self, scene)
	for i in 5:
		await process_frame
	await _save(shot)


## Runs a scenario for `seconds`, aims at the first actor of `profile` (or the zone) and saves.
func _observe(path: String, shot: String, profile: String, seconds: float, fov: float, sensor: bool) -> void:
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
	scene.set_sensor_view(sensor)
	scene.observer.look_at_point(target)
	scene.observer.set_fov(fov)
	# Select the tracker track nearest the aim point (tracker output, as a trainee would).
	var best := ""
	var best_distance := INF
	for track in scene.session.tracker.confirmed_tracks():
		var d: float = (track["position"] as Vector3).distance_to(target)
		if d < best_distance:
			best_distance = d
			best = track["id"]
	if not best.is_empty():
		scene.select_track(best)
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
