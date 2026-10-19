extends SceneTree
## Writes a deterministic example droneacharya-session file (fixed id and date,
## scripted trainee, rules-only so it does not depend on the ML artefact) for the
## schema documentation and tests.
## Usage: Godot_v4.7.2-stable_win64_console.exe --headless --path simulator --script res://tools/export_sample_session.gd -- --out=E:/.../schemas/examples/session_example.json

const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const SessionRecord := preload("res://scripts/training/session_record.gd")
const Rubric := preload("res://scripts/training/rubric.gd")


static func build() -> Dictionary:
	var config: Dictionary = ScenarioConfig.load_file("res://scenarios/01_single_rural_day.json")["config"]
	config["duration_s"] = 60
	var session := ThreatSession.new(config, null)
	session.start()
	while not session.is_finished():
		session.step()
		if session.tick() % 20 != 0:
			continue
		for track in session.tracker.confirmed_tracks():
			var state := session.trainee_state(track["id"])
			var advice: Dictionary = session.decisions.recommendation_for(track["id"])
			if advice.is_empty():
				continue
			if state.is_empty():
				session.acknowledge(track["id"])
			elif String(state["response"]).is_empty() and advice["rules"]["evidence"] != "insufficient":
				session.classify(track["id"], advice["rules"]["category"], 60)
				session.respond(track["id"], advice["policy"]["response"])
	var record := SessionRecord.build(session, "example-session-1", "2026-10-20T10:00:00Z")
	record["evaluation"] = Rubric.evaluate(record)
	return record


func _initialize() -> void:
	var out := "user://session_example.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(build(), " "))
	file.close()
	print("wrote ", out)
	quit(0)
