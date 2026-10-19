extends Control
## Training history and after-action review. Lists validated session files (invalid
## files are listed with reasons and never modified), shows the review for the
## selected session, verifies or plays its deterministic replay, and exports or
## imports versioned JSON.

const AppState := preload("res://scripts/app/app_state.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const SessionIO := preload("res://scripts/training/session_io.gd")
const Replay := preload("res://scripts/training/replay.gd")
const Aar := preload("res://scripts/training/aar.gd")
const MlClassifier := preload("res://scripts/ai/ml_classifier.gd")

var sessions: Array = []
var invalid: Array = []
var selected: Dictionary = {}
var list: ItemList
var report_label: RichTextLabel
var status_label: Label
var invalid_label: Label
var import_dialog: FileDialog
var sessions_dir := AppState.sessions_dir


func _ready() -> void:
	UiKit.background(self)
	var root := UiKit.vbox(10)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 32)
	add_child(root)
	root.add_child(UiKit.label("Training history & after-action review", 30))
	var body := UiKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := UiKit.vbox(8)
	left.custom_minimum_size = Vector2(430, 0)
	body.add_child(left)
	left.add_child(UiKit.heading("Saved sessions"))
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_font_size_override("font_size", 15)
	list.item_selected.connect(_on_selected)
	left.add_child(list)
	invalid_label = UiKit.label("", 14, UiKit.WARN, true)
	left.add_child(invalid_label)
	var file_buttons := UiKit.hbox(8)
	file_buttons.add_child(UiKit.button("Import…", _open_import, 120))
	file_buttons.add_child(UiKit.button("Export all", export_all, 130))
	file_buttons.add_child(UiKit.button("Open folder", func(): OS.shell_open(ProjectSettings.globalize_path(sessions_dir)), 150))
	left.add_child(file_buttons)

	var right := UiKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	report_label = RichTextLabel.new()
	report_label.bbcode_enabled = true
	report_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_label.add_theme_font_size_override("normal_font_size", 15)
	report_label.add_theme_font_size_override("bold_font_size", 15)
	right.add_child(report_label)
	var actions := UiKit.hbox(8)
	actions.add_child(UiKit.button("Replay in 3D", replay_in_3d, 170))
	actions.add_child(UiKit.button("Verify replay", verify_replay, 170))
	actions.add_child(UiKit.button("Export this session", export_selected, 210))
	actions.add_child(UiKit.button("Back to menu", AppState.goto.bind(get_tree(), "menu"), 170))
	right.add_child(actions)
	status_label = UiKit.label("", 15, UiKit.ACCENT, true)
	right.add_child(status_label)

	import_dialog = FileDialog.new()
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.filters = PackedStringArray(["*.json ; DroneAcharya history or session"])
	import_dialog.use_native_dialog = true
	import_dialog.file_selected.connect(import_file)
	add_child(import_dialog)
	reload()


func reload() -> void:
	var history := SessionIO.list_history(sessions_dir)
	sessions = history["sessions"]
	invalid = history["invalid"]
	list.clear()
	for record in sessions:
		var index := list.add_item("%s · %.1f · %s" % [String(record["created_at"]).substr(0, 16).replace("T", " "), record["evaluation"]["score"], record["scenario"]["title"]])
		list.set_item_tooltip(index, "%s · %s · seed %d · %s" % [record["session_id"], record["status"], record["scenario"]["seed"], record["scenario"]["title"]])
	invalid_label.text = "" if invalid.is_empty() else "%d invalid file(s) not loaded (left untouched): %s" % [invalid.size(), "; ".join(PackedStringArray(invalid.map(func(i): return "%s — %s" % [i["file"], i["reason"]])))]
	var wanted: String = AppState.review_session.get("session_id", "")
	var index := 0
	for i in sessions.size():
		if sessions[i]["session_id"] == wanted:
			index = i
	if sessions.is_empty():
		selected = {}
		report_label.text = "No saved sessions yet. Finish a threat-observation exercise to create one."
	else:
		list.select(index)
		_on_selected(index)


func _on_selected(index: int) -> void:
	selected = sessions[index]
	AppState.review_session = selected
	report_label.text = Aar.report(selected)
	status_label.text = ""


func verify_replay() -> Dictionary:
	if selected.is_empty():
		return {}
	var result := Replay.new(selected, MlClassifier.shared()).verify()
	if result["identical"]:
		status_label.text = "Replay verified: re-simulating seed %d with the recorded actions reproduces every event and the score exactly." % selected["scenario"]["seed"]
	else:
		status_label.text = "Replay differs: %s %s" % [result["first_difference"], " ".join(result["warnings"])]
	return result


func replay_in_3d() -> void:
	if selected.is_empty():
		return
	AppState.review_session = selected
	AppState.replay_requested = true
	AppState.selected_config = selected["scenario"]
	AppState.goto(get_tree(), "observation")


func export_selected() -> Dictionary:
	if selected.is_empty():
		return {}
	return _export([selected], "droneacharya-session-%s.json" % selected["session_id"])


func export_all() -> Dictionary:
	return _export(sessions, "droneacharya-history-%s.json" % Time.get_datetime_string_from_system(true).replace(":", "-"))


func _export(records: Array, file_name: String) -> Dictionary:
	var result := SessionIO.export_bundle(records, SessionIO.EXPORT_DIR.path_join(file_name))
	status_label.text = "Exported %d session(s) to %s" % [result["count"], ProjectSettings.globalize_path(result["path"])] if result["ok"] else "Export failed: " + result["error"]
	return result


func _open_import() -> void:
	import_dialog.popup_centered(Vector2i(900, 600))


func import_file(path: String) -> Dictionary:
	var result := SessionIO.import_bundle(path, sessions_dir)
	status_label.text = ("Imported %d new session(s); %d already present." % [result["added"], result["skipped"]]) if result["ok"] else "Import refused: " + result["error"]
	reload()
	return result
