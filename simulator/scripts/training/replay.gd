extends RefCounted
## Deterministic replay of a recorded session: the scenario is rebuilt from its
## recorded config (same seed and generator), and every recorded trainee control
## event is re-applied at the tick it was recorded. Because the simulation is
## deterministic, the regenerated event log and evaluation must equal the record;
## verify() checks exactly that and reports any difference.
## Limitations: the same simulator and ML-model versions are required (a different
## ML model changes model outputs); wall-clock pause lengths are not part of the record.

const ThreatSession := preload("res://scripts/sim/threat_session.gd")
const SessionRecord := preload("res://scripts/training/session_record.gd")
const SessionIO := preload("res://scripts/training/session_io.gd")
const Rubric := preload("res://scripts/training/rubric.gd")
const Generator := preload("res://scripts/sim/scenario_generator.gd")

const CONTROL_TYPES := ["action", "paused", "resumed", "decision_support_visible", "finished"]

var record: Dictionary
var session: ThreatSession
var controls: Array = []
var warnings := PackedStringArray()
var _next := 0


func _init(recorded: Dictionary, classifier: RefCounted = null) -> void:
	record = recorded
	var recorded_ml: Dictionary = record["models"].get("ml", {})
	var use_ml: bool = recorded_ml.get("loaded", false)
	if use_ml and (classifier == null or not classifier.is_loaded()):
		warnings.append("The recorded session used ML model %s, which is not available; model outputs will differ." % recorded_ml.get("version", "?"))
	elif use_ml and classifier.version != recorded_ml.get("version"):
		warnings.append("The recorded session used ML model %s but %s is loaded; model outputs may differ." % [recorded_ml.get("version"), classifier.version])
	if record.get("generator") != Generator.GENERATOR_VERSION:
		warnings.append("Recorded with generator %s; this simulator has %s." % [record.get("generator"), Generator.GENERATOR_VERSION])
	session = ThreatSession.new(record["scenario"], classifier if use_ml else null)
	for e in record["events"]:
		if e["type"] in CONTROL_TYPES and not (e["type"] == "finished" and e["data"].get("outcome") == "completed"):
			controls.append(e)
	session.start()
	_apply_due()


func end_tick() -> int:
	return int(record["end_tick"])


func is_done() -> bool:
	return session.is_finished() or session.tick() >= end_tick()


## Advances the replay until `tick` (or the end), re-applying recorded controls.
func step_to(tick: int) -> void:
	tick = mini(tick, end_tick())
	while session.tick() < tick and not session.is_finished():
		if session.status == ThreatSession.Status.PAUSED:
			_apply_due()
			if session.status == ThreatSession.Status.PAUSED:
				break
		session.step()
		_apply_due()


func _apply_due() -> void:
	while _next < controls.size() and int(controls[_next]["tick"]) == session.tick():
		_apply(controls[_next])
		_next += 1


func _apply(e: Dictionary) -> void:
	var data: Dictionary = e["data"]
	match e["type"]:
		"paused":
			session.pause()
		"resumed":
			session.resume()
		"finished":
			session.abort()
		"decision_support_visible":
			session.log_event("decision_support_visible", {"visible": data["visible"]})
		"action":
			match data["kind"]:
				"acknowledge":
					session.acknowledge(data["track_id"])
				"classify":
					session.classify(data["track_id"], String(data.get("category", "")), int(data.get("confidence", -1)))
				"respond":
					session.respond(data["track_id"], String(data.get("response", "")))


## Replays to the end and compares the regenerated events and evaluation with the
## record. Returns {identical, events_match, evaluation_match, first_difference, warnings}.
func verify() -> Dictionary:
	step_to(end_tick())
	var rebuilt := SessionRecord.build(session, record["session_id"], record["created_at"])
	rebuilt["evaluation"] = Rubric.evaluate(rebuilt)
	var events_match := SessionIO.canonical(rebuilt["events"]) == SessionIO.canonical(record["events"])
	var evaluation_match := SessionIO.canonical(rebuilt["evaluation"]) == SessionIO.canonical(record["evaluation"])
	var difference := ""
	if not events_match:
		var a: Array = JSON.parse_string(JSON.stringify(rebuilt["events"]))
		var b: Array = JSON.parse_string(JSON.stringify(record["events"]))
		for i in mini(a.size(), b.size()):
			if JSON.stringify(a[i], "", true) != JSON.stringify(b[i], "", true):
				difference = "event %d differs: replay %s vs recorded %s" % [i + 1, JSON.stringify(a[i]), JSON.stringify(b[i])]
				break
		if difference.is_empty():
			difference = "event count differs: replay %d vs recorded %d" % [a.size(), b.size()]
	return {"identical": events_match and evaluation_match, "events_match": events_match,
		"evaluation_match": evaluation_match, "first_difference": difference, "warnings": warnings}
