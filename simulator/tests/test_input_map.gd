extends "res://tests/test_case.gd"

## Stage 1 flight controls and the physical key each must be bound to.
const EXPECTED_KEYS := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"ascend": KEY_SPACE, "descend": KEY_C, "yaw_left": KEY_Q, "yaw_right": KEY_E,
	"toggle_view": KEY_V, "reset_mission": KEY_R, "pause": KEY_ESCAPE,
}


func test_flight_actions_are_bound_to_documented_keys() -> void:
	for action in EXPECTED_KEYS:
		assert_true(InputMap.has_action(action), "input action '%s' is defined" % action)
		if not InputMap.has_action(action):
			continue
		var keys := []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys.append(event.physical_keycode)
		assert_true(EXPECTED_KEYS[action] in keys, "'%s' is bound to %s" % [action, OS.get_keycode_string(EXPECTED_KEYS[action])])
