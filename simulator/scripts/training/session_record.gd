extends RefCounted
## Builds a JSON-compatible record of a finished (or aborted) exercise. The record
## separates trainee-visible data (events, observations, tracks) from ground truth
## (`truth`) so evaluation and replay can use truth while the rest stays clean.

const FORMAT := "droneacharya-session"
const FORMAT_VERSION := 1
const Features := preload("res://scripts/ai/features.gd")
const RuleEngine := preload("res://scripts/ai/rule_engine.gd")
const DecisionPolicy := preload("res://scripts/ai/decision_policy.gd")
const Generator := preload("res://scripts/sim/scenario_generator.gd")

const STATUS_NAMES := ["briefing", "running", "paused", "completed", "aborted"]


static func build(session: RefCounted, session_id: String, created_at: String) -> Dictionary:
	var definition: Dictionary = session.definition
	var tracks := []
	for track in session.tracker.retired + session.tracker.tracks.values():
		tracks.append({
			"id": track["id"], "status": track["status"], "created_t": track["created_t"],
			"confirmed_t": track["confirmed_t"], "retired_t": track.get("retired_t", -1.0),
			"hits": track["hits"], "obs_ids": track["obs_ids"].duplicate(),
		})
	tracks.sort_custom(func(a, b): return a["id"] < b["id"])
	var actors := []
	for actor in definition["actors"]:
		actors.append({
			"id": actor["id"], "profile": actor["profile"], "behavior": actor["behavior"],
			"truth_category": actor["truth_category"], "significant": actor["significant"],
			"group_id": actor["group_id"], "spawn_tick": actor["spawn_tick"],
		})
	var classifier = session.decisions.classifier
	return {
		"format": FORMAT, "format_version": FORMAT_VERSION,
		"session_id": session_id, "created_at": created_at,
		"scenario": session.config.duplicate(true),
		"generator": Generator.GENERATOR_VERSION, "tick_rate": definition["tick_rate"],
		"status": STATUS_NAMES[session.status], "end_tick": session.tick(), "end_t": snappedf(session.time_s(), 0.001),
		"models": {
			"features": Features.VERSION, "rules": RuleEngine.VERSION, "policy": DecisionPolicy.VERSION,
			"ml": classifier.info() if classifier != null else {"loaded": false},
		},
		"spam_count": session.spam_count,
		"events": jsonify(session.events),
		"observations": compact_observations(session.observations),
		"tracks": tracks,
		"truth": {
			"actors": actors,
			"protected_zone_radius_m": definition["protected_zone"]["radius_m"],
			"links": session.sensor.truth_links.duplicate(),
			"events": session.truth_events.duplicate(true),
			"availability": session.availability.duplicate(true),
		},
	}


## Observations as compact rows (see docs/DRONEACHARYA_SESSION_SCHEMA.md).
const OBSERVATION_COLUMNS := ["id", "sensor", "t", "t_delivered", "bearing_deg", "elevation_deg", "range_m",
	"quality", "degraded", "id_reply", "id_quality", "apparent_size_m", "flap_detected"]


static func compact_observations(observations: Array) -> Dictionary:
	var rows := []
	for o in observations:
		rows.append([o["id"], o["sensor"], snappedf(o["t"], 0.001), snappedf(o["t_delivered"], 0.001),
			snappedf(o["bearing_deg"], 0.001), snappedf(o["elevation_deg"], 0.001), snappedf(o["range_m"], 0.1),
			snappedf(o["quality"], 0.001), o["degraded"], o["id_reply"], o["id_quality"],
			snappedf(o["apparent_size_m"], 0.001), o["flap_detected"]])
	return {"columns": OBSERVATION_COLUMNS, "rows": rows}


## Converts Vector3 and nested containers into JSON-friendly values.
static func jsonify(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR3:
			return [snappedf(value.x, 0.01), snappedf(value.y, 0.01), snappedf(value.z, 0.01)]
		TYPE_DICTIONARY:
			var out := {}
			for key in value:
				out[key] = jsonify(value[key])
			return out
		TYPE_ARRAY:
			var arr := []
			for item in value:
				arr.append(jsonify(item))
			return arr
		TYPE_FLOAT:
			return snappedf(value, 0.0001)
	return value
