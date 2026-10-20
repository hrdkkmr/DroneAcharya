extends CanvasLayer
## Flight-training HUD. Displays values handed to it by the flight scene; it holds no
## simulation state of its own. Layout (1600×900 design, scaled by the window):
##  * top left: mission card — objective, mission clock (with limit), status
##  * top right: alert banners (each with a word and a shape, never colour alone)
##  * bottom left: telemetry strip — altitude, speed, climb, heading, battery, integrity, camera
##  * bottom right: radar (added by the flight scene)
##  * centre: short messages; the pause / result screen is a shared PauseMenu.

const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const COMPASS_POINTS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var altitude_value: Label
var speed_value: Label
var vertical_value: Label
var heading_value: Label
var time_value: Label
var limit_value: Label
var view_value: Label
var battery_value: Label
var integrity_value: Label
var mission_title: Label
var objective_value: Label
var status_value: Label
var message_label: Label
var alerts_box: VBoxContainer
var alerts := {} ## id -> PanelContainer
var root: Control
var overlay: PauseMenu
var overlay_title: Label
var overlay_detail: Label

var _message_time_left := 0.0


func _ready() -> void:
	root = Control.new()
	root.name = "Root"
	root.theme = UiKit.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_mission_card()
	_build_telemetry()
	alerts_box = UiKit.vbox(6)
	alerts_box.name = "Alerts"
	alerts_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	alerts_box.offset_left = -360
	alerts_box.offset_right = -16
	alerts_box.offset_top = 16
	alerts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(alerts_box)
	message_label = UiKit.label("", 24)
	message_label.name = "Message"
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_constant_override("outline_size", 8)
	message_label.add_theme_color_override("font_outline_color", Color.BLACK)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	message_label.offset_top = 170
	message_label.offset_bottom = 210
	message_label.visible = false
	root.add_child(message_label)
	overlay = PauseMenu.new()
	overlay.name = "PauseMenu"
	add_child(overlay)
	overlay_title = overlay.title_label
	overlay_detail = overlay.detail_label


func _build_mission_card() -> void:
	var card := UiKit.panel(0.72)
	card.name = "Mission"
	card.position = Vector2(16, 16)
	card.custom_minimum_size = Vector2(430, 0)
	root.add_child(card)
	var rows := UiKit.vbox(4)
	card.add_child(rows)
	mission_title = UiKit.heading("Mission", 14)
	rows.add_child(mission_title)
	objective_value = UiKit.label("-", 20, UiKit.TEXT, true)
	objective_value.custom_minimum_size = Vector2(400, 0)
	rows.add_child(objective_value)
	var clock_row := UiKit.hbox(12)
	time_value = UiKit.label("00:00.0", 34, Color.WHITE)
	clock_row.add_child(time_value)
	limit_value = UiKit.label("", 16, UiKit.MUTED)
	limit_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_row.add_child(limit_value)
	rows.add_child(clock_row)
	status_value = UiKit.label("-", 16, UiKit.MUTED, true)
	rows.add_child(status_value)


func _build_telemetry() -> void:
	var strip := UiKit.panel(0.72)
	strip.name = "Telemetry"
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(strip)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 22)
	strip.add_child(grid)
	var captions := ["ALT", "SPEED", "CLIMB", "HEADING", "BATTERY", "INTEGRITY", "CAMERA"]
	for caption in captions:
		grid.add_child(UiKit.label(caption, 13, UiKit.MUTED))
	altitude_value = _value(grid)
	speed_value = _value(grid)
	vertical_value = _value(grid)
	heading_value = _value(grid)
	battery_value = _value(grid)
	integrity_value = _value(grid)
	view_value = _value(grid)


func _value(parent: Control) -> Label:
	var value := UiKit.label("-", 20, Color.WHITE)
	parent.add_child(value)
	return value


static func format_altitude(metres: float) -> String:
	return "%.1f m" % metres


static func format_speed(metres_per_second: float) -> String:
	return "%.1f m/s" % metres_per_second


static func format_vertical_speed(metres_per_second: float) -> String:
	return "%+.1f m/s" % metres_per_second


static func format_heading(degrees: float) -> String:
	var wrapped := fposmod(degrees, 360.0)
	var whole := int(round(wrapped)) % 360
	var point: String = COMPASS_POINTS[int(round(wrapped / 45.0)) % 8]
	return "%03d° %s" % [whole, point]


static func format_time(seconds: float) -> String:
	var total := maxf(seconds, 0.0)
	return "%02d:%04.1f" % [int(total / 60.0), fmod(total, 60.0)]


func show_telemetry(altitude: float, horizontal_speed: float, vertical_speed: float, heading: float, elapsed: float, view_name: String) -> void:
	altitude_value.text = format_altitude(altitude)
	speed_value.text = format_speed(horizontal_speed)
	vertical_value.text = format_vertical_speed(vertical_speed)
	heading_value.text = format_heading(heading)
	time_value.text = format_time(elapsed)
	view_value.text = view_name


## Mission clock limit, battery and integrity. `time_left` is INF without a limit.
func show_limits(time_limit: float, time_left: float, time_warning: bool, battery: float, battery_warning: bool, integrity: float) -> void:
	if time_limit > 0.0:
		limit_value.text = "limit %s · %s left" % [format_time(time_limit).left(5), format_time(time_left).left(5)]
	else:
		limit_value.text = "no time limit"
	time_value.add_theme_color_override("font_color", UiKit.WARN if time_warning else Color.WHITE)
	battery_value.text = "%d%%" % roundi(battery * 100.0)
	battery_value.add_theme_color_override("font_color", UiKit.WARN if battery_warning else Color.WHITE)
	integrity_value.text = "%d%%" % roundi(integrity)
	integrity_value.add_theme_color_override("font_color", UiKit.BAD if integrity < 100.0 else Color.WHITE)
	set_alert("time", time_warning, "TIME LOW", "%s left" % format_time(time_left).left(5), UiKit.WARN)
	set_alert("battery", battery_warning, "BATTERY LOW", "%d%% — land soon" % roundi(battery * 100.0), UiKit.WARN)


func show_mission(objective: String, status: String) -> void:
	objective_value.text = objective
	status_value.text = status


func set_mission_title(text: String) -> void:
	mission_title.text = text.to_upper()


## Shows or hides one alert banner: a bold word and a detail, with a coloured bar
## and a symbol so it does not rely on colour.
func set_alert(id: String, active: bool, word: String, detail: String, color: Color) -> void:
	var banner: PanelContainer = alerts.get(id)
	if not active:
		if banner:
			banner.queue_free()
			alerts.erase(id)
		return
	if banner == null:
		banner = UiKit.panel(0.85)
		banner.name = "Alert_" + id
		var style: StyleBoxFlat = banner.get_theme_stylebox("panel")
		style.border_width_left = 6
		style.border_color = color
		var row := UiKit.hbox(10)
		row.add_child(UiKit.label("!", 22, color))
		var word_label := UiKit.label(word, 18, color)
		word_label.name = "Word"
		row.add_child(word_label)
		var detail_label := UiKit.label("", 16, UiKit.TEXT)
		detail_label.name = "Detail"
		row.add_child(detail_label)
		banner.add_child(row)
		alerts_box.add_child(banner)
		alerts[id] = banner
	(banner.get_child(0).get_node("Detail") as Label).text = detail


func has_alert(id: String) -> bool:
	return alerts.has(id)


func show_message(text: String, seconds := 3.0) -> void:
	message_label.text = text
	message_label.visible = true
	_message_time_left = seconds


## `actions`: [id, label] pairs for the buttons; `controls`: rows for the Controls section.
func show_overlay(title: String, detail: String, actions: Array = [], controls: Array = []) -> void:
	overlay.open(title, detail, actions, controls)


func hide_overlay() -> void:
	overlay.close()


func _process(delta: float) -> void:
	if _message_time_left > 0.0:
		_message_time_left -= delta
		if _message_time_left <= 0.0:
			message_label.visible = false
