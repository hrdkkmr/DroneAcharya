extends RefCounted
## One threat-observation exercise: ground-truth world → synthetic sensors → tracker →
## decision support, advanced at a fixed tick rate while running, plus the trainee's
## actions. Scene code only renders it and forwards input.
##
## Two separate records are kept:
##  * `events`: what the trainee and the decision models may know (sensor status,
##    track lifecycle, model outputs, trainee actions).
##  * truth channel (`truth_events`, `availability`, `sensor.truth_links`): ground
##    truth for assessment, labelling and replay only.

const Generator := preload("res://scripts/sim/scenario_generator.gd")
const ThreatWorld := preload("res://scripts/sim/threat_world.gd")
const SensorModel := preload("res://scripts/sim/sensor_model.gd")
const Tracker := preload("res://scripts/sim/tracker.gd")
const Features := preload("res://scripts/ai/features.gd")
const DecisionSupport := preload("res://scripts/ai/decision_support.gd")
const Vocabulary := preload("res://scripts/ai/vocabulary.gd")

enum Status { BRIEFING, RUNNING, PAUSED, COMPLETED, ABORTED }

const MAX_CLASSIFICATIONS_PER_TRACK := 3 ## further re-classifications count as action spam

var config: Dictionary
var definition: Dictionary
var world: ThreatWorld
var sensor: SensorModel
var tracker: Tracker
var decisions: DecisionSupport
var status := Status.BRIEFING
var events: Array = []
var truth_events: Array = []
var availability: Array = [] ## per second: {t, active, id, zone} actor-id lists (ground truth)
var observations: Array = [] ## every delivered observation, in delivery order
## Trainee state per track id: {acknowledged_t, category, confidence, classified_t,
## classifications, response, responded_t}
var trainee := {}
var spam_count := 0
## When false, decision support and availability sampling are skipped (dataset
## generation does its own sampling and does not need them).
var run_decisions := true

var _degraded := false
var _active := {}


func _init(scenario_config: Dictionary, ml_classifier: RefCounted = null) -> void:
	config = scenario_config
	definition = Generator.build(config)
	world = ThreatWorld.new(definition)
	sensor = SensorModel.new(definition)
	tracker = Tracker.new(definition["observer_position"], config["sensor"])
	decisions = DecisionSupport.new(Features.context_from(definition), ml_classifier)


func tick() -> int:
	return world.tick


func tick_seconds() -> float:
	return world.dt


func time_s() -> float:
	return world.time_s()


func remaining_s() -> float:
	return maxf(float(config["duration_s"]) - time_s(), 0.0)


func is_finished() -> bool:
	return status == Status.COMPLETED or status == Status.ABORTED


func is_degraded() -> bool:
	return _degraded


func start() -> bool:
	if status != Status.BRIEFING:
		return false
	status = Status.RUNNING
	log_event("started", {"scenario_id": config["id"], "seed": config["seed"], "ml_active": decisions.ml_active()})
	return true


func pause() -> bool:
	if status != Status.RUNNING:
		return false
	status = Status.PAUSED
	log_event("paused", {})
	return true


func resume() -> bool:
	if status != Status.PAUSED:
		return false
	status = Status.RUNNING
	log_event("resumed", {})
	return true


func abort() -> bool:
	if status != Status.RUNNING and status != Status.PAUSED:
		return false
	status = Status.ABORTED
	log_event("finished", {"outcome": "aborted"})
	return true


## Advances one tick when running. Returns false when nothing happened.
func step() -> bool:
	if status != Status.RUNNING:
		return false
	world.step()
	var t := time_s()
	_record_truth_changes()
	var degraded := sensor.degradation_at(t) > 0.0
	if degraded != _degraded:
		_degraded = degraded
		log_event("sensor_degraded" if degraded else "sensor_restored", {"severity": sensor.degradation_at(t)})
	var delivered := sensor.update(world.tick, world.physical_snapshot())
	observations.append_array(delivered)
	tracker.process(delivered, t)
	for e in tracker.take_events():
		log_event(e["type"], {"track_id": e["track_id"]})
	if run_decisions and world.tick % int(definition["tick_rate"]) == 0:
		_sample_availability(t)
		for change in decisions.update(tracker.confirmed_tracks(), t):
			log_event("model_output", change)
	if world.is_finished():
		status = Status.COMPLETED
		log_event("finished", {"outcome": "completed"})
	return true


func log_event(type: String, data: Dictionary) -> Dictionary:
	var event := {"seq": events.size() + 1, "tick": world.tick, "t": snappedf(time_s(), 0.001), "type": type, "data": data}
	events.append(event)
	return event


# --- Trainee actions -------------------------------------------------------------
# Each returns {ok: bool, message: String} and is logged (rejected actions too).

func acknowledge(track_id: String) -> Dictionary:
	var check := _check_track(track_id, "acknowledge")
	if not check["ok"]:
		return check
	var state := _state(track_id)
	if state["acknowledged_t"] >= 0.0:
		return _reject("acknowledge", track_id, "%s is already acknowledged." % track_id, true)
	var members := _targets(track_id)
	for id in members:
		if _state(id)["acknowledged_t"] < 0.0:
			_state(id)["acknowledged_t"] = time_s()
	return _accept("acknowledge", track_id, {"members": members}, "%s acknowledged." % track_id)


func classify(track_id: String, category: String, confidence: int) -> Dictionary:
	var args := {"category": category, "confidence": confidence}
	var check := _check_track(track_id, "classify", args)
	if not check["ok"]:
		return check
	if not category in Vocabulary.CATEGORIES:
		return _reject("classify", track_id, "Unknown category '%s'." % category, false, args)
	if confidence < 0 or confidence > 100:
		return _reject("classify", track_id, "Confidence must be 0-100.", false, args)
	var state := _state(track_id)
	if state["acknowledged_t"] < 0.0:
		return _reject("classify", track_id, "Acknowledge %s first (F)." % track_id, false, args)
	if not String(state["response"]).is_empty():
		return _reject("classify", track_id, "%s already has a final response." % track_id, true, args)
	state["classifications"] += 1
	var spam: bool = state["classifications"] > MAX_CLASSIFICATIONS_PER_TRACK
	if spam:
		spam_count += 1
	var members := _targets(track_id) if category == "swarm" else [track_id]
	for id in members:
		var s := _state(id)
		if s["acknowledged_t"] < 0.0:
			s["acknowledged_t"] = time_s()
		s["category"] = category
		s["confidence"] = confidence
		s["classified_t"] = time_s()
	return _accept("classify", track_id, {"category": category, "confidence": confidence, "members": members, "spam": spam},
		"%s classified as %s (%d%%)." % [track_id, Vocabulary.CATEGORY_LABELS[category], confidence])


func respond(track_id: String, response: String) -> Dictionary:
	var args := {"response": response}
	var check := _check_track(track_id, "respond", args)
	if not check["ok"]:
		return check
	if not response in Vocabulary.RESPONSES:
		return _reject("respond", track_id, "Unknown response '%s'." % response, false, args)
	var state := _state(track_id)
	if String(state["category"]).is_empty():
		return _reject("respond", track_id, "Classify %s before choosing a response." % track_id, false, args)
	if not String(state["response"]).is_empty():
		return _reject("respond", track_id, "%s already has a final response." % track_id, true, args)
	var members := _targets(track_id) if state["category"] == "swarm" else [track_id]
	for id in members:
		var s := _state(id)
		s["response"] = response
		s["responded_t"] = time_s()
	var model: Dictionary = decisions.recommendation_for(track_id).get("policy", {})
	var model_summary := {}
	if not model.is_empty():
		model_summary = {"response": model["response"], "reason_code": model["reason_code"], "based_on": model["based_on"]}
	return _accept("respond", track_id, {"response": response, "members": members, "model_recommendation": model_summary},
		"%s: %s." % [track_id, Vocabulary.RESPONSE_LABELS[response]])


func trainee_state(track_id: String) -> Dictionary:
	return trainee.get(track_id, {})


func _check_track(track_id: String, kind: String, args := {}) -> Dictionary:
	if status != Status.RUNNING:
		return {"ok": false, "message": "Resume the exercise first."}
	var track: Dictionary = tracker.tracks.get(track_id, {})
	if track.is_empty() or track["status"] == "tentative":
		return _reject(kind, track_id, "No confirmed track '%s'." % track_id, true, args)
	return {"ok": true}


## Tracks an action applies to: the whole observed swarm group when grouping is on.
func _targets(track_id: String) -> Array:
	var group: String = tracker.tracks[track_id].get("swarm_group", "")
	if not config.get("group_swarms", true) or group.is_empty() or not tracker.groups.has(group):
		return [track_id]
	return tracker.groups[group]["members"].duplicate()


func _state(track_id: String) -> Dictionary:
	if not trainee.has(track_id):
		trainee[track_id] = {"acknowledged_t": -1.0, "category": "", "confidence": 0, "classified_t": -1.0,
			"classifications": 0, "response": "", "responded_t": -1.0}
	return trainee[track_id]


func _accept(kind: String, track_id: String, data: Dictionary, message: String) -> Dictionary:
	var payload := {"kind": kind, "track_id": track_id, "valid": true}
	payload.merge(data)
	log_event("action", payload)
	return {"ok": true, "message": message}


func _reject(kind: String, track_id: String, message: String, spam: bool, args := {}) -> Dictionary:
	if spam:
		spam_count += 1
	var data := {"kind": kind, "track_id": track_id, "valid": false, "spam": spam, "message": message}
	data.merge(args)
	log_event("action", data)
	return {"ok": false, "message": message}


# --- Ground-truth channel ---------------------------------------------------------

func _sample_availability(t: float) -> void:
	var sample := {"t": snappedf(t, 0.001), "active": [], "id": [], "zone": []}
	var zone_radius: float = definition["protected_zone"]["radius_m"]
	for target in world.physical_snapshot():
		var id: String = target["actor_id"]
		sample["active"].append(id)
		if sensor.identification_available(target):
			sample["id"].append(id)
		var p: Vector3 = target["position"]
		if Vector2(p.x, p.z).length() <= zone_radius:
			sample["zone"].append(id)
	availability.append(sample)


func _record_truth_changes() -> void:
	for record in world.actors:
		var id: String = record["id"]
		if record["active"] and not _active.has(id):
			_active[id] = true
			truth_events.append({"tick": world.tick, "type": "spawned", "actor_id": id})
		elif not record["active"] and _active.has(id):
			_active.erase(id)
			truth_events.append({"tick": world.tick, "type": "exited", "actor_id": id})
