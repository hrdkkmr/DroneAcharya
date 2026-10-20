extends "res://tests/test_case.gd"

## Stage 1 flight controls and the physical key each must be bound to.
const EXPECTED_KEYS := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"ascend": KEY_SPACE, "descend": KEY_C, "yaw_left": KEY_Q, "yaw_right": KEY_E,
	"toggle_view": KEY_V, "reset_mission": KEY_R, "pause": KEY_ESCAPE,
	"mark": KEY_F, "classify": KEY_K, "report": KEY_ENTER, "cycle_track": KEY_TAB, "jump": KEY_J,
	"option_prev": KEY_UP, "option_next": KEY_DOWN, "decision_back": KEY_BACKSPACE,
	"confidence_low": KEY_1, "confidence_medium": KEY_2, "confidence_high": KEY_3, "zoom_in": KEY_EQUAL, "zoom_out": KEY_MINUS,
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


func test_no_physical_key_is_bound_to_two_actions() -> void:
	var owner := {}
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key: int = event.physical_keycode
				assert_true(not owner.has(key), "%s is bound to both '%s' and '%s'" % [OS.get_keycode_string(key), owner.get(key, ""), action])
				owner[key] = action
