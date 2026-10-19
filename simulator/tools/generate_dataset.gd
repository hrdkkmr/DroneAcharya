extends SceneTree
## Generates the labelled synthetic track dataset for Model 2 (offline, headless).
## Each scenario is a seeded procedural config; seeds never overlap between splits.
## Every 5 simulated seconds each confirmed track contributes one sample: its
## features-1 vector (the exact inference-time inputs) plus a label taken from the
## truth links of its observations. Truth is used here only to create labels.
##
## Usage (from the workspace root):
##   Godot_v4.7.2-stable_win64_console.exe --headless --path simulator --script res://tools/generate_dataset.gd -- --split=train --out=E:/.../ml/data/train.csv
## Options: --split=train|val|test|degraded  --count=N  --start=SEED  --out=PATH

const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const Features := preload("res://scripts/ai/features.gd")
const RuleEngine := preload("res://scripts/ai/rule_engine.gd")
const Vocabulary := preload("res://scripts/ai/vocabulary.gd")
const SimRandom := preload("res://scripts/sim/sim_random.gd")

const SAMPLE_EVERY_S := 5.0
const MIN_TRACK_DURATION_S := 2.0
const SPLITS := {
	"train": {"start": 100000, "count": 600},
	"val": {"start": 200000, "count": 150},
	"test": {"start": 300000, "count": 200},
	"degraded": {"start": 400000, "count": 100},
}
const META_COLUMNS := ["split", "scenario_seed", "difficulty", "environment", "time_of_day", "visibility",
	"t", "track_id", "label", "label_purity", "rule_category", "rule_evidence"]


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			args[parts[0]] = parts[1]
	var split: String = args.get("split", "train")
	if not SPLITS.has(split):
		printerr("unknown split ", split)
		quit(2)
		return
	var start := int(args.get("start", SPLITS[split]["start"]))
	var count := int(args.get("count", SPLITS[split]["count"]))
	var out: String = args.get("out", "user://%s.csv" % split)
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		printerr("cannot write ", out)
		quit(2)
		return
	file.store_line(",".join(PackedStringArray(META_COLUMNS + Features.NAMES)))
	var started := Time.get_ticks_msec()
	var samples := 0
	var labels := {}
	for i in count:
		var seed_value := start + i
		var config := _config(split, seed_value)
		for row in _run(split, config):
			file.store_line(row["line"])
			samples += 1
			labels[row["label"]] = labels.get(row["label"], 0) + 1
		if (i + 1) % 25 == 0:
			print("%s: %d/%d scenarios, %d samples, %.0f s" % [split, i + 1, count, samples, (Time.get_ticks_msec() - started) / 1000.0])
	file.close()
	print("DONE %s scenarios=%d samples=%d labels=%s seconds=%.0f" % [split, count, samples, labels, (Time.get_ticks_msec() - started) / 1000.0])
	quit(0)


## Procedural config per seed. The degraded split forces night or fog, high
## difficulty and a long degradation window.
static func _config(split: String, seed_value: int) -> Dictionary:
	var rng := SimRandom.stream(seed_value, "dataset-options")
	var options := {"difficulty": 1 + rng.randi() % 5, "swarm": rng.randf() < 0.5}
	if split == "degraded":
		options["difficulty"] = 4 + rng.randi() % 2
		if rng.randf() < 0.5:
			options["time_of_day"] = "night"
		else:
			options["visibility"] = "fog"
	var config: Dictionary = ScenarioConfig.generate(seed_value, options)["config"]
	if split == "degraded":
		config["sensor"]["degradation"] = [{"start_s": 20.0, "end_s": float(config["duration_s"]) - 20.0, "severity": 0.6}]
	return config


func _run(split: String, config: Dictionary) -> Array:
	var session := ThreatSession.new(config)
	session.run_decisions = false
	session.start()
	var context := Features.context_from(session.definition)
	var profiles := {}
	for actor in session.definition["actors"]:
		profiles[actor["id"]] = actor["profile"]
	var links: Dictionary = session.sensor.truth_links
	var every := int(SAMPLE_EVERY_S * session.definition["tick_rate"])
	var rows := []
	while not session.is_finished():
		session.step()
		if session.tick() % every != 0:
			continue
		var tracks := session.tracker.confirmed_tracks()
		for track in tracks:
			if float(track["last_update_t"]) - float(track["created_t"]) < MIN_TRACK_DURATION_S:
				continue
			var label := _label(track, links, profiles)
			var features := Features.extract(track, tracks, context, session.time_s())
			var rules := RuleEngine.assess(features)
			var values := PackedStringArray([split, str(config["seed"]), str(config["difficulty"]), config["environment"],
				config["time_of_day"], config["visibility"], "%.2f" % session.time_s(), track["id"], label["label"],
				"%.3f" % label["purity"], rules["category"], rules["evidence"]])
			for name in Features.NAMES:
				values.append("%.5f" % float(features[name]))
			rows.append({"line": ",".join(values), "label": label["label"]})
	return rows


## Majority truth source of the track's observations → training category.
static func _label(track: Dictionary, links: Dictionary, profiles: Dictionary) -> Dictionary:
	var votes := {}
	for obs_id in track["obs_ids"]:
		var source: String = links.get(obs_id, "clutter")
		votes[source] = votes.get(source, 0) + 1
	var best := "clutter"
	var best_votes := 0
	var keys := votes.keys()
	keys.sort()
	for source in keys:
		if votes[source] > best_votes:
			best = source
			best_votes = votes[source]
	var category := "clutter" if best == "clutter" else String(Vocabulary.TRUTH_CATEGORY_FOR_PROFILE[profiles[best]])
	return {"label": category, "purity": float(best_votes) / maxf(float(track["obs_ids"].size()), 1.0)}
