extends RefCounted
## Pure mission rules: ordered checkpoints, then a held landing in the landing zone.
## No scene access, so it can be unit-tested and replayed deterministically.
## Methods that change progress return a message for the pilot ("" when nothing changed).

enum Status { READY, FLYING, COMPLETED, FAILED }

const TAKEOFF_ALTITUDE := 0.5 ## m; leaving the pad above this starts the mission clock
const LANDING_MAX_SPEED := 0.5 ## m/s; must be (nearly) stationary to count as landed
const LANDING_HOLD_SECONDS := 1.0

var checkpoint_count := 0
var next_checkpoint := 0
var status := Status.READY
var elapsed_seconds := 0.0
var failure_reason := ""

var _landed_seconds := 0.0
var _early_landing_reported := false


func _init(count: int = 0) -> void:
	checkpoint_count = maxi(count, 0)


func reset() -> void:
	next_checkpoint = 0
	status = Status.READY
	elapsed_seconds = 0.0
	failure_reason = ""
	_landed_seconds = 0.0
	_early_landing_reported = false


func is_finished() -> bool:
	return status == Status.COMPLETED or status == Status.FAILED


func all_checkpoints_passed() -> bool:
	return next_checkpoint >= checkpoint_count


## Called when the drone enters checkpoint `index` (0-based). Only the next one counts.
func pass_checkpoint(index: int) -> String:
	if is_finished() or index < 0 or index >= checkpoint_count:
		return ""
	if index < next_checkpoint:
		return ""
	if index > next_checkpoint:
		return "Wrong checkpoint: fly through checkpoint %d first" % (next_checkpoint + 1)
	next_checkpoint += 1
	if all_checkpoints_passed():
		return "Checkpoint %d of %d passed. Now land in the green zone" % [index + 1, checkpoint_count]
	return "Checkpoint %d of %d passed" % [index + 1, checkpoint_count]


## Advances the mission by one step from the drone's current state.
func update(altitude: float, on_ground: bool, in_landing_zone: bool, speed: float, delta: float) -> String:
	if is_finished() or delta <= 0.0 or not is_finite(delta):
		return ""
	if status == Status.READY:
		if altitude <= TAKEOFF_ALTITUDE:
			return ""
		status = Status.FLYING
	elapsed_seconds += delta

	var settled := on_ground and in_landing_zone and speed <= LANDING_MAX_SPEED
	if not settled:
		_landed_seconds = 0.0
		if not on_ground:
			_early_landing_reported = false
		return ""
	if not all_checkpoints_passed():
		if _early_landing_reported:
			return ""
		_early_landing_reported = true
		return "Landing zone reached, but %d checkpoint(s) remain" % (checkpoint_count - next_checkpoint)
	_landed_seconds += delta
	if _landed_seconds < LANDING_HOLD_SECONDS:
		return ""
	status = Status.COMPLETED
	return "Mission complete in %.1f s" % elapsed_seconds


func fail(reason: String) -> String:
	if is_finished():
		return ""
	status = Status.FAILED
	failure_reason = reason
	return "Mission failed: " + reason


func objective_text() -> String:
	match status:
		Status.COMPLETED:
			return "Mission complete. Press R to fly again"
		Status.FAILED:
			return "Mission failed. Press R to restart"
	if not all_checkpoints_passed():
		var prefix := "Take off (Space), then fly" if status == Status.READY else "Fly"
		return "%s through checkpoint %d of %d" % [prefix, next_checkpoint + 1, checkpoint_count]
	return "Land in the green landing zone and hold still"


func status_text(on_ground: bool, in_landing_zone: bool) -> String:
	match status:
		Status.READY:
			return "On launch pad"
		Status.COMPLETED:
			return "Landed: mission complete"
		Status.FAILED:
			return "Failed: " + failure_reason
	if not on_ground:
		return "Flying"
	return "Landed in landing zone" if in_landing_zone else "Landed outside landing zone"
