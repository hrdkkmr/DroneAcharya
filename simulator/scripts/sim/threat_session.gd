extends RefCounted
## One threat-observation exercise: ground-truth world → synthetic sensors → tracker,
## advanced at a fixed tick rate while running. Scene code only renders it.
##
## Two separate records are kept:
##  * `events`: what the trainee and decision models may know (sensor status, track
##    lifecycle, later trainee actions and model outputs).
##  * `truth_events`: ground truth (spawns, exits) for evaluation and replay only.

const Generator := preload("res://scripts/sim/scenario_generator.gd")
const ThreatWorld := preload("res://scripts/sim/threat_world.gd")
const SensorModel := preload("res://scripts/sim/sensor_model.gd")
const Tracker := preload("res://scripts/sim/tracker.gd")

enum Status { BRIEFING, RUNNING, PAUSED, COMPLETED, ABORTED }

var config: Dictionary
var definition: Dictionary
var world: ThreatWorld
var sensor: SensorModel
var tracker: Tracker
var status := Status.BRIEFING
var events: Array = []
var truth_events: Array = []
var observations: Array = [] ## every delivered observation, in delivery order

var _degraded := false
var _active := {}


func _init(scenario_config: Dictionary) -> void:
	config = scenario_config
	definition = Generator.build(config)
	world = ThreatWorld.new(definition)
	sensor = SensorModel.new(definition)
	tracker = Tracker.new(definition["observer_position"], config["sensor"])


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
	log_event("started", {"scenario_id": config["id"], "seed": config["seed"]})
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
	if world.is_finished():
		status = Status.COMPLETED
		log_event("finished", {"outcome": "completed"})
	return true


func log_event(type: String, data: Dictionary) -> Dictionary:
	var event := {"seq": events.size() + 1, "tick": world.tick, "t": snappedf(time_s(), 0.001), "type": type, "data": data}
	events.append(event)
	return event


func _record_truth_changes() -> void:
	for record in world.actors:
		var id: String = record["id"]
		if record["active"] and not _active.has(id):
			_active[id] = true
			truth_events.append({"tick": world.tick, "type": "spawned", "actor_id": id})
		elif not record["active"] and _active.has(id):
			_active.erase(id)
			truth_events.append({"tick": world.tick, "type": "exited", "actor_id": id})
