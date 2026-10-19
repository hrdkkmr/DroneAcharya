extends RefCounted
## One threat-observation exercise. Owns the ground-truth world and advances it at a
## fixed tick rate while running. Scene code only renders what this object exposes.

const Generator := preload("res://scripts/sim/scenario_generator.gd")
const ThreatWorld := preload("res://scripts/sim/threat_world.gd")

enum Status { BRIEFING, RUNNING, PAUSED, COMPLETED, ABORTED }

var config: Dictionary
var definition: Dictionary
var world: ThreatWorld
var status := Status.BRIEFING


func _init(scenario_config: Dictionary) -> void:
	config = scenario_config
	definition = Generator.build(config)
	world = ThreatWorld.new(definition)


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


func start() -> bool:
	if status != Status.BRIEFING:
		return false
	status = Status.RUNNING
	return true


func pause() -> bool:
	if status != Status.RUNNING:
		return false
	status = Status.PAUSED
	return true


func resume() -> bool:
	if status != Status.PAUSED:
		return false
	status = Status.RUNNING
	return true


func abort() -> bool:
	if status != Status.RUNNING and status != Status.PAUSED:
		return false
	status = Status.ABORTED
	return true


## Advances one tick when running. Returns false when nothing happened.
func step() -> bool:
	if status != Status.RUNNING:
		return false
	world.step()
	if world.is_finished():
		status = Status.COMPLETED
	return true
