extends Node3D
## Observation-post camera. Look with right-mouse drag or W/A/S/D; zoom with the
## mouse wheel. Sensitivity scales with zoom so aiming stays precise when zoomed in.
## Eye view zooms 70°→20°; the simulated sensor camera zooms 30°→2°.

const MAX_FOV := 70.0
const EYE_MIN_FOV := 20.0
const SENSOR_MAX_FOV := 30.0
const SENSOR_MIN_FOV := 2.0
const KEY_LOOK_DEGREES_PER_SECOND := 60.0

@export var mouse_sensitivity := 0.25 ## degrees per pixel at full zoom-out

var yaw_degrees := 0.0
var pitch_degrees := 5.0
var fov := MAX_FOV
var sensor_mode := false

@onready var eye_camera: Camera3D = $EyeCamera


func _ready() -> void:
	eye_camera.make_current()
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var scale := mouse_sensitivity * fov / MAX_FOV
		yaw_degrees -= event.relative.x * scale
		pitch_degrees -= event.relative.y * scale
		_apply()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_fov(fov / 1.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_fov(fov * 1.2)


func _process(delta: float) -> void:
	var turn := Input.get_axis("move_right", "move_left")
	var tilt := Input.get_axis("move_back", "move_forward")
	if turn != 0.0 or tilt != 0.0:
		var rate := KEY_LOOK_DEGREES_PER_SECOND * delta * maxf(fov / MAX_FOV, 0.1)
		yaw_degrees += turn * rate
		pitch_degrees += tilt * rate
		_apply()


func set_fov(value: float) -> void:
	if sensor_mode:
		fov = clampf(value, SENSOR_MIN_FOV, SENSOR_MAX_FOV)
	else:
		fov = clampf(value, EYE_MIN_FOV, MAX_FOV)
	_apply()


## Switches between the naked-eye view and the simulated sensor camera.
func set_sensor_mode(enabled: bool) -> void:
	sensor_mode = enabled
	set_fov(minf(fov, 12.0) if enabled else maxf(fov, 50.0))


## Points the view at a world position (used by "centre on track" and tests).
func look_at_point(target: Vector3) -> void:
	var offset := target - global_position
	yaw_degrees = rad_to_deg(atan2(-offset.x, -offset.z))
	pitch_degrees = rad_to_deg(atan2(offset.y, Vector2(offset.x, offset.z).length()))
	_apply()


func forward() -> Vector3:
	return -eye_camera.global_basis.z


func _apply() -> void:
	pitch_degrees = clampf(pitch_degrees, -60.0, 85.0)
	yaw_degrees = fposmod(yaw_degrees, 360.0)
	rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	eye_camera.rotation = Vector3(deg_to_rad(pitch_degrees), 0.0, 0.0)
	eye_camera.fov = fov
