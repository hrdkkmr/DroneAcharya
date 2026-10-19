extends Node3D
## Visual stand-in for one simulated actor, built from primitive meshes. Drawn at
## VISUAL_SCALE × its nominal size so distant objects stay findable with the zoom
## camera; this is a deliberate game readability choice, not a physical size.

const VISUAL_SCALE := 2.0

var profile := ""
var _wings: Array[Node3D] = []
var _flap_phase := 0.0


static func create(actor_def: Dictionary) -> Node3D:
	var node: Node3D = load("res://scripts/observation/actor_visuals.gd").new()
	node.name = actor_def["id"]
	node.profile = actor_def["profile"]
	node._build(float(actor_def["size_m"]) * VISUAL_SCALE)
	node.visible = false
	return node


func _build(size: float) -> void:
	match profile:
		"bird":
			var body := _mesh(_capsule(size * 0.12, size * 0.5), Color(0.25, 0.22, 0.2))
			body.rotation.x = PI / 2.0
			add_child(body)
			for side in [-1.0, 1.0]:
				var pivot := Node3D.new()
				add_child(pivot)
				var wing := _mesh(_box(Vector3(size * 0.55, size * 0.02, size * 0.22)), Color(0.3, 0.27, 0.24))
				wing.position.x = side * size * 0.3
				pivot.add_child(wing)
				pivot.set_meta("side", side)
				_wings.append(pivot)
		"balloon":
			var envelope := _mesh(_sphere(size * 0.5), Color(0.92, 0.92, 0.88))
			add_child(envelope)
			var payload := _mesh(_box(Vector3.ONE * size * 0.12), Color(0.4, 0.35, 0.3))
			payload.position.y = -size * 0.9
			add_child(payload)
		_:
			add_child(_mesh(_box(Vector3(size * 0.35, size * 0.12, size * 0.35)), Color(0.12, 0.13, 0.15)))
			for corner in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
				var rotor := _mesh(_cylinder(size * 0.17, size * 0.02), Color(0.08, 0.08, 0.08))
				rotor.position = corner * size * 0.32 + Vector3(0, size * 0.07, 0)
				add_child(rotor)
			if profile == "authorised_uav":
				var beacon := _mesh(_sphere(size * 0.06), Color(0.2, 1.0, 0.4), true)
				beacon.position.y = size * 0.1
				add_child(beacon)


## Places the visual at a simulated position and heading; flaps wings for birds.
func show_state(position_m: Vector3, yaw: float, delta: float) -> void:
	position = position_m
	rotation.y = yaw
	visible = true
	if _wings.is_empty():
		return
	_flap_phase = fmod(_flap_phase + delta * 9.0, TAU)
	for pivot in _wings:
		pivot.rotation.z = float(pivot.get_meta("side")) * sin(_flap_phase) * 0.6


func _mesh(mesh: Mesh, color: Color, glow := false) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 3.0
	mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return mesh


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	return mesh
