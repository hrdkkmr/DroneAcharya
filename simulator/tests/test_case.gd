extends RefCounted
## Base class for tests. Extend with `extends "res://tests/test_case.gd"` and add
## methods named `test_*`. Assertion helpers record failures; they never abort.

var failures: Array[String] = []


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, var_to_str(expected), var_to_str(actual)])
