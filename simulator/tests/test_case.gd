extends RefCounted
## Base class for tests. Extend with `extends "res://tests/test_case.gd"` and add
## methods named `test_*`. Assertion helpers record failures; they never abort.

const PRESSABLE_ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right", "ascend", "descend", "yaw_left", "yaw_right",
]

var failures: Array[String] = []
## Set by the runner. Use it to add scenes to `tree.root` and to wait for frames.
var tree: SceneTree

var _added_nodes: Array[Node] = []


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, var_to_str(expected), var_to_str(actual)])


func assert_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if not is_finite(actual) or absf(actual - expected) > tolerance:
		failures.append("%s (expected %.4f ± %.4f, got %.4f)" % [message, expected, tolerance, actual])


## Instantiates a scene under the root; it is freed automatically after the test.
func add_scene(path: String) -> Node:
	var packed: PackedScene = load(path)
	if packed == null:
		failures.append("could not load scene " + path)
		return null
	var node := packed.instantiate()
	tree.root.add_child(node)
	_added_nodes.append(node)
	return node


func add_node(node: Node) -> Node:
	tree.root.add_child(node)
	_added_nodes.append(node)
	return node


func wait_physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


## Called by the runner after every test: releases keys, unpauses, frees added nodes.
func cleanup() -> void:
	for action in PRESSABLE_ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)
	if tree == null:
		return
	tree.paused = false
	if tree.current_scene != null:
		tree.unload_current_scene()
	for node in _added_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_added_nodes.clear()
	await tree.process_frame
