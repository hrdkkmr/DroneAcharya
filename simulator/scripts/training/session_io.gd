extends RefCounted
## Saving, loading, validating, exporting and importing droneacharya-session v1
## records. Validation is strict: structure, event order, references and a
## recompute-and-compare of the stored evaluation (the VIGIL policy: never trust a
## stored score, never repair a record). Invalid files are reported, never modified.
## JSON Schema for the structure: schemas/droneacharya-session-1.schema.json.

const SessionRecord := preload("res://scripts/training/session_record.gd")
const Rubric := preload("res://scripts/training/rubric.gd")
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")

const SESSIONS_DIR := "user://sessions"
const EXPORT_DIR := "user://exports"
const BUNDLE_FORMAT := "droneacharya-history"
const BUNDLE_VERSION := 1
const MAX_FILE_BYTES := 20 * 1024 * 1024
const STATUSES := ["completed", "aborted"]
const EVENT_TYPES := ["started", "paused", "resumed", "finished", "sensor_degraded", "sensor_restored",
	"track_created", "track_confirmed", "track_coasting", "track_reacquired", "track_lost", "track_dropped",
	"model_output", "action", "decision_support_visible"]
const ID_PATTERN := "^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$"


## Canonical JSON text (sorted keys, numbers normalised through a JSON round trip).
static func canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true)), "", true)


static func validate(record: Variant, recompute := true) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(record) != TYPE_DICTIONARY:
		return {"ok": false, "errors": PackedStringArray(["session must be a JSON object"])}
	var r: Dictionary = record
	if r.get("format") != SessionRecord.FORMAT or int(r.get("format_version", -1)) != SessionRecord.FORMAT_VERSION:
		errors.append("format must be %s version %d" % [SessionRecord.FORMAT, SessionRecord.FORMAT_VERSION])
		return {"ok": false, "errors": errors}
	for key in ["session_id", "created_at", "scenario", "generator", "tick_rate", "status", "end_tick", "end_t",
			"models", "spam_count", "events", "observations", "tracks", "truth", "evaluation"]:
		if not r.has(key):
			errors.append("missing field: " + key)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var regex := RegEx.create_from_string(ID_PATTERN)
	if typeof(r["session_id"]) != TYPE_STRING or regex.search(r["session_id"]) == null:
		errors.append("session_id must be a short identifier")
	var scenario := ScenarioConfig.validate(r["scenario"])
	if not scenario["ok"]:
		errors.append("scenario invalid: " + "; ".join(scenario["errors"]))
	if not r["status"] in STATUSES:
		errors.append("status must be completed or aborted")
	if int(r["tick_rate"]) != 20:
		errors.append("tick_rate must be 20")
	_validate_events(r, errors)
	_validate_observations_and_tracks(r, errors)
	_validate_truth(r, errors)
	if errors.is_empty() and recompute:
		var stored: Variant = r["evaluation"]
		var copy: Dictionary = r.duplicate(true)
		copy.erase("evaluation")
		var computed := Rubric.evaluate(copy)
		if canonical(stored) != canonical(computed):
			errors.append("stored evaluation does not match %s applied to the recorded events (record not repaired)" % Rubric.VERSION)
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_events(r: Dictionary, errors: PackedStringArray) -> void:
	var events = r["events"]
	if typeof(events) != TYPE_ARRAY or (events as Array).is_empty():
		errors.append("events must be a non-empty array")
		return
	var last_tick := 0
	for i in events.size():
		var e = events[i]
		if typeof(e) != TYPE_DICTIONARY or not e.has_all(["seq", "tick", "t", "type", "data"]):
			errors.append("event %d is malformed" % (i + 1))
			return
		if int(e["seq"]) != i + 1:
			errors.append("event sequence numbers must be contiguous (at %d)" % (i + 1))
			return
		if int(e["tick"]) < last_tick:
			errors.append("event ticks must not decrease (event %d)" % (i + 1))
			return
		if not e["type"] in EVENT_TYPES:
			errors.append("unknown event type '%s'" % e["type"])
			return
		last_tick = int(e["tick"])
	if events[0]["type"] != "started":
		errors.append("first event must be 'started'")
	var finish: Dictionary = events[-1]
	if finish["type"] != "finished" or finish["data"].get("outcome") != r["status"]:
		errors.append("last event must be 'finished' with the record's status")
	if int(finish["tick"]) != int(r["end_tick"]):
		errors.append("end_tick must equal the final event's tick")
	if typeof(r["scenario"]) == TYPE_DICTIONARY and _is_number(r["scenario"].get("duration_s")):
		var duration_ticks := int(r["scenario"]["duration_s"]) * 20
		if int(r["end_tick"]) > duration_ticks or (r["status"] == "completed" and int(r["end_tick"]) != duration_ticks):
			errors.append("end_tick is inconsistent with the scenario duration and status")


static func _validate_observations_and_tracks(r: Dictionary, errors: PackedStringArray) -> void:
	var obs = r["observations"]
	if typeof(obs) != TYPE_DICTIONARY or obs.get("columns") != SessionRecord.OBSERVATION_COLUMNS or typeof(obs.get("rows")) != TYPE_ARRAY:
		errors.append("observations must use the documented columns")
		return
	var ids := {}
	for row in obs["rows"]:
		if typeof(row) != TYPE_ARRAY or row.size() != SessionRecord.OBSERVATION_COLUMNS.size():
			errors.append("observation row has the wrong number of columns")
			return
		ids[row[0]] = true
	if typeof(r["tracks"]) != TYPE_ARRAY:
		errors.append("tracks must be an array")
		return
	for track in r["tracks"]:
		if typeof(track) != TYPE_DICTIONARY or not track.has_all(["id", "status", "created_t", "confirmed_t", "obs_ids"]):
			errors.append("track entry is malformed")
			return
		for obs_id in track["obs_ids"]:
			if not ids.has(obs_id):
				errors.append("track %s references unknown observation %s" % [track["id"], obs_id])
				return


static func _validate_truth(r: Dictionary, errors: PackedStringArray) -> void:
	var truth = r["truth"]
	if typeof(truth) != TYPE_DICTIONARY or not truth.has_all(["actors", "links", "events", "availability", "protected_zone_radius_m"]):
		errors.append("truth section is incomplete")
		return
	var actors := {}
	for a in truth["actors"]:
		if typeof(a) != TYPE_DICTIONARY or not a.has_all(["id", "profile", "significant", "group_id"]):
			errors.append("truth actor is malformed")
			return
		actors[a["id"]] = true
	for obs_id in truth["links"]:
		var source: String = truth["links"][obs_id]
		if source != "clutter" and not actors.has(source):
			errors.append("truth link %s points to unknown actor %s" % [obs_id, source])
			return


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


# --- Files --------------------------------------------------------------------------

static func save(record: Dictionary, directory := SESSIONS_DIR) -> Dictionary:
	var check := validate(record)
	if not check["ok"]:
		return {"ok": false, "error": "not saved: " + "; ".join(check["errors"])}
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join(record["session_id"] + ".json")
	if FileAccess.file_exists(path):
		var existing := load_file(path)
		if existing["ok"] and canonical(existing["record"]) == canonical(record):
			return {"ok": true, "path": path}
		return {"ok": false, "error": "a different session with id %s already exists; nothing overwritten" % record["session_id"]}
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot write " + temp}
	file.store_string(JSON.stringify(record))
	file.close()
	if DirAccess.rename_absolute(temp, path) != OK:
		return {"ok": false, "error": "cannot move %s into place" % temp}
	return {"ok": true, "path": path}


static func load_file(path: String, recompute := true) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": PackedStringArray(["file not found"]), "record": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file.get_length() > MAX_FILE_BYTES:
		return {"ok": false, "errors": PackedStringArray(["file exceeds 20 MiB"]), "record": {}}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"ok": false, "errors": PackedStringArray(["not valid JSON (line %d)" % json.get_error_line()]), "record": {}}
	var result := validate(json.data, recompute)
	result["record"] = json.data if result["ok"] else {}
	return result


## All saved sessions, newest first. Invalid files are listed separately with reasons
## and left untouched on disk.
static func list_history(directory := SESSIONS_DIR) -> Dictionary:
	var sessions := []
	var invalid := []
	if not DirAccess.dir_exists_absolute(directory):
		return {"sessions": sessions, "invalid": invalid}
	var files := Array(DirAccess.get_files_at(directory))
	files.sort()
	for name in files:
		if not name.ends_with(".json"):
			continue
		var result := load_file(directory.path_join(name))
		if result["ok"]:
			sessions.append(result["record"])
		else:
			invalid.append({"file": name, "reason": "; ".join(result["errors"])})
	sessions.sort_custom(func(a, b): return String(a["created_at"]) > String(b["created_at"]) or (a["created_at"] == b["created_at"] and String(a["session_id"]) > String(b["session_id"])))
	return {"sessions": sessions, "invalid": invalid}


static func export_bundle(records: Array, path: String) -> Dictionary:
	var bundle := {"format": BUNDLE_FORMAT, "format_version": BUNDLE_VERSION,
		"exported_at": Time.get_datetime_string_from_system(true) + "Z", "sessions": records}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot write " + path}
	file.store_string(JSON.stringify(bundle))
	file.close()
	return {"ok": true, "path": path, "count": records.size()}


## Validates every session in a bundle first; imports nothing if any is invalid or
## conflicts with an existing session of the same id. Identical duplicates are skipped.
static func import_bundle(path: String, directory := SESSIONS_DIR) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "file not found"}
	var text := FileAccess.get_file_as_string(path)
	if text.length() > MAX_FILE_BYTES:
		return {"ok": false, "error": "file exceeds 20 MiB"}
	var bundle = JSON.parse_string(text)
	if typeof(bundle) != TYPE_DICTIONARY or bundle.get("format") != BUNDLE_FORMAT or int(bundle.get("format_version", -1)) != BUNDLE_VERSION:
		return {"ok": false, "error": "not a %s v%d file" % [BUNDLE_FORMAT, BUNDLE_VERSION]}
	var incoming: Array = bundle.get("sessions", [])
	var seen := {}
	for record in incoming:
		var check := validate(record)
		if not check["ok"]:
			return {"ok": false, "error": "session %s invalid: %s" % [str(record.get("session_id", "?")) if typeof(record) == TYPE_DICTIONARY else "?", "; ".join(check["errors"])]}
		if seen.has(record["session_id"]):
			return {"ok": false, "error": "duplicate session id %s in the file" % record["session_id"]}
		seen[record["session_id"]] = true
		var existing_path := directory.path_join(record["session_id"] + ".json")
		if FileAccess.file_exists(existing_path):
			var existing := load_file(existing_path, false)
			if not existing["ok"] or canonical(existing["record"]) != canonical(record):
				return {"ok": false, "error": "session %s conflicts with an existing session; nothing imported" % record["session_id"]}
	var added := 0
	for record in incoming:
		if not FileAccess.file_exists(directory.path_join(record["session_id"] + ".json")):
			var saved := save(record, directory)
			if not saved["ok"]:
				return {"ok": false, "error": saved["error"]}
			added += 1
	return {"ok": true, "added": added, "skipped": incoming.size() - added}
