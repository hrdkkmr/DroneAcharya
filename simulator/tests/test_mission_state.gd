extends "res://tests/test_case.gd"
## Pure mission rules, including invalid inputs.

const MissionState := preload("res://scripts/mission/mission_state.gd")
const DT := 1.0 / 60.0


func _hold_landed(state: MissionState, seconds: float) -> String:
	var last := ""
	for i in int(round(seconds / DT)):
		var text := state.update(0.0, true, true, 0.0, DT)
		if not text.is_empty():
			last = text
	return last


func test_starts_ready_and_takes_off_above_threshold() -> void:
	var state := MissionState.new(3)
	assert_eq(state.status, MissionState.Status.READY, "initial status")
	assert_true(state.objective_text().begins_with("Take off"), "initial objective")
	state.update(0.2, true, false, 0.0, DT)
	assert_eq(state.status, MissionState.Status.READY, "still on pad below takeoff altitude")
	assert_eq(state.elapsed_seconds, 0.0, "clock not running before takeoff")
	state.update(1.0, false, false, 2.0, DT)
	assert_eq(state.status, MissionState.Status.FLYING, "flying after takeoff")
	assert_near(state.elapsed_seconds, DT, 1e-9, "clock started")


func test_checkpoints_must_be_flown_in_order() -> void:
	var state := MissionState.new(3)
	assert_true(state.pass_checkpoint(1).begins_with("Wrong checkpoint"), "skipping ahead is rejected")
	assert_eq(state.next_checkpoint, 0, "no progress when skipping")
	assert_eq(state.pass_checkpoint(0), "Checkpoint 1 of 3 passed", "first checkpoint")
	assert_eq(state.pass_checkpoint(0), "", "re-entering a passed checkpoint is silent")
	state.pass_checkpoint(1)
	assert_true(state.pass_checkpoint(2).ends_with("land in the green zone"), "last checkpoint prompts landing")
	assert_true(state.all_checkpoints_passed(), "all passed")


func test_out_of_range_checkpoints_are_ignored() -> void:
	var state := MissionState.new(2)
	assert_eq(state.pass_checkpoint(-1), "", "negative index ignored")
	assert_eq(state.pass_checkpoint(99), "", "too-large index ignored")
	assert_eq(state.next_checkpoint, 0, "no progress")


func test_landing_completes_only_after_all_checkpoints_and_a_held_touchdown() -> void:
	var state := MissionState.new(2)
	state.update(5.0, false, false, 3.0, DT)
	assert_true(_hold_landed(state, 0.1).begins_with("Landing zone reached, but 2"), "early landing explained")
	assert_eq(_hold_landed(state, 0.5), "", "early-landing message not repeated")
	assert_eq(state.status, MissionState.Status.FLYING, "not complete without checkpoints")
	state.pass_checkpoint(0)
	state.pass_checkpoint(1)
	assert_eq(_hold_landed(state, 0.5), "", "touchdown must be held")
	state.update(0.0, true, true, 2.0, DT)  # sliding too fast resets the hold
	_hold_landed(state, 0.9)
	assert_eq(state.status, MissionState.Status.FLYING, "hold restarted after moving")
	assert_true(_hold_landed(state, 0.2).begins_with("Mission complete in"), "completion message")
	assert_eq(state.status, MissionState.Status.COMPLETED, "completed")


func test_landing_outside_zone_does_not_complete() -> void:
	var state := MissionState.new(0)
	state.update(5.0, false, false, 0.0, DT)
	for i in 120:
		state.update(0.0, true, false, 0.0, DT)
	assert_eq(state.status, MissionState.Status.FLYING, "outside zone")
	assert_eq(state.status_text(true, false), "Landed outside landing zone", "status explains")


func test_finished_mission_ignores_further_events() -> void:
	var state := MissionState.new(1)
	state.update(5.0, false, false, 0.0, DT)
	assert_eq(state.fail("collided with PillarA at 5.0 m/s"), "Mission failed: collided with PillarA at 5.0 m/s", "failure message")
	assert_eq(state.fail("again"), "", "second failure ignored")
	assert_eq(state.pass_checkpoint(0), "", "checkpoint ignored after failure")
	var elapsed := state.elapsed_seconds
	assert_eq(_hold_landed(state, 2.0), "", "landing ignored after failure")
	assert_eq(state.elapsed_seconds, elapsed, "clock stopped after failure")
	assert_eq(state.failure_reason, "collided with PillarA at 5.0 m/s", "first reason kept")
	assert_eq(state.objective_text(), "Mission failed. Press R to restart", "objective")


func test_reset_restores_initial_state() -> void:
	var state := MissionState.new(2)
	state.update(5.0, false, false, 0.0, 1.0)
	state.pass_checkpoint(0)
	state.fail("left the training area")
	state.reset()
	assert_eq(state.status, MissionState.Status.READY, "status")
	assert_eq(state.next_checkpoint, 0, "checkpoint")
	assert_eq(state.elapsed_seconds, 0.0, "clock")
	assert_eq(state.failure_reason, "", "reason")
	assert_eq(state.checkpoint_count, 2, "count kept")


func test_invalid_configuration_and_time_steps_are_safe() -> void:
	var empty := MissionState.new(-5)
	assert_eq(empty.checkpoint_count, 0, "negative count clamps to 0")
	assert_true(empty.objective_text().begins_with("Land"), "zero-checkpoint mission asks to land")
	var state := MissionState.new(2)
	state.update(5.0, false, false, 0.0, DT)
	var elapsed := state.elapsed_seconds
	for delta in [0.0, -1.0, NAN, INF]:
		assert_eq(state.update(0.0, true, true, 0.0, delta), "", "invalid delta returns no message")
	assert_eq(state.elapsed_seconds, elapsed, "clock unchanged by invalid delta")
