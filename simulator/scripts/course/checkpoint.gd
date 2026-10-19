extends Area3D
## A ring the drone must fly through. The mission assigns its order and colour state.

signal drone_entered(index: int)

const COLOR_NEXT := Color(1.0, 0.75, 0.1)
const COLOR_PENDING := Color(0.35, 0.55, 0.9)
const COLOR_PASSED := Color(0.25, 0.85, 0.35)

var index := -1

var _material := StandardMaterial3D.new()

@onready var _ring: MeshInstance3D = get_node_or_null("Ring")
@onready var _label: Label3D = get_node_or_null("Number")


func _ready() -> void:
	_material.emission_enabled = true
	if _ring:
		_ring.material_override = _material
	body_entered.connect(_on_body_entered)
	set_progress(false, false)


func configure(new_index: int) -> void:
	index = new_index
	if _label:
		_label.text = str(new_index + 1)


func set_progress(passed: bool, is_next: bool) -> void:
	var color := COLOR_PASSED if passed else (COLOR_NEXT if is_next else COLOR_PENDING)
	_material.albedo_color = color
	_material.emission = color
	_material.emission_energy_multiplier = 1.5 if is_next else 0.4


func _on_body_entered(body: Node3D) -> void:
	if index >= 0 and body.is_in_group("drone"):
		drone_entered.emit(index)
