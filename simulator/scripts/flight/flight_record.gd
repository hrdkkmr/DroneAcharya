extends RefCounted
## Versioned record of one flight-training mission ("droneacharya-flight-session").
## Built from the pure MissionState when a mission ends, saved as JSON next to the
## threat-observation sessions (in its own folder), and read back by the history
## screen. `validate()` accepts every known version; readers dispatch on
## `format_version` so older files stay readable when the format grows.

const FORMAT := "droneacharya-flight-session"
const FORMAT_VERSION := 1
const SUPPORTED_VERSIONS := [1]
const STATUS_NAMES := ["ready", "flying", "completed", "failed"]
const REQUIRED := ["format", "format_version", "session_id", "created_at", "mission", "profile", "result", "events"]
const MAX_BYTES := 2 * 1024 * 1024


static func build(state: RefCounted, mission: Dictionary, profile_id: String, profile: Dictionary, session_id: String,
		created_at: String, extra := {}) -> Dictionary:
	var result := {
		"status": STATUS_NAMES[state.status],
		"failure_reason": state.failure_reason,
		"elapsed_s": snappedf(state.elapsed_seconds, 0.01),
		"time_limit_s": state.time_limit_s,
		"checkpoints_passed": state.next_checkpoint,
		"checkpoint_count": state.checkpoint_count,
		"checkpoint_times": state.checkpoint_times.duplicate(),
		"wrong_checkpoints": state.wrong_checkpoint_count,
		"bumps": state.bump_count,
		"hits": state.hit_count,
		"integrity_end": snappedf(state.integrity, 0.1),
		"battery_end": snappedf(state.battery_fraction(), 0.001),
		"endurance_s": state.endurance_s,
		"landed_in_zone": STATUS_NAMES[state.status] == "completed",
	}
	result.merge(extra, true)
	return {
		"format": FORMAT, "format_version": FORMAT_VERSION,
		"session_id": session_id, "created_at": created_at,
		"mission": {"id": mission["id"], "title": mission["title"], "environment": mission["environment"],
			"hostile": mission.get("hostile", false)},
		"profile": {"id": profile_id, "title": profile["title"]},
		"result": result,
		"events": state.events.duplicate(true),
	}


## {ok, errors} — structural checks for any supported version.
static func validate(record: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(record) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["not a JSON object"]}
	for key in REQUIRED:
		if not record.has(key):
			errors.append("missing '%s'" % key)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	if record["format"] != FORMAT:
		errors.append("format is '%s', expected '%s'" % [record["format"], FORMAT])
	if not int(record["format_version"]) in SUPPORTED_VERSIONS:
		errors.append("unsupported format_version %s" % record["format_version"])
	var result = record["result"]
	if typeof(result) != TYPE_DICTIONARY or not result.has("status") or not result.get("status") in STATUS_NAMES:
		errors.append("result.status missing or unknown")
	if typeof(record["events"]) != TYPE_ARRAY:
		errors.append("events must be an array")
	return {"ok": errors.is_empty(), "errors": errors}


static func save(record: Dictionary, dir: String) -> Dictionary:
	var check := validate(record)
	if not check["ok"]:
		return {"ok": false, "error": "; ".join(check["errors"])}
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("%s.json" % String(record["session_id"]).validate_filename())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]}
	file.store_string(JSON.stringify(record, "  "))
	file.close()
	return {"ok": true, "path": path}


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "file not found"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {"ok": false, "error": "unreadable or too large"}
	var parsed = JSON.parse_string(file.get_as_text())
	var check := validate(parsed)
	if not check["ok"]:
		return {"ok": false, "error": "; ".join(check["errors"])}
	return {"ok": true, "record": parsed}


## Valid records in `dir`, newest first (by created_at), plus invalid files with reasons.
static func list_history(dir: String) -> Dictionary:
	var records := []
	var invalid := []
	if DirAccess.dir_exists_absolute(dir):
		for name in DirAccess.get_files_at(dir):
			if not name.ends_with(".json"):
				continue
			var loaded := load_file(dir.path_join(name))
			if loaded["ok"]:
				records.append(loaded["record"])
			else:
				invalid.append({"file": name, "error": loaded["error"]})
	records.sort_custom(func(a, b): return String(a["created_at"]) > String(b["created_at"]))
	return {"records": records, "invalid": invalid}
