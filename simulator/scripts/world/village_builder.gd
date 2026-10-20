extends RefCounted
## Procedural fictional village for flight training, deliberately unlike the city:
## winding dirt roads and footpaths, scattered houses of three kinds (pitched-roof,
## flat-roof concrete with roof tanks, round thatched huts) in walled compounds,
## crop fields with rows and earth bunds, an orchard, a pond, shade trees and bushes,
## utility poles with sagging wires along the main road, a water-tank tower, farm
## sheds and haystacks, and a fenced camp with tents, sandbags, a watchtower and the
## landing helipad. Deterministic for a seed; props that would block the mission
## route are left out (route_corridor.gd).

const Props := preload("res://scripts/world/props.gd")
const RouteCorridor := preload("res://scripts/world/route_corridor.gd")

const AREA := Rect2(-230.0, -400.0, 450.0, 490.0)
const MAIN_ROAD := [Vector2(-215, 75), Vector2(-150, 52), Vector2(-95, 30), Vector2(-55, 2), Vector2(-25, -38),
	Vector2(-6, -88), Vector2(18, -138), Vector2(55, -185), Vector2(95, -222), Vector2(118, -258)]
const SIDE_PATHS := [
	[Vector2(-6, -88), Vector2(-60, -110), Vector2(-120, -140), Vector2(-175, -150)],
	[Vector2(-6, -88), Vector2(45, -70), Vector2(100, -58), Vector2(180, -45)],
	[Vector2(-55, 2), Vector2(-45, 30), Vector2(-40, 55)],
	[Vector2(55, -185), Vector2(5, -215), Vector2(-60, -250)],
]
const CAMP := Rect2(98.0, -335.0, 80.0, 70.0)
const VILLAGE_CENTRE := Vector2(-10.0, -80.0)
const WALL_COLORS := [Color(0.85, 0.78, 0.62), Color(0.78, 0.6, 0.5), Color(0.7, 0.75, 0.78), Color(0.82, 0.7, 0.45),
	Color(0.72, 0.56, 0.42), Color(0.9, 0.86, 0.78), Color(0.6, 0.52, 0.42)]
const ROOF_COLORS := [Color(0.6, 0.28, 0.18), Color(0.5, 0.52, 0.55), Color(0.42, 0.25, 0.18), Color(0.35, 0.4, 0.38)]
const CROPS := [Color(0.38, 0.55, 0.22), Color(0.78, 0.7, 0.25), Color(0.45, 0.33, 0.22), Color(0.3, 0.5, 0.25), Color(0.6, 0.62, 0.3)]

var rng := RandomNumberGenerator.new()
var corridor: RouteCorridor
var batch := Props.Batch.new()
var houses := Props.Batch.new()
var colliders: Props.Colliders
var stats := {"houses": 0, "huts": 0, "trees": 0, "fields": 0, "poles": 0, "rejected": 0}
var _taken: Array = [] ## [Vector2 centre, float radius] of placed structures

var _vc: StandardMaterial3D
var _box: BoxMesh
var _cyl: CylinderMesh
var _cone: CylinderMesh
var _sphere: SphereMesh
var _prism: PrismMesh


static func build(parent: Node3D, route: Dictionary, seed: int, reduced_effects := false) -> Dictionary:
	var builder = load("res://scripts/world/village_builder.gd").new()
	return builder._build(parent, route, seed, reduced_effects)


func _build(parent: Node3D, route: Dictionary, seed: int, reduced_effects: bool) -> Dictionary:
	rng.seed = seed
	corridor = RouteCorridor.new(route["spawn"], route["checkpoints"], route["landing"])
	_vc = Props.vertex_color_material()
	_box = Props.unit_box(_vc)
	_cyl = Props.unit_cylinder(_vc, 12)
	_cone = Props.unit_cylinder(_vc, 10, 0.0)
	_sphere = Props.unit_sphere(_vc, 8)
	_prism = Props.unit_prism(_vc)
	Props.daylight(parent, reduced_effects, 0.001, Color(0.76, 0.8, 0.8))
	parent.add_child(Props.ground(Color(0.27, 0.36, 0.17), Color(0.36, 0.4, 0.2)))
	var obstacles := Node3D.new()
	obstacles.name = "Obstacles"
	parent.add_child(obstacles)
	colliders = Props.Colliders.new(obstacles)
	var dirt := Props.flat_material(Color(0.55, 0.45, 0.32))
	var road := Props.ribbon(PackedVector2Array(_smooth(MAIN_ROAD)), 6.0, 0.03, dirt)
	road.name = "MainRoad"
	parent.add_child(road)
	for i in SIDE_PATHS.size():
		var path := Props.ribbon(PackedVector2Array(_smooth(SIDE_PATHS[i])), 3.0, 0.035, Props.flat_material(Color(0.58, 0.49, 0.36)))
		path.name = "Path%d" % i
		parent.add_child(path)
	_reserve(Vector2(route["spawn"].x, route["spawn"].z), 14.0)
	_reserve(Vector2(route["landing"].x, route["landing"].z), 14.0)
	_reserve(CAMP.get_center(), 48.0)
	_camp(route["landing"])
	_farmyard(route["spawn"])
	_water_tower(Vector3(48.0, 0.0, -118.0))
	_pond(Vector3(70.0, 0.0, -12.0))
	_village()
	_power_line()
	_orchard(Rect2(-175.0, -215.0, 70.0, 50.0))
	_fields()
	_scatter_trees()
	var props := Node3D.new()
	props.name = "Props"
	parent.add_child(props)
	batch.build(props)
	var house_node := Node3D.new()
	house_node.name = "Houses"
	parent.add_child(house_node)
	var facade := Props.facade_material(3.0, 4.2, false, Color(0.62, 0.6, 0.56))
	var wall_mesh := Props.unit_box(facade)
	var walls := Props.Batch.new()
	for i in houses.transforms.get("h", []).size():
		walls.add("HouseWalls", wall_mesh, houses.transforms["h"][i], houses.colors["h"][i])
	walls.build(house_node)
	stats["collision_shapes"] = colliders.shape_count
	stats["instances"] = batch.count() + walls.count()
	return {"area": AREA, "stats": stats}


## Catmull-Rom style smoothing so roads curve instead of zig-zagging.
func _smooth(points: Array) -> Array:
	var out := []
	for i in points.size() - 1:
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, points.size() - 1)]
		for k in 6:
			var t := k / 6.0
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(points[-1])
	return out


func _distance_to_roads(p: Vector2) -> float:
	var best := INF
	for line in [MAIN_ROAD] + SIDE_PATHS:
		for i in line.size() - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t))
	return best


func _free(p: Vector2, radius: float) -> bool:
	for taken in _taken:
		if p.distance_to(taken[0]) < radius + taken[1]:
			return false
	return true


func _reserve(p: Vector2, radius: float) -> void:
	_taken.append([p, radius])


# --- Houses ------------------------------------------------------------------------

func _village() -> void:
	var attempts := 0
	while stats["houses"] + stats["huts"] < 46 and attempts < 900:
		attempts += 1
		# Most houses near the centre and along the main road; some farther out.
		var anchor: Vector2 = MAIN_ROAD[rng.randi_range(2, 7)]
		if rng.randf() < 0.45:
			anchor = VILLAGE_CENTRE
		var p := anchor + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(9.0, 55.0)
		var road_distance := _distance_to_roads(p)
		if road_distance < 8.0 or road_distance > 40.0 or CAMP.grow(10.0).has_point(p):
			continue
		var kind := rng.randf()
		if kind < 0.18:
			_hut(p)
		elif kind < 0.6:
			_pitched_house(p)
		else:
			_flat_house(p)


func _pitched_house(p: Vector2) -> void:
	var size := Vector2(rng.randf_range(6.0, 10.0), rng.randf_range(5.0, 8.0))
	var wall_h := rng.randf_range(3.0, 4.2)
	var roof_h := rng.randf_range(1.6, 2.6)
	var yaw := rng.randf_range(-0.5, 0.5)
	if not _site(p, size, wall_h + roof_h):
		return
	var base := Vector3(p.x, 0, p.y)
	var color: Color = WALL_COLORS[rng.randi() % WALL_COLORS.size()]
	houses.add("h", _box, Props.place(base + Vector3(0, wall_h * 0.5, 0), Vector3(size.x, wall_h, size.y), yaw), color)
	batch.add("PitchedRoofs", _prism, Props.roof_transform(base + Vector3(0, wall_h + roof_h * 0.5, 0), size, roof_h, yaw),
		ROOF_COLORS[rng.randi() % ROOF_COLORS.size()])
	batch.add("Doors", _box, Props.place(base + Vector3(0, 1.0, 0) + Vector3(0, 0, size.y * 0.5 + 0.02).rotated(Vector3.UP, yaw),
		Vector3(1.0, 2.0, 0.06), yaw), Color(0.32, 0.22, 0.14))
	colliders.box("House", base + Vector3(0, (wall_h + roof_h) * 0.5, 0), Vector3(size.x, wall_h + roof_h, size.y), yaw)
	stats["houses"] += 1
	if rng.randf() < 0.45:
		_compound_wall(p, size, yaw)


func _flat_house(p: Vector2) -> void:
	var size := Vector2(rng.randf_range(7.0, 12.0), rng.randf_range(6.0, 10.0))
	var floors := 1 if rng.randf() < 0.55 else 2
	var h := floors * 3.0 + 0.3
	var yaw := rng.randf_range(-0.4, 0.4)
	var extra := 2.2 if floors == 2 else 1.6
	if not _site(p, size, h + extra):
		return
	var base := Vector3(p.x, 0, p.y)
	var color: Color = WALL_COLORS[rng.randi() % WALL_COLORS.size()]
	houses.add("h", _box, Props.place(base + Vector3(0, h * 0.5, 0), Vector3(size.x, h, size.y), yaw), color)
	batch.add("Parapets", _box, Props.place(base + Vector3(0, h + 0.35, 0), Vector3(size.x + 0.2, 0.7, size.y + 0.2), yaw), color.darkened(0.15))
	batch.add("Doors", _box, Props.place(base + Vector3(0, 1.0, 0) + Vector3(0, 0, size.y * 0.5 + 0.02).rotated(Vector3.UP, yaw),
		Vector3(1.1, 2.0, 0.06), yaw), Color(0.25, 0.28, 0.3))
	var top := base + Vector3(0, h, 0)
	if rng.randf() < 0.5:
		var tank := top + Vector3(size.x * 0.25, 0, -size.y * 0.2).rotated(Vector3.UP, yaw)
		batch.add("RoofTanks", _cyl, Props.place(tank + Vector3(0, 0.75, 0), Vector3(1.3, 1.5, 1.3)), Color(0.12, 0.12, 0.13))
	if floors == 2:
		batch.add("RoofStairs", _box, Props.place(top + Vector3(-size.x * 0.25, 1.1, size.y * 0.2).rotated(Vector3.UP, yaw), Vector3(2.4, 2.2, 2.4), yaw), color.darkened(0.1))
	colliders.box("House", base + Vector3(0, (h + extra) * 0.5, 0), Vector3(size.x, h + extra, size.y), yaw)
	stats["houses"] += 1
	if rng.randf() < 0.55:
		_compound_wall(p, size, yaw)


func _hut(p: Vector2) -> void:
	var r := rng.randf_range(2.2, 3.2)
	if not _site(p, Vector2(r * 2.0, r * 2.0), 5.5):
		return
	var base := Vector3(p.x, 0, p.y)
	batch.add("HutWalls", _cyl, Props.place(base + Vector3(0, 1.2, 0), Vector3(r * 2.0, 2.4, r * 2.0)), Color(0.66, 0.52, 0.36))
	batch.add("HutRoofs", _cone, Props.place(base + Vector3(0, 3.6, 0), Vector3(r * 2.5, 2.6, r * 2.5)), Color(0.62, 0.52, 0.3))
	colliders.box("Hut", base + Vector3(0, 2.4, 0), Vector3(r * 1.8, 4.8, r * 1.8))
	stats["huts"] += 1


## Reserves ground for a structure; false (and nothing placed) when it overlaps
## another or would block the route.
func _site(p: Vector2, size: Vector2, top: float) -> bool:
	var radius := size.length() * 0.5 + 2.5
	if not _free(p, radius):
		return false
	if corridor.blocks(Vector3(p.x, 0, p.y), size, top):
		stats["rejected"] += 1
		return false
	_reserve(p, radius)
	return true


## Low boundary wall around a house plot with an opening at the front.
func _compound_wall(p: Vector2, size: Vector2, yaw: float) -> void:
	var half := size * 0.5 + Vector2(3.0, 3.0)
	var h := 1.6
	var color := Color(0.62, 0.55, 0.45)
	var corners := [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if i == 2:
			# Front wall: leave a 3 m opening in the middle.
			_wall_piece(p, a, a.lerp(b, 0.4), h, yaw, color)
			_wall_piece(p, a.lerp(b, 0.6), b, h, yaw, color)
		else:
			_wall_piece(p, a, b, h, yaw, color)


func _wall_piece(origin: Vector2, a: Vector2, b: Vector2, h: float, yaw: float, color: Color) -> void:
	var a3 := Vector3(a.x, 0, a.y).rotated(Vector3.UP, yaw) + Vector3(origin.x, 0, origin.y)
	var b3 := Vector3(b.x, 0, b.y).rotated(Vector3.UP, yaw) + Vector3(origin.x, 0, origin.y)
	var mid := (a3 + b3) * 0.5
	var length := a3.distance_to(b3)
	var wall_yaw := atan2(-(b3 - a3).z, (b3 - a3).x)
	if corridor.blocks(mid, Vector2(length, 0.4), h):
		return
	batch.add("CompoundWalls", _box, Props.place(mid + Vector3(0, h * 0.5, 0), Vector3(length, h, 0.35), wall_yaw), color)
	colliders.box("Boundary wall", mid + Vector3(0, h * 0.5, 0), Vector3(length, h, 0.35), wall_yaw)


# --- Landmarks ---------------------------------------------------------------------

func _water_tower(at: Vector3) -> void:
	var p := Vector2(at.x, at.z)
	for offset in [Vector2.ZERO, Vector2(12, 0), Vector2(-12, 0), Vector2(0, 14), Vector2(18, 10)]:
		if not corridor.blocks(at + Vector3(offset.x, 0, offset.y), Vector2(9, 9), 19.5):
			at += Vector3(offset.x, 0, offset.y)
			break
	if corridor.blocks(at, Vector2(9, 9), 19.5):
		stats["rejected"] += 1
		return
	_reserve(Vector2(at.x, at.z), 8.0)
	var concrete := Color(0.68, 0.67, 0.64)
	for corner in [Vector3(-2.8, 0, -2.8), Vector3(2.8, 0, -2.8), Vector3(-2.8, 0, 2.8), Vector3(2.8, 0, 2.8)]:
		batch.add("TowerLegs", _box, Props.place(at + corner + Vector3(0, 7.0, 0), Vector3(0.5, 14.0, 0.5)), concrete)
		colliders.box("Water tower", at + corner + Vector3(0, 7.0, 0), Vector3(0.5, 14.0, 0.5))
	for level: float in [5.0, 10.0]:
		batch.add("TowerBraces", _box, Props.place(at + Vector3(0, level, 0), Vector3(6.1, 0.3, 6.1)), concrete.darkened(0.1))
	batch.add("TowerTank", _cyl, Props.place(at + Vector3(0, 16.5, 0), Vector3(8.0, 5.0, 8.0)), Color(0.78, 0.78, 0.74))
	batch.add("TowerTankTop", _cone, Props.place(at + Vector3(0, 19.4, 0), Vector3(8.2, 0.9, 8.2)), Color(0.6, 0.6, 0.58))
	colliders.box("Water tower", at + Vector3(0, 16.8, 0), Vector3(7.6, 5.6, 7.6))


func _pond(at: Vector3) -> void:
	_reserve(Vector2(at.x, at.z), 18.0)
	batch.add("PondBank", _cyl, Props.place(at + Vector3(0, 0.04, 0), Vector3(32, 0.06, 22)), Color(0.42, 0.36, 0.26), false)
	batch.add("PondWater", _cyl, Props.place(at + Vector3(0, 0.08, 0), Vector3(28, 0.04, 18)), Color(0.22, 0.32, 0.36), false)
	for i in 10:
		var angle := TAU * i / 10.0 + rng.randf_range(-0.2, 0.2)
		_bush(at + Vector3(cos(angle) * 16.0, 0, sin(angle) * 11.0))


func _farmyard(spawn: Vector3) -> void:
	var yard := Vector3(spawn.x + 26.0, 0, spawn.z + 6.0)
	if _site(Vector2(yard.x, yard.z), Vector2(12, 8), 6.0):
		batch.add("Sheds", _box, Props.place(yard + Vector3(0, 2.2, 0), Vector3(12, 4.4, 8)), Color(0.55, 0.42, 0.3))
		batch.add("ShedRoofs", _box, Props.place(yard + Vector3(0, 4.6, 0), Vector3(13, 0.3, 9), 0.0), Color(0.45, 0.47, 0.5))
		colliders.box("Farm shed", yard + Vector3(0, 2.4, 0), Vector3(12, 4.8, 8))
	for i in 5:
		var hay := spawn + Vector3(-22.0 + i * 4.0, 0, 16.0 + rng.randf_range(-2, 2))
		if corridor.blocks(hay, Vector2(3, 3), 2.8):
			continue
		batch.add("Haystacks", _cone, Props.place(hay + Vector3(0, 1.4, 0), Vector3(3.2, 2.8, 3.2)), Color(0.8, 0.68, 0.32))
	# Cattle shelter: posts and a roof.
	var shelter := spawn + Vector3(-24.0, 0, -6.0)
	if _site(Vector2(shelter.x, shelter.z), Vector2(10, 6), 3.6):
		for corner in [Vector3(-4.6, 0, -2.6), Vector3(4.6, 0, -2.6), Vector3(-4.6, 0, 2.6), Vector3(4.6, 0, 2.6)]:
			batch.add("ShelterPosts", _box, Props.place(shelter + corner + Vector3(0, 1.6, 0), Vector3(0.2, 3.2, 0.2)), Color(0.4, 0.3, 0.2))
		batch.add("ShelterRoofs", _box, Props.place(shelter + Vector3(0, 3.3, 0), Vector3(10.4, 0.2, 6.4)), Color(0.5, 0.5, 0.48))
		colliders.box("Cattle shelter", shelter + Vector3(0, 1.7, 0), Vector3(10, 3.4, 6))
	# Launch pad: packed-earth square with a white ring.
	batch.add("LaunchArea", _cyl, Props.place(spawn + Vector3(0, 0.02, 0), Vector3(9, 0.02, 9)), Color(0.5, 0.44, 0.34), false)


## Utility poles along the main road, offset to one side, with three sagging wires
## between neighbouring poles. Poles and wires have collision (a flight hazard).
func _power_line() -> void:
	var points := _smooth(MAIN_ROAD)
	var poles: Array = []
	var travelled := 0.0
	var next := 0.0
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length := a.distance_to(b)
		while next <= travelled + length:
			var p := a.lerp(b, (next - travelled) / length)
			var dir := (b - a).normalized()
			var side := Vector2(-dir.y, dir.x) * 7.0
			poles.append(Vector3(p.x + side.x, 0, p.y + side.y))
			next += 38.0
		travelled += length
	var placed: Array = []
	for pole in poles:
		if CAMP.grow(6.0).has_point(Vector2(pole.x, pole.z)) or corridor.blocks(pole, Vector2(1.6, 1.6), 9.4):
			placed.append(null)
			stats["rejected"] += 1
			continue
		batch.add("UtilityPoles", _cyl, Props.place(pole + Vector3(0, 4.5, 0), Vector3(0.3, 9.0, 0.3)), Color(0.42, 0.4, 0.38))
		batch.add("CrossArms", _box, Props.place(pole + Vector3(0, 8.7, 0), Vector3(1.8, 0.15, 0.15)), Color(0.35, 0.3, 0.25))
		colliders.box("Utility pole", pole + Vector3(0, 4.5, 0), Vector3(0.35, 9.0, 0.35))
		placed.append(pole)
		stats["poles"] += 1
	var wire_color := Color(0.1, 0.1, 0.1)
	for i in placed.size() - 1:
		if placed[i] == null or placed[i + 1] == null:
			continue
		for offset: float in [-0.8, 0.0, 0.8]:
			var a: Vector3 = placed[i] + Vector3(offset, 8.8, 0)
			var b: Vector3 = placed[i + 1] + Vector3(offset, 8.8, 0)
			var mid := (a + b) * 0.5 - Vector3(0, 0.7, 0)
			for pair in [[a, mid], [mid, b]]:
				batch.add("Wires", _box, Props.span(pair[0], pair[1], 0.05), wire_color, false)
				var shape := Props.span(pair[0], pair[1], 1.0)
				colliders.oriented("Power line", Transform3D(shape.basis.orthonormalized(), shape.origin), Vector3(0.12, 0.12, (pair[0] as Vector3).distance_to(pair[1])))


func _camp(landing: Vector3) -> void:
	var olive := Color(0.36, 0.38, 0.24)
	batch.add("CampGround", _box, Props.place(Vector3(CAMP.get_center().x, 0.03, CAMP.get_center().y), Vector3(CAMP.size.x, 0.04, CAMP.size.y)), Color(0.55, 0.5, 0.4), false)
	# Fence with a gate gap on the south side facing the road.
	var corners := [CAMP.position, Vector2(CAMP.end.x, CAMP.position.y), CAMP.end, Vector2(CAMP.position.x, CAMP.end.y)]
	var gate := Vector2(122.0, CAMP.end.y)
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var panels := int(a.distance_to(b) / 5.0)
		for k in panels:
			var p0 := a.lerp(b, float(k) / panels)
			var p1 := a.lerp(b, float(k + 1) / panels)
			var mid := (p0 + p1) * 0.5
			if mid.distance_to(gate) < 5.0:
				continue
			var size := Vector3(p0.distance_to(p1), 2.4, 0.08) if absf(a.y - b.y) < 0.1 else Vector3(0.08, 2.4, p0.distance_to(p1))
			if corridor.blocks(Vector3(mid.x, 0, mid.y), Vector2(size.x, size.z), 2.4):
				continue
			batch.add("CampFence", _box, Props.place(Vector3(mid.x, 1.2, mid.y), size), Color(0.45, 0.47, 0.42, 1.0))
			batch.add("CampFencePosts", _box, Props.place(Vector3(p0.x, 1.3, p0.y), Vector3(0.15, 2.6, 0.15)), Color(0.3, 0.3, 0.28))
			colliders.box("Camp fence", Vector3(mid.x, 1.2, mid.y), size)
	for s: float in [-1.0, 1.0]:
		batch.add("GatePosts", _box, Props.place(Vector3(gate.x + s * 4.5, 1.6, gate.y), Vector3(0.5, 3.2, 0.5)), olive.darkened(0.2))
	# Rows of tents in the west half, away from the helipad.
	for row in 3:
		for col in 4:
			var at := Vector3(CAMP.position.x + 8.0 + col * 8.0, 0, CAMP.position.y + 10.0 + row * 9.0)
			if corridor.blocks(at, Vector2(6, 4), 3.0):
				continue
			batch.add("Tents", _prism, Props.roof_transform(at + Vector3(0, 1.4, 0), Vector2(6.0, 4.0), 2.8), olive.lightened(rng.randf_range(-0.05, 0.05)))
			colliders.box("Tent", at + Vector3(0, 1.4, 0), Vector3(6.0, 2.8, 4.0))
	# Watchtower in the north-east corner, flagpole near the gate.
	var tower := Vector3(CAMP.end.x - 5.0, 0, CAMP.position.y + 5.0)
	for corner in [Vector3(-1.5, 0, -1.5), Vector3(1.5, 0, -1.5), Vector3(-1.5, 0, 1.5), Vector3(1.5, 0, 1.5)]:
		batch.add("WatchtowerLegs", _box, Props.place(tower + corner + Vector3(0, 3.5, 0), Vector3(0.25, 7.0, 0.25)), Color(0.45, 0.33, 0.2))
	batch.add("WatchtowerDeck", _box, Props.place(tower + Vector3(0, 7.2, 0), Vector3(4.0, 0.3, 4.0)), Color(0.45, 0.33, 0.2))
	batch.add("WatchtowerRoof", _box, Props.place(tower + Vector3(0, 9.4, 0), Vector3(4.4, 0.25, 4.4)), olive)
	colliders.box("Watchtower", tower + Vector3(0, 4.8, 0), Vector3(4.0, 9.6, 4.0))
	var flag := Vector3(gate.x + 9.0, 0, gate.y - 5.0)
	if not corridor.blocks(flag, Vector2(1, 1), 10.0):
		batch.add("Flagpole", _cyl, Props.place(flag + Vector3(0, 5.0, 0), Vector3(0.12, 10.0, 0.12)), Color(0.75, 0.75, 0.75))
		batch.add("Flag", _box, Props.place(flag + Vector3(0.9, 9.2, 0), Vector3(1.6, 1.0, 0.03)), Color(0.85, 0.55, 0.15))
		colliders.box("Flagpole", flag + Vector3(0, 5.0, 0), Vector3(0.2, 10.0, 0.2))
	# Sandbag walls at the gate and two parked trucks.
	for s: float in [-1.0, 1.0]:
		var bags := Vector3(gate.x + s * 8.0, 0, gate.y - 3.0)
		for layer in 3:
			batch.add("Sandbags", _box, Props.place(bags + Vector3(0, 0.22 + layer * 0.36, 0), Vector3(4.0, 0.36, 0.7)), Color(0.6, 0.55, 0.4))
		colliders.box("Sandbag wall", bags + Vector3(0, 0.55, 0), Vector3(4.0, 1.1, 0.7))
	for i in 2:
		var truck := Vector3(CAMP.end.x - 10.0, 0, CAMP.end.y - 10.0 - i * 6.0)
		if corridor.blocks(truck, Vector2(7, 3), 3.2):
			continue
		batch.add("Trucks", _box, Props.place(truck + Vector3(0, 1.4, 0), Vector3(7.0, 2.2, 2.5), PI / 2.0), olive.darkened(0.15))
		batch.add("TruckCabs", _box, Props.place(truck + Vector3(0, 1.7, -3.9), Vector3(2.4, 2.6, 1.6)), olive.darkened(0.3))
		colliders.box("Truck", truck + Vector3(0, 1.5, -0.5), Vector3(2.5, 3.0, 8.0))
	# Helipad: concrete disc with an H and corner markers (ground decals, no collision).
	batch.add("Helipad", _cyl, Props.place(landing + Vector3(0, 0.05, 0), Vector3(12.0, 0.04, 12.0)), Color(0.62, 0.62, 0.6), false)
	for piece in [[Vector3(-1.2, 0, 0), Vector3(0.5, 0.02, 4.0)], [Vector3(1.2, 0, 0), Vector3(0.5, 0.02, 4.0)], [Vector3.ZERO, Vector3(2.4, 0.02, 0.5)]]:
		batch.add("HelipadMarks", _box, Props.place(landing + piece[0] + Vector3(0, 0.08, 0), piece[1]), Color(0.95, 0.95, 0.9), false)


func _orchard(rect: Rect2) -> void:
	var x := rect.position.x
	while x < rect.end.x:
		var z := rect.position.y
		while z < rect.end.y:
			var at := Vector3(x + rng.randf_range(-0.6, 0.6), 0, z + rng.randf_range(-0.6, 0.6))
			_tree(at, rng.randf_range(4.0, 5.5), true)
			z += 7.0
		x += 7.0


func _fields() -> void:
	var cell := 62.0
	var x := AREA.position.x + 10.0
	while x < AREA.end.x - cell:
		var z := AREA.position.y + 10.0
		while z < AREA.end.y - cell:
			var centre := Vector2(x + cell * 0.5, z + cell * 0.5)
			var ok := _distance_to_roads(centre) > cell * 0.55 and centre.distance_to(VILLAGE_CENTRE) > 85.0 \
				and not CAMP.grow(30.0).intersects(Rect2(x, z, cell, cell)) and _free(centre, 30.0) \
				and not Rect2(-175.0, -215.0, 70.0, 50.0).grow(5.0).intersects(Rect2(x, z, cell, cell))
			if ok and rng.randf() < 0.85:
				_field(centre, Vector2(cell - rng.randf_range(4.0, 12.0), cell - rng.randf_range(4.0, 12.0)), rng.randf_range(-0.25, 0.25))
			z += cell
		x += cell


## One crop field: soil base, crop rows across it and earth bunds around it.
func _field(centre: Vector2, size: Vector2, yaw: float) -> void:
	var crop: Color = CROPS[rng.randi() % CROPS.size()]
	var base := Vector3(centre.x, 0, centre.y)
	batch.add("FieldSoil", _box, Props.place(base + Vector3(0, 0.02, 0), Vector3(size.x, 0.03, size.y), yaw), Color(0.42, 0.34, 0.24), false)
	var ploughed := crop.r < 0.5 and crop.g < 0.4
	var spacing := 1.6
	var offset := -size.x * 0.5 + spacing * 0.5
	while offset < size.x * 0.5:
		var row := base + Vector3(offset, 0.0, 0).rotated(Vector3.UP, yaw)
		batch.add("CropRows", _box, Props.place(row + Vector3(0, 0.12 if ploughed else 0.3, 0), Vector3(0.7, 0.18 if ploughed else 0.55, size.y - 1.0), yaw),
			crop.lightened(rng.randf_range(-0.04, 0.04)), false)
		offset += spacing
	for s: float in [-1.0, 1.0]:
		batch.add("Bunds", _box, Props.place(base + Vector3(0, 0.2, s * size.y * 0.5).rotated(Vector3.UP, yaw), Vector3(size.x, 0.4, 0.6), yaw), Color(0.46, 0.38, 0.26), false)
		batch.add("Bunds", _box, Props.place(base + Vector3(s * size.x * 0.5, 0.2, 0).rotated(Vector3.UP, yaw), Vector3(0.6, 0.4, size.y), yaw), Color(0.46, 0.38, 0.26), false)
	stats["fields"] += 1


func _scatter_trees() -> void:
	# Shade trees around the village and a line of trees along parts of the main road.
	for i in 90:
		var p := VILLAGE_CENTRE + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * rng.randf_range(10.0, 120.0)
		if _distance_to_roads(p) < 5.0 or not _free(p, 4.0) or CAMP.grow(6.0).has_point(p):
			continue
		_tree(Vector3(p.x, 0, p.y), rng.randf_range(6.0, 11.0), false)
	for i in range(1, MAIN_ROAD.size() - 2):
		var a: Vector2 = MAIN_ROAD[i]
		var b: Vector2 = MAIN_ROAD[i + 1]
		var dir := (b - a).normalized()
		for k in 3:
			var p := a.lerp(b, 0.2 + k * 0.3) + Vector2(dir.y, -dir.x) * 6.5
			if _free(p, 3.0):
				_tree(Vector3(p.x, 0, p.y), rng.randf_range(7.0, 10.0), false)
	for i in 160:
		var p := Vector2(rng.randf_range(AREA.position.x, AREA.end.x), rng.randf_range(AREA.position.y, AREA.end.y))
		if _distance_to_roads(p) > 4.0 and _free(p, 2.0):
			_bush(Vector3(p.x, 0, p.y))


func _tree(at: Vector3, height: float, fruit: bool) -> void:
	var crown := height * (0.55 if fruit else 0.5)
	if corridor.blocks(at, Vector2(crown, crown), height):
		stats["rejected"] += 1
		return
	_reserve(Vector2(at.x, at.z), crown * 0.4)
	batch.add("TreeTrunks", _cyl, Props.place(at + Vector3(0, height * 0.3, 0), Vector3(0.4, height * 0.6, 0.4)), Color(0.35, 0.26, 0.17))
	var color := Color(0.24, 0.4, 0.16) if fruit else Color(0.2, 0.36, 0.15)
	if not fruit and rng.randf() < 0.3:
		# Tall narrow tree for variety.
		batch.add("TallCrowns", _cone, Props.place(at + Vector3(0, height * 0.62, 0), Vector3(crown * 0.7, height * 0.8, crown * 0.7)), color.darkened(0.1))
	else:
		batch.add("TreeCrowns", _sphere, Props.place(at + Vector3(0, height * 0.7, 0), Vector3(crown, height * 0.55, crown)), color.lightened(rng.randf_range(-0.05, 0.1)))
	if height > 5.0:
		colliders.box("Tree", at + Vector3(0, height * 0.55, 0), Vector3(crown * 0.7, height * 0.9, crown * 0.7))
	stats["trees"] += 1


func _bush(at: Vector3) -> void:
	var size := rng.randf_range(1.0, 2.2)
	batch.add("Bushes", _sphere, Props.place(at + Vector3(0, size * 0.35, 0), Vector3(size, size * 0.8, size)), Color(0.28, 0.4, 0.18).lightened(rng.randf_range(-0.05, 0.08)), false)
