extends SceneTree
## Performance measurements (needs a window; vsync is disabled to measure headroom).
## Usage: Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path simulator --script res://tools/measure_performance.gd -- --out=C:/Temp/perf.json
## Reports: startup to first menu frame, simulation tick cost, decision-support cost,
## ML inference latency, session record size, and rendering frame rate for a
## 30-actor stress scenario and a typical preset.

const AppState := preload("res://scripts/app/app_state.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const SessionRecord := preload("res://scripts/training/session_record.gd")
const Rubric := preload("res://scripts/training/rubric.gd")
const MlClassifier := preload("res://scripts/ai/ml_classifier.gd")

var report := {}


func stress_config() -> Dictionary:
	var raw := {
		"format": "droneacharya-scenario", "version": 1, "id": "stress-30", "title": "Stress: 30 actors", "seed": 777,
		"environment": "urban", "time_of_day": "day", "visibility": "clear", "duration_s": 300, "difficulty": 5,
		"groups": [
			{"profile": "swarm_uav", "behavior": "transit", "count": 12, "spawn_s": [0, 5], "start_range_m": [600, 900]},
			{"profile": "swarm_uav", "behavior": "loiter", "count": 12, "spawn_s": [0, 5], "start_range_m": [600, 900]},
			{"profile": "bird", "behavior": "erratic", "count": 6, "spawn_s": [0, 5], "start_range_m": [200, 500]},
		],
		"sensor": {"clutter_per_min": 3.0},
	}
	var result := ScenarioConfig.validate(raw)
	assert(result["ok"])
	return result["config"]


func _initialize() -> void:
	var startup_ms := Time.get_ticks_msec()
	var out := "user://performance.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	AppState.sessions_dir = "user://test_runs/perf_sessions"
	AppState.goto(self, "menu")
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	report["startup_to_first_menu_frame_ms"] = Time.get_ticks_msec()
	report["engine_init_ms"] = startup_ms
	report["hardware"] = {"cpu": OS.get_processor_name(), "cores": OS.get_processor_count(),
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": DisplayServer.window_get_size()}
	report["stress_simulation"] = _measure_ticks(stress_config(), 300.0)
	report["typical_simulation"] = _measure_ticks(ScenarioConfig.load_file("res://scenarios/03_mixed_rural_night_degraded.json")["config"], 180.0)
	report["stress_render"] = await _measure_render(stress_config(), 20.0)
	report["typical_render"] = await _measure_render(ScenarioConfig.load_file("res://scenarios/02_swarm_urban_day.json")["config"], 20.0)
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, " "))
	file.close()
	print(JSON.stringify(report, " "))
	quit(0)


## Steps a full exercise without rendering; times every tick.
func _measure_ticks(config: Dictionary, seconds: float) -> Dictionary:
	var session := ThreatSession.new(config, MlClassifier.shared())
	session.start()
	var regular := []
	var decision := []
	var max_tracks := 0
	var max_actors := 0
	var size_at_60 := 0
	while session.time_s() < seconds and not session.is_finished():
		var t0 := Time.get_ticks_usec()
		session.step()
		var cost := Time.get_ticks_usec() - t0
		(decision if session.tick() % 20 == 0 else regular).append(cost)
		max_tracks = maxi(max_tracks, session.tracker.tracks.size())
		max_actors = maxi(max_actors, session.world.active_ids().size())
		if session.tick() == 20 * 60:
			size_at_60 = _record_bytes(session)
	var ml_latency := []
	for id in session.decisions.latest:
		var ml: Dictionary = session.decisions.latest[id]["ml"]
		if ml.get("ok", false):
			ml_latency.append(int(ml["latency_us"]))
	return {"simulated_s": session.time_s(), "max_active_actors": max_actors, "max_active_tracks": max_tracks,
		"tick_us": _stats(regular), "decision_tick_us": _stats(decision),
		"realtime_budget_used_pct": snappedf((_mean(regular) * 19 + _mean(decision)) / 1_000_000.0 * 100.0, 0.01),
		"ml_latency_us_last_outputs": _stats(ml_latency),
		"record_bytes_at_60s": size_at_60, "record_bytes_full": _record_bytes(session), "events": session.events.size(),
		"observations": session.observations.size()}


func _record_bytes(session: ThreatSession) -> int:
	var record := SessionRecord.build(session, "perf", "2026-10-20T00:00:00Z")
	record["evaluation"] = Rubric.evaluate(record)
	return JSON.stringify(record).to_utf8_buffer().size()


## Runs the observation scene and samples the frame rate in eye and sensor view.
func _measure_render(config: Dictionary, seconds: float) -> Dictionary:
	AppState.selected_config = config
	AppState.replay_requested = false
	AppState.goto(self, "observation")
	for i in 5:
		await process_frame
	var scene: Node = current_scene
	var result := {}
	for view in ["eye", "sensor"]:
		scene.set_sensor_view(view == "sensor")
		scene.observer.look_at_point(Vector3(-400, 80, -600))
		var frame_ms := []
		var started := Time.get_ticks_msec()
		var last := Time.get_ticks_usec()
		while Time.get_ticks_msec() - started < seconds * 500.0:
			await process_frame
			var now := Time.get_ticks_usec()
			frame_ms.append((now - last) / 1000.0)
			last = now
		frame_ms = frame_ms.slice(30)
		frame_ms.sort()
		var mean := _mean(frame_ms)
		result[view] = {"frames": frame_ms.size(), "fps_mean": snappedf(1000.0 / mean, 0.1),
			"fps_1pct_low": snappedf(1000.0 / frame_ms[int(frame_ms.size() * 0.99)], 0.1),
			"active_actors": scene.session.world.active_ids().size(), "tracks": scene.session.tracker.tracks.size()}
	return result


static func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0}
	var sorted := values.duplicate()
	sorted.sort()
	return {"n": sorted.size(), "mean": snappedf(_mean(sorted), 0.1), "p95": sorted[int(sorted.size() * 0.95)], "max": sorted[-1]}


static func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total / maxf(values.size(), 1.0)
