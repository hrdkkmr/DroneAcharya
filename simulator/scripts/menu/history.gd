extends Control
## Training history and reports. Lists validated threat-detection sessions and flight
## records together (newest first; invalid files are listed with reasons and never
## modified), shows the plain-language report for the selected entry with the full
## rubric output under "Details", verifies or plays a threat session's deterministic
## replay, and exports or imports versioned JSON.

const AppState := preload("res://scripts/app/app_state.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const SessionIO := preload("res://scripts/training/session_io.gd")
const Replay := preload("res://scripts/training/replay.gd")
const ReportBuilder := preload("res://scripts/training/report_builder.gd")
const FlightRecord := preload("res://scripts/flight/flight_record.gd")
const MlClassifier := preload("res://scripts/ai/ml_classifier.gd")
const Adaptive := preload("res://scripts/training/adaptive.gd")

var sessions: Array = [] ## threat-detection records
var flights: Array = [] ## flight-training records
var entries: Array = [] ## both, newest first, as shown in the list
var invalid: Array = []
var selected: Dictionary = {}
var report: Dictionary = {}
var list: ItemList
var report_label: RichTextLabel
var details_label: RichTextLabel
var details_toggle: Button
var status_label: Label
var invalid_label: Label
var import_dialog: FileDialog
var recommendation: Dictionary = {}
var recommendation_label: RichTextLabel
var replay_button: Button
var verify_button: Button
var sessions_dir := AppState.sessions_dir
var flights_dir := AppState.flight_sessions_dir


func _ready() -> void:
	UiKit.background(self)
	var root := UiKit.screen_column(self, 1520, 10)
	root.add_child(UiKit.header("Training history", "Reports", "Plain-language reports of your missions and exercises. Everything here is computed from what was recorded."))
	var body := UiKit.hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := UiKit.vbox(8)
	left.custom_minimum_size = Vector2(440, 0)
	body.add_child(left)
	left.add_child(UiKit.heading("Saved missions and exercises"))
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
	left.add_child(UiKit.heading("Next recommended exercise (rule-based)"))
	recommendation_label = UiKit.rich(14)
	left.add_child(recommendation_label)
	left.add_child(UiKit.button("Start recommended exercise", start_recommended))

	var right := UiKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var report_column := UiKit.vbox(10)
	report_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(report_column)
	report_label = UiKit.rich(16)
	report_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_column.add_child(report_label)
	details_toggle = UiKit.button("Show details (scoring and full log)", toggle_details, 320)
	details_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	report_column.add_child(details_toggle)
	details_label = UiKit.rich(14)
	details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_label.visible = false
	report_column.add_child(details_label)
	var actions := UiKit.hbox(8)
	replay_button = UiKit.button("Replay in 3D", replay_in_3d, 170)
	actions.add_child(replay_button)
	verify_button = UiKit.button("Verify replay", verify_replay, 170)
	actions.add_child(verify_button)
	actions.add_child(UiKit.button("Export this entry", export_selected, 190))
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


static func is_flight(record: Dictionary) -> bool:
	return record.get("format", "") == FlightRecord.FORMAT


func reload() -> void:
	var history := SessionIO.list_history(sessions_dir)
	sessions = history["sessions"]
	invalid = history["invalid"].duplicate()
	var flight_history := FlightRecord.list_history(flights_dir)
	flights = flight_history["records"]
	for bad in flight_history["invalid"]:
		invalid.append({"file": bad["file"], "reason": bad["error"]})
	entries = sessions + flights
	entries.sort_custom(func(a, b): return String(a["created_at"]) > String(b["created_at"]))
	list.clear()
	for record in entries:
		var when := String(record["created_at"]).substr(0, 16).replace("T", " ")
		if is_flight(record):
			var r: Dictionary = record["result"]
			list.add_item("Flight · %s · %s · %s" % [when, record["mission"]["title"], "completed" if r["status"] == "completed" else "failed"])
		else:
			list.add_item("Threat · %s · %s · %.1f" % [when, record["scenario"]["title"], record["evaluation"]["score"]])
		list.set_item_tooltip(list.item_count - 1, String(record["session_id"]))
	invalid_label.text = "" if invalid.is_empty() else "%d invalid file(s) not loaded (left untouched): %s" % [invalid.size(), "; ".join(PackedStringArray(invalid.map(func(i): return "%s — %s" % [i["file"], i["reason"]])))]
	recommendation = Adaptive.recommend(sessions)
	recommendation_label.text = "[b]%s[/b] · level %d → %d (%s)\n%s" % [recommendation["config"]["title"], recommendation["baseline_difficulty"],
		recommendation["difficulty"], recommendation["rule"], "\n".join(recommendation["reasons"])]
	var wanted: String = AppState.review_session.get("session_id", "")
	var index := 0
	for i in entries.size():
		if entries[i]["session_id"] == wanted:
			index = i
	if entries.is_empty():
		selected = {}
		report = {}
		report_label.text = "No saved missions or exercises yet. Finish a flight mission or a threat-detection exercise to create a report."
		details_toggle.visible = false
	else:
		list.select(index)
		_on_selected(index)


func _on_selected(index: int) -> void:
	selected = entries[index]
	AppState.review_session = selected
	report = ReportBuilder.build(selected)
	report_label.text = ReportBuilder.to_bbcode(report)
	details_label.text = report["details"]
	details_toggle.visible = not String(report["details"]).is_empty()
	replay_button.disabled = is_flight(selected)
	verify_button.disabled = is_flight(selected)
	status_label.text = ""


func toggle_details() -> void:
	details_label.visible = not details_label.visible
	details_toggle.text = "Hide details" if details_label.visible else "Show details (scoring and full log)"


func start_recommended() -> void:
	AppState.selected_config = recommendation["config"]
	AppState.replay_requested = false
	AppState.goto(get_tree(), "briefing")


func verify_replay() -> Dictionary:
	if selected.is_empty() or is_flight(selected):
		return {}
	var result := Replay.new(selected, MlClassifier.shared()).verify()
	if result["identical"]:
		status_label.text = "Replay verified: re-simulating seed %d with the recorded actions reproduces every event and the score exactly." % selected["scenario"]["seed"]
	else:
		status_label.text = "Replay differs: %s %s" % [result["first_difference"], " ".join(result["warnings"])]
	return result


func replay_in_3d() -> void:
	if selected.is_empty() or is_flight(selected):
		return
	AppState.review_session = selected
	AppState.replay_requested = true
	AppState.selected_config = selected["scenario"]
	AppState.goto(get_tree(), "observation")


func export_selected() -> Dictionary:
	if selected.is_empty():
		return {}
	if is_flight(selected):
		DirAccess.make_dir_recursive_absolute(SessionIO.EXPORT_DIR)
		var path := SessionIO.EXPORT_DIR.path_join("droneacharya-flight-%s.json" % String(selected["session_id"]).validate_filename())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			status_label.text = "Export failed: cannot write " + path
			return {"ok": false}
		file.store_string(JSON.stringify(selected, "  "))
		file.close()
		status_label.text = "Exported the flight record to %s" % ProjectSettings.globalize_path(path)
		return {"ok": true, "path": path, "count": 1}
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
