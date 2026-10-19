extends RefCounted
## Builds the visible world for an observation scenario from its definition:
## sky and lighting (day/night), fog (clear/haze/fog), ground, obstacles,
## protected zone and observation tower. Purely visual; the simulation and sensor
## use the definition's obstacle boxes directly.

const FOG_DENSITY := {"clear": 0.0006, "haze": 0.003, "fog": 0.012}


static func build(definition: Dictionary, parent: Node3D) -> void:
	var config: Dictionary = definition["config"]
	var night: bool = config["time_of_day"] == "night"
	parent.add_child(_environment(night, config["visibility"]))
	parent.add_child(_light(night))
	parent.add_child(_ground(config["environment"], night))
	for node in _obstacles(definition["layout"]["obstacles"], night):
		parent.add_child(node)
	parent.add_child(_zone(definition["protected_zone"]["radius_m"]))
	parent.add_child(_tower(definition["observer_position"]))


static func _environment(night: bool, visibility: String) -> WorldEnvironment:
	var sky_material := ProceduralSkyMaterial.new()
	if night:
		sky_material.sky_top_color = Color(0.01, 0.015, 0.04)
		sky_material.sky_horizon_color = Color(0.04, 0.05, 0.09)
		sky_material.ground_horizon_color = Color(0.03, 0.035, 0.05)
		sky_material.ground_bottom_color = Color(0.01, 0.01, 0.02)
		sky_material.sun_angle_max = 1.0
	else:
		sky_material.sky_top_color = Color(0.3, 0.5, 0.8)
		sky_material.sky_horizon_color = Color(0.7, 0.78, 0.86)
		sky_material.ground_horizon_color = Color(0.7, 0.78, 0.86)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6 if night else 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = FOG_DENSITY.get(visibility, 0.0006)
	env.fog_light_color = Color(0.05, 0.06, 0.09) if night else Color(0.75, 0.8, 0.85)
	env.fog_sky_affect = 0.6
	var node := WorldEnvironment.new()
	node.name = "WorldEnvironment"
	node.environment = env
	return node


static func _light(night: bool) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "Moon" if night else "Sun"
	light.rotation = Vector3(deg_to_rad(-35.0 if night else -50.0), deg_to_rad(-30.0), 0.0)
	light.light_energy = 0.18 if night else 1.0
	light.light_color = Color(0.6, 0.7, 1.0) if night else Color(1.0, 0.97, 0.92)
	light.shadow_enabled = not night
	light.directional_shadow_max_distance = 300.0
	return light


static func _ground(environment: String, night: bool) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/ground_grid.gdshader")
	var base := Color(0.36, 0.37, 0.38) if environment == "urban" else Color(0.34, 0.45, 0.25)
	if night:
		base = base.darkened(0.4)
	material.set_shader_parameter("base_color", base)
	material.set_shader_parameter("line_color", base.darkened(0.2))
	material.set_shader_parameter("minor_spacing", 20.0)
	material.set_shader_parameter("major_spacing", 100.0)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(6000, 6000)
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "Ground"
	node.mesh = mesh
	return node


## One MultiMesh per obstacle kind: cheap to draw even with hundreds of boxes.
static func _obstacles(obstacles: Array, night: bool) -> Array:
	var by_kind := {}
	for o in obstacles:
		by_kind.get_or_add(o["kind"], []).append(o)
	var nodes := []
	for kind in by_kind:
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.9
		var mesh: Mesh
		if kind == "tree":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.5
			cone.height = 1.0
			cone.radial_segments = 8
			mesh = cone
		else:
			mesh = BoxMesh.new()
		mesh.surface_set_material(0, material)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		multimesh.instance_count = by_kind[kind].size()
		var i := 0
		for o in by_kind[kind]:
			var size: Vector3 = o["size"]
			multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(size), o["center"]))
			var shade := 0.85 + 0.15 * sin(float(i) * 12.9898)
			var color := Color(0.2, 0.42, 0.2) * shade if kind == "tree" else Color(0.62, 0.6, 0.56) * shade
			multimesh.set_instance_color(i, color.darkened(0.5) if night else color)
			i += 1
		var node := MultiMeshInstance3D.new()
		node.name = kind.capitalize() + "s"
		node.multimesh = multimesh
		nodes.append(node)
	return nodes


static func _zone(radius: float) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.35, 0.25, 0.22)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.05
	mesh.radial_segments = 64
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "ProtectedZone"
	node.mesh = mesh
	node.position = Vector3(0.0, 0.05, 0.0)
	return node


static func _tower(top: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.3, 0.25)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4.0, top.y - 1.5, 4.0)
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "ObservationTower"
	node.mesh = mesh
	node.position = Vector3(top.x, (top.y - 1.5) * 0.5, top.z + 3.0)
	return node
