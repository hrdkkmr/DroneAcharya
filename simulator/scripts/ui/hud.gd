extends CanvasLayer
## Displays values handed to it by Main; it holds no simulation state of its own.

const COMPASS_POINTS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var _message_time_left := 0.0

@onready var altitude_value: Label = $Telemetry/Rows/AltitudeValue
@onready var speed_value: Label = $Telemetry/Rows/SpeedValue
@onready var vertical_value: Label = $Telemetry/Rows/VerticalValue
@onready var heading_value: Label = $Telemetry/Rows/HeadingValue
@onready var time_value: Label = $Telemetry/Rows/TimeValue
@onready var view_value: Label = $Telemetry/Rows/ViewValue
@onready var objective_value: Label = $Mission/Rows/ObjectiveValue
@onready var status_value: Label = $Mission/Rows/StatusValue
@onready var message_label: Label = $Message
@onready var overlay: PanelContainer = $Overlay
@onready var overlay_title: Label = $Overlay/Rows/OverlayTitle
@onready var overlay_detail: Label = $Overlay/Rows/OverlayDetail


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


func show_mission(objective: String, status: String) -> void:
	objective_value.text = objective
	status_value.text = status


func show_message(text: String, seconds := 3.0) -> void:
	message_label.text = text
	message_label.visible = true
	_message_time_left = seconds


func show_overlay(title: String, detail: String) -> void:
	overlay_title.text = title
	overlay_detail.text = detail
	overlay.visible = true


func hide_overlay() -> void:
	overlay.visible = false


func _process(delta: float) -> void:
	if _message_time_left > 0.0:
		_message_time_left -= delta
		if _message_time_left <= 0.0:
			message_label.visible = false
