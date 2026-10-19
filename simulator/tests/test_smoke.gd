extends "res://tests/test_case.gd"

const REQUIRED_ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right", "jump",
	"toggle_view", "mark", "classify", "report", "pause",
]


func test_main_scene_shows_title() -> void:
	var path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	assert_eq(path, "res://scenes/main.tscn", "main scene setting")
	var packed: PackedScene = load(path)
	assert_true(packed != null, "main scene loads")
	if packed == null:
		return
	var main: Node = packed.instantiate()
	var title: Label = main.get_node_or_null("Title")
	assert_true(title != null, "main scene has a Title label")
	if title != null:
		assert_eq(title.text, "DroneAcharya — synthetic training only", "title text")
	main.free()


func test_required_input_actions_exist() -> void:
	for action in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "input action '%s' is defined" % action)
		if InputMap.has_action(action):
			assert_true(not InputMap.action_get_events(action).is_empty(), "input action '%s' has a binding" % action)
