extends Node3D
## Two views: a smoothed chase camera behind the drone, and the drone's onboard camera.
## The chase camera follows the drone's heading only, so tilting does not shake the view.

enum Mode { FOLLOW, ONBOARD }

@export var drone_path: NodePath
@export var follow_distance := 7.0 ## m behind the drone
@export var follow_height := 3.0 ## m above the drone
@export var follow_smoothing := 5.0 ## higher = snappier
@export var minimum_camera_height := 0.5 ## m; keeps the chase camera above the ground

var mode := Mode.FOLLOW

var _drone: Node3D

@onready var follow_camera: Camera3D = get_node_or_null("FollowCamera")


func _ready() -> void:
	_drone = get_node_or_null(drone_path) as Node3D
	if _drone == null or follow_camera == null:
		push_warning("CameraRig needs a drone and a FollowCamera child; camera will not follow.")
		return
	set_mode(Mode.FOLLOW)
	snap()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_view"):
		toggle_mode()
		get_viewport().set_input_as_handled()


func toggle_mode() -> void:
	set_mode(Mode.ONBOARD if mode == Mode.FOLLOW else Mode.FOLLOW)


func set_mode(new_mode: Mode) -> void:
	var onboard := _onboard_camera()
	if new_mode == Mode.ONBOARD and onboard == null:
		new_mode = Mode.FOLLOW
	mode = new_mode
	if mode == Mode.ONBOARD:
		onboard.make_current()
	elif follow_camera:
		follow_camera.make_current()


func active_camera() -> Camera3D:
	return _onboard_camera() if mode == Mode.ONBOARD else follow_camera


## Jumps the chase camera to its target position (used at start and after reset).
func snap() -> void:
	if _drone == null or follow_camera == null:
		return
	follow_camera.global_position = _follow_target()
	_look_at_drone()
	follow_camera.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if _drone == null or follow_camera == null:
		return
	var blend := 1.0 - exp(-follow_smoothing * delta)
	follow_camera.global_position = follow_camera.global_position.lerp(_follow_target(), blend)
	follow_camera.global_position.y = maxf(follow_camera.global_position.y, minimum_camera_height)
	_look_at_drone()


func _follow_target() -> Vector3:
	var behind := Vector3(0.0, 0.0, follow_distance).rotated(Vector3.UP, _drone.global_rotation.y)
	var target := _drone.global_position + behind + Vector3.UP * follow_height
	target.y = maxf(target.y, minimum_camera_height)
	return target


func _look_at_drone() -> void:
	var focus := _drone.global_position + Vector3.UP * 0.5
	if follow_camera.global_position.distance_to(focus) > 0.01:
		follow_camera.look_at(focus, Vector3.UP)


func _onboard_camera() -> Camera3D:
	return _drone.get_node_or_null("OnboardCamera") as Camera3D if _drone else null
