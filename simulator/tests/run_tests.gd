extends SceneTree
## Headless test runner. Usage (from the workspace root):
##   Godot_v4.7.2-stable_win64_console.exe --headless --path simulator --script res://tests/run_tests.gd
## Optional: append `-- --dir=res://some/folder` to run tests from another folder.
## Runs every `test_*` method in every `test_*.gd` file of the folder. A test fails
## if an assertion fails or if any engine/script error is logged while it runs.
## Tests may `await` frames (see test_case.gd); each one gets `tree` set to this SceneTree.
## Exit code: 0 when all tests pass, 1 otherwise (including when no tests are found).

const DEFAULT_DIR := "res://tests"


class ErrorCapture extends Logger:
	var _mutex := Mutex.new()
	var _errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text := rationale if not rationale.is_empty() else code
		_mutex.lock()
		_errors.append("%s (%s:%d in %s)" % [text, file, line, function])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var result := _errors.duplicate()
		_errors.clear()
		_mutex.unlock()
		return result


func _initialize() -> void:
	var capture := ErrorCapture.new()
	OS.add_logger(capture)
	var dir_path := _requested_dir()
	var files := _test_files(dir_path)
	var passed := 0
	var failed := 0
	print("Running tests in %s" % dir_path)
	# Nodes added to the root are not inside the tree until the first frame has run.
	await process_frame
	capture.take()
	for path in files:
		var script: GDScript = load(path)
		var load_errors := capture.take()
		if script == null or not script.can_instantiate() or not load_errors.is_empty():
			failed += 1
			print("FAIL %s: could not load test file %s" % [path, "; ".join(load_errors)])
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var test: Object = script.new()
			test.tree = self
			await test.call(name)
			await test.cleanup()
			var problems: Array[String] = []
			problems.append_array(test.failures)
			for error in capture.take():
				problems.append("engine error: " + error)
			if problems.is_empty():
				passed += 1
				print("PASS %s::%s" % [path.get_file(), name])
			else:
				failed += 1
				print("FAIL %s::%s" % [path.get_file(), name])
				for problem in problems:
					print("     - " + problem)
	OS.remove_logger(capture)
	if passed + failed == 0:
		print("No tests found in %s" % dir_path)
		quit(1)
		return
	print("%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _requested_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			return arg.trim_prefix("--dir=")
	return DEFAULT_DIR


func _test_files(dir_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	for file in DirAccess.get_files_at(dir_path):
		if file.begins_with("test_") and file.ends_with(".gd"):
			result.append(dir_path.path_join(file))
	result.sort()
	return result
