extends RefCounted
## Pure mission rules: ordered checkpoints, then a held landing in the landing zone.
## No scene access, so it can be unit-tested and replayed deterministically.
## Methods that change progress return a message for the pilot ("" when nothing changed).
##
## Mission clock policy: the clock starts when the drone first climbs above
## TAKEOFF_ALTITUDE, advances only while update() is called (it is not called while
## the game is paused), and stops for good when the mission completes or fails.
## Optional limits (0 = none): `time_limit_s` and battery `endurance_s`; the
## airframe has 100 % integrity and simulated hits subtract from it.
## Every notable change is appended to `events` ({t, type, data}) for the report.

enum Status { READY, FLYING, COMPLETED, FAILED }

const TAKEOFF_ALTITUDE := 0.5 ## m; leaving the pad above this starts the mission clock
const LANDING_MAX_SPEED := 0.5 ## m/s; must be (nearly) stationary to count as landed
const LANDING_HOLD_SECONDS := 1.0
const TIME_WARNING_S := 30.0 ## warn when this much time (or less) remains
const BATTERY_WARNING := 0.2 ## warn at 20 % battery
const CLIMB_DRAIN_FACTOR := 1.5 ## battery use while climbing, relative to level flight

var checkpoint_count := 0
var next_checkpoint := 0
var status := Status.READY
var elapsed_seconds := 0.0
var failure_reason := ""
var time_limit_s := 0.0
var endurance_s := 0.0
var battery_used_s := 0.0
var integrity := 100.0
var events: Array = []
var checkpoint_times: Array = [] ## mission time at which each checkpoint was passed
var wrong_checkpoint_count := 0
var bump_count := 0
var hit_count := 0
var time_warning_given := false
var battery_warning_given := false

var _landed_seconds := 0.0
var _early_landing_reported := false


func _init(count: int = 0, limit_s: float = 0.0, endurance: float = 0.0) -> void:
	checkpoint_count = maxi(count, 0)
	time_limit_s = maxf(limit_s, 0.0)
	endurance_s = maxf(endurance, 0.0)


func reset() -> void:
	next_checkpoint = 0
	status = Status.READY
	elapsed_seconds = 0.0
	failure_reason = ""
	battery_used_s = 0.0
	integrity = 100.0
	events.clear()
	checkpoint_times.clear()
	wrong_checkpoint_count = 0
	bump_count = 0
	hit_count = 0
	time_warning_given = false
	battery_warning_given = false
	_landed_seconds = 0.0
	_early_landing_reported = false


func is_finished() -> bool:
	return status == Status.COMPLETED or status == Status.FAILED


func all_checkpoints_passed() -> bool:
	return next_checkpoint >= checkpoint_count


func has_time_limit() -> bool:
	return time_limit_s > 0.0


## Seconds left before the time limit (INF without a limit).
func time_remaining() -> float:
	return maxf(time_limit_s - elapsed_seconds, 0.0) if has_time_limit() else INF


func time_warning_active() -> bool:
	return has_time_limit() and not is_finished() and status == Status.FLYING and time_remaining() <= TIME_WARNING_S


## Remaining battery 0..1 (1 without an endurance limit).
func battery_fraction() -> float:
	return clampf(1.0 - battery_used_s / endurance_s, 0.0, 1.0) if endurance_s > 0.0 else 1.0


func battery_warning_active() -> bool:
	return endurance_s > 0.0 and not is_finished() and battery_fraction() <= BATTERY_WARNING


## Called when the drone enters checkpoint `index` (0-based). Only the next one counts.
func pass_checkpoint(index: int) -> String:
	if is_finished() or index < 0 or index >= checkpoint_count:
		return ""
	if index < next_checkpoint:
		return ""
	if index > next_checkpoint:
		wrong_checkpoint_count += 1
		log_event("wrong_checkpoint", {"entered": index + 1, "expected": next_checkpoint + 1})
		return "Wrong checkpoint: fly through checkpoint %d first" % (next_checkpoint + 1)
	next_checkpoint += 1
	checkpoint_times.append(snappedf(elapsed_seconds, 0.01))
	log_event("checkpoint", {"number": index + 1, "of": checkpoint_count})
	if all_checkpoints_passed():
		return "Checkpoint %d of %d passed. Now land in the green zone" % [index + 1, checkpoint_count]
	return "Checkpoint %d of %d passed" % [index + 1, checkpoint_count]


## Advances the mission by one step from the drone's current state.
func update(altitude: float, on_ground: bool, in_landing_zone: bool, speed: float, delta: float, vertical_speed := 0.0) -> String:
	if is_finished() or delta <= 0.0 or not is_finite(delta):
		return ""
	if status == Status.READY:
		if altitude <= TAKEOFF_ALTITUDE:
			return ""
		status = Status.FLYING
		log_event("takeoff", {})
	elapsed_seconds += delta
	if not on_ground:
		battery_used_s += delta * (CLIMB_DRAIN_FACTOR if vertical_speed > 0.5 else 1.0)
	var limits := _check_limits()
	if not limits.is_empty():
		return limits

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
		log_event("early_landing", {"remaining_checkpoints": checkpoint_count - next_checkpoint})
		return "Landing zone reached, but %d checkpoint(s) remain" % (checkpoint_count - next_checkpoint)
	_landed_seconds += delta
	if _landed_seconds < LANDING_HOLD_SECONDS:
		return ""
	status = Status.COMPLETED
	log_event("completed", {"time_s": snappedf(elapsed_seconds, 0.01)})
	return "Mission complete in %.1f s" % elapsed_seconds


## Time-limit and battery checks: warnings once, then failure.
func _check_limits() -> String:
	if has_time_limit() and elapsed_seconds >= time_limit_s:
		return fail("time limit reached (%s)" % clock(time_limit_s))
	if endurance_s > 0.0 and battery_fraction() <= 0.0:
		return fail("battery depleted")
	if time_warning_active() and not time_warning_given:
		time_warning_given = true
		log_event("time_warning", {"remaining_s": snappedf(time_remaining(), 0.1)})
		return "%d seconds left" % ceili(time_remaining())
	if battery_warning_active() and not battery_warning_given:
		battery_warning_given = true
		log_event("battery_warning", {"battery": snappedf(battery_fraction(), 0.01)})
		return "Battery low: %d%%. Head for the landing zone" % roundi(battery_fraction() * 100.0)
	return ""


## A minor collision (below crash speed): counted, not fatal.
func record_bump(obstacle: String, impact_speed: float) -> String:
	if is_finished():
		return ""
	bump_count += 1
	log_event("bump", {"obstacle": obstacle, "speed": snappedf(impact_speed, 0.1)})
	return "Minor collision with %s" % obstacle


## A simulated hit from a training hazard. Integrity at 0 fails the mission.
func record_hit(source: String, damage: float) -> String:
	if is_finished():
		return ""
	hit_count += 1
	integrity = maxf(integrity - damage, 0.0)
	log_event("hit", {"source": source, "integrity": snappedf(integrity, 0.1)})
	if integrity <= 0.0:
		return fail("airframe integrity lost after %d simulated hits" % hit_count)
	return "Simulated hit by %s. Integrity %d%%" % [source, roundi(integrity)]


func fail(reason: String) -> String:
	if is_finished():
		return ""
	status = Status.FAILED
	failure_reason = reason
	log_event("failed", {"reason": reason})
	return "Mission failed: " + reason


func log_event(type: String, data: Dictionary) -> void:
	events.append({"t": snappedf(elapsed_seconds, 0.01), "type": type, "data": data})


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


static func clock(seconds: float) -> String:
	var total := maxi(int(ceil(seconds - 0.0001)), 0)
	return "%02d:%02d" % [total / 60, total % 60]
