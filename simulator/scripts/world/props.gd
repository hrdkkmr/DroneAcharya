extends RefCounted
## Reusable low-poly props for the procedural flight environments.
##
## Drawing: every prop is added to a Batch, which groups instances by mesh and builds
## one MultiMeshInstance3D per mesh (one draw call each), with a per-instance colour.
## Collision: only props a drone can realistically hit get a box shape, added to a
## named StaticBody3D in the "obstacle" group (the name appears in crash messages).
## Decorative and distant props have no collision.
##
## Everything here is fictional, generic geometry built from Godot primitives.

class Batch:
	var meshes := {} ## key -> Mesh
	var transforms := {} ## key -> Array[Transform3D]
	var colors := {} ## key -> Array[Color]
	var shadows := {} ## key -> bool

	func add(key: String, mesh: Mesh, transform: Transform3D, color := Color.WHITE, cast_shadow := true) -> void:
		if not meshes.has(key):
			meshes[key] = mesh
			transforms[key] = []
			colors[key] = []
			shadows[key] = cast_shadow
		transforms[key].append(transform)
		colors[key].append(color)

	func count() -> int:
		var total := 0
		for key in transforms:
			total += transforms[key].size()
		return total

	## Builds one MultiMeshInstance3D per mesh under `parent`.
	func build(parent: Node3D) -> void:
		for key in meshes:
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_colors = true
			multimesh.mesh = meshes[key]
			multimesh.instance_count = transforms[key].size()
			for i in transforms[key].size():
				multimesh.set_instance_transform(i, transforms[key][i])
				multimesh.set_instance_color(i, colors[key][i])
			var node := MultiMeshInstance3D.new()
			node.name = key
			node.multimesh = multimesh
			if not shadows[key]:
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(node)


## A named static body in the "obstacle" group collecting box shapes.
class Colliders:
	var bodies := {} ## name -> StaticBody3D
	var parent: Node3D
	var shape_count := 0

	func _init(root: Node3D) -> void:
		parent = root

	func box(name: String, center: Vector3, size: Vector3, yaw := 0.0) -> void:
		var body: StaticBody3D = bodies.get(name)
		if body == null:
			body = StaticBody3D.new()
			body.name = name
			body.add_to_group("obstacle")
			parent.add_child(body)
			bodies[name] = body
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		shape.transform = Transform3D(Basis(Vector3.UP, yaw), center)
		body.add_child(shape)
		shape_count += 1

	## A box with any orientation (e.g. a sagging wire between two poles).
	func oriented(name: String, transform: Transform3D, size: Vector3) -> void:
		box(name, Vector3.ZERO, size)
		var body: StaticBody3D = bodies[name]
		(body.get_child(body.get_child_count() - 1) as CollisionShape3D).transform = transform


## Transform for a unit box stretched from `a` to `b` with the given thickness.
static func span(a: Vector3, b: Vector3, thickness: float) -> Transform3D:
	var direction := b - a
	var length := direction.length()
	var z := direction / maxf(length, 0.0001)
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return Transform3D(Basis(x * thickness, y * thickness, z * length), (a + b) * 0.5)


static var _cache := {}


## Material that takes its colour from the MultiMesh instance colour.
static func vertex_color_material(roughness := 0.9, emission := 0.0) -> StandardMaterial3D:
	var key := "vc_%.2f_%.2f" % [roughness, emission]
	if _cache.has(key):
		return _cache[key]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = roughness
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = Color(1.0, 0.92, 0.7)
		material.emission_energy_multiplier = emission
	_cache[key] = material
	return material


static func facade_material(floor_height: float, window_spacing: float, shopfront: bool, roof: Color) -> ShaderMaterial:
	var key := "facade_%.1f_%.1f_%s_%s" % [floor_height, window_spacing, shopfront, roof.to_html()]
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/building_facade.gdshader")
	material.set_shader_parameter("floor_height", floor_height)
	material.set_shader_parameter("window_spacing", window_spacing)
	material.set_shader_parameter("shopfront", 1.0 if shopfront else 0.0)
	material.set_shader_parameter("roof_color", roof)
	_cache[key] = material
	return material


## Unit-sized meshes (scaled per instance) shared by all builders.
static func unit_box(material: Material) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh.material = material
	return mesh


static func unit_cylinder(material: Material, segments := 10, top := 0.5) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = material
	return mesh


static func unit_sphere(material: Material, segments := 8) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = segments
	mesh.rings = maxi(segments / 2, 3)
	mesh.material = material
	return mesh


## Triangular prism (gable roof) with its ridge along local X, 1×1×1.
static func unit_prism(material: Material) -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = Vector3.ONE
	mesh.material = material
	return mesh


## Transform for a unit mesh scaled to `size`, centred at `center`, turned by `yaw`.
static func place(center: Vector3, size: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled_local(size), center)


## Gable roof: prism ridge along the building's longer side.
static func roof_transform(center: Vector3, footprint: Vector2, height: float, yaw := 0.0) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw)
	if footprint.y > footprint.x:
		basis = basis * Basis(Vector3.UP, PI / 2.0)
		footprint = Vector2(footprint.y, footprint.x)
	# PrismMesh points up along Y with its slope across X; turn it so the ridge runs along local X.
	basis = basis * Basis(Vector3.UP, PI / 2.0)
	return Transform3D(basis.scaled_local(Vector3(footprint.y + 0.6, height, footprint.x + 0.6)), center)


## A flat ribbon mesh (roads, paths) following `points` (x, z) at height `y`.
static func ribbon(points: PackedVector2Array, width: float, y: float, material: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var half := width * 0.5
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in points.size():
		var before := points[maxi(i - 1, 0)]
		var after := points[mini(i + 1, points.size() - 1)]
		var dir := (after - before).normalized()
		var side := Vector2(-dir.y, dir.x) * half
		left.append(Vector3(points[i].x + side.x, y, points[i].y + side.y))
		right.append(Vector3(points[i].x - side.x, y, points[i].y - side.y))
	for i in points.size() - 1:
		st.add_vertex(left[i])
		st.add_vertex(right[i])
		st.add_vertex(left[i + 1])
		st.add_vertex(left[i + 1])
		st.add_vertex(right[i])
		st.add_vertex(right[i + 1])
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func flat_material(color: Color, roughness := 0.95) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


## Large ground plane with gentle colour variation from procedural noise.
static func ground(color_a: Color, color_b: Color, size := 1600.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.add_to_group("ground")
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var gradient := Gradient.new()
	gradient.set_color(0, color_a)
	gradient.set_color(1, color_b)
	texture.color_ramp = gradient
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.uv1_scale = Vector3(size / 40.0, size / 40.0, 1.0)
	material.roughness = 1.0
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	return body


## Daylight sky, sun and light haze shared by the outdoor environments.
static func daylight(parent: Node3D, reduced_effects: bool, haze := 0.0025, tint := Color(0.72, 0.8, 0.88)) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.28, 0.47, 0.78)
	sky_material.sky_horizon_color = tint
	sky_material.ground_horizon_color = tint
	sky_material.ground_bottom_color = Color(0.3, 0.32, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.ambient_light_sky_contribution = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 1.4
	env.fog_enabled = true
	env.fog_density = haze
	env.fog_light_color = tint
	env.fog_sky_affect = 0.4
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = env
	parent.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = not reduced_effects
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 220.0
	parent.add_child(sun)
