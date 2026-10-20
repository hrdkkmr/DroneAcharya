extends Node3D
## Draws the flight traffic simulation: other drones as small quadcopters (colour and
## size by kind), simulated projectiles as small glowing markers with a short trail,
## and hostile emplacement sites as low bunkers with a red light. Visual only.

var _nodes := {} ## entity id -> Node3D
var _materials := {}


func _material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var key := color.to_html() + str(emission)
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.6
		if emission > 0.0:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = emission
		_materials[key] = m
	return _materials[key]


func add_sites(sites: Array) -> void:
	for i in sites.size():
		var site := Node3D.new()
		site.name = "Site%d" % (i + 1)
		site.position = sites[i]
		var bunker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(5.0, 1.6, 4.0)
		box.material = _material(Color(0.36, 0.34, 0.3))
		bunker.mesh = box
		bunker.position = Vector3(0, 0.8, 0)
		site.add_child(bunker)
		var light := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.3
		sphere.height = 0.6
		sphere.material = _material(Color(1.0, 0.2, 0.15), 3.0)
		light.mesh = sphere
		light.position = Vector3(0, 1.9, 0)
		site.add_child(light)
		add_child(site)


func sync(entities: Array) -> void:
	var live := {}
	for entity in entities:
		var id: String = entity["id"]
		live[id] = true
		var node: Node3D = _nodes.get(id)
		if node == null:
			node = _create(entity["kind"])
			node.name = id
			add_child(node)
			_nodes[id] = node
			node.position = entity["position"]
			node.reset_physics_interpolation()
		node.position = entity["position"]
		var velocity: Vector3 = entity["velocity"]
		if Vector2(velocity.x, velocity.z).length() > 0.3:
			node.rotation.y = atan2(-velocity.x, -velocity.z)
		if entity["kind"] == "projectile" and velocity.length() > 0.1:
			node.look_at(node.global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
	for id in _nodes.keys():
		if not live.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)


func count() -> int:
	return _nodes.size()


func _create(kind: String) -> Node3D:
	var root := Node3D.new()
	if kind == "projectile":
		var head := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.35
		sphere.height = 0.7
		sphere.material = _material(Color(1.0, 0.55, 0.15), 4.0)
		head.mesh = sphere
		root.add_child(head)
		var trail := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.12, 4.0)
		box.material = _material(Color(1.0, 0.75, 0.4), 1.5)
		trail.mesh = box
		trail.position = Vector3(0, 0, 2.2)
		root.add_child(trail)
		return root
	var color: Color = {"friendly": Color(0.25, 0.45, 0.75), "unknown": Color(0.5, 0.5, 0.5), "hostile_drone": Color(0.55, 0.12, 0.1)}.get(kind, Color.GRAY)
	var scale := 1.6 if kind == "hostile_drone" else 1.2
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.5, 0.18, 0.6) * scale
	body_mesh.material = _material(color)
	body.mesh = body_mesh
	root.add_child(body)
	for arm_yaw in [PI / 4.0, -PI / 4.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(1.3, 0.06, 0.08) * scale
		arm_mesh.material = _material(Color(0.25, 0.25, 0.27))
		arm.mesh = arm_mesh
		arm.rotation.y = arm_yaw
		root.add_child(arm)
	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.1 * scale
	beacon_mesh.height = 0.2 * scale
	beacon_mesh.material = _material(color.lightened(0.4), 3.0)
	beacon.mesh = beacon_mesh
	beacon.position = Vector3(0, 0.15 * scale, 0)
	root.add_child(beacon)
	return root
