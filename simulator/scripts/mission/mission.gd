extends Node
## Connects the pure MissionState to the scene: drone, checkpoints and landing zone.
## If any of them is missing the mission stays inert instead of erroring every frame.

const MissionState := preload("res://scripts/mission/mission_state.gd")

signal message(text: String)

@export var drone_path: NodePath
@export var checkpoints_path: NodePath ## Parent node; checkpoints are flown in child order.
@export var landing_zone_path: NodePath
## Leaving this box (x/z in metres) fails the mission.
@export var training_area := Rect2(-80.0, -170.0, 160.0, 210.0)

var state: MissionState = MissionState.new(0)
var checkpoints: Array[Node] = []
var drone: CharacterBody3D
var landing_zone: Node3D


func _ready() -> void:
	drone = get_node_or_null(drone_path) as CharacterBody3D
	landing_zone = get_node_or_null(landing_zone_path) as Node3D
	var parent := get_node_or_null(checkpoints_path)
	if parent:
		for child in parent.get_children():
			if child.has_signal("drone_entered"):
				checkpoints.append(child)
	if not is_configured():
		push_warning("Mission is missing its drone, checkpoints or landing zone; it will stay inactive.")
		return
	state = MissionState.new(checkpoints.size())
	for i in checkpoints.size():
		checkpoints[i].configure(i)
		checkpoints[i].drone_entered.connect(_on_checkpoint_entered)
	if drone.has_signal("crashed"):
		drone.crashed.connect(_on_drone_crashed)
	_refresh_checkpoints()


func is_configured() -> bool:
	return drone != null and landing_zone != null and landing_zone.has_method("contains") and not checkpoints.is_empty()


func reset() -> void:
	state.reset()
	_refresh_checkpoints()


func in_landing_zone() -> bool:
	return is_configured() and landing_zone.contains(drone.global_position)


func objective_text() -> String:
	return state.objective_text() if is_configured() else "Mission unavailable: course is incomplete"


func status_text() -> String:
	if not is_configured():
		return "Unavailable"
	return state.status_text(drone.is_on_floor(), in_landing_zone())


func _physics_process(delta: float) -> void:
	if not is_configured():
		return
	var position := drone.global_position
	if not training_area.has_point(Vector2(position.x, position.z)):
		_emit(state.fail("left the training area"))
		if drone.get("controls_enabled") != null:
			drone.controls_enabled = false
	var on_ground := drone.is_on_floor()
	var speed := drone.velocity.length()
	_emit(state.update(drone.altitude(), on_ground, in_landing_zone(), speed, delta))
	if state.status == MissionState.Status.COMPLETED:
		drone.controls_enabled = false


func _on_checkpoint_entered(index: int) -> void:
	var text := state.pass_checkpoint(index)
	_refresh_checkpoints()
	_emit(text)


func _on_drone_crashed(impact_speed: float, obstacle_name: String) -> void:
	_emit(state.fail("collided with %s at %.1f m/s" % [obstacle_name, impact_speed]))


func _refresh_checkpoints() -> void:
	for i in checkpoints.size():
		checkpoints[i].set_progress(i < state.next_checkpoint, i == state.next_checkpoint)


func _emit(text: String) -> void:
	if not text.is_empty():
		message.emit(text)
