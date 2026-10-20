extends RefCounted
## Procedural fictional city for flight training. Layout: a street grid with uneven
## block sizes, a wide main avenue (tree median) and main street; blocks are split
## into lots of different sizes holding buildings of varied height, colour and roof
## equipment, with special blocks for the launch depot, a park, a walled compound, a
## construction site with a crane, and the landing plaza. Streets carry lane markings,
## crossings, streetlights, parked cars and signs.
## Deterministic for a given seed. Props that would block the mission route are not
## placed (route_corridor.gd), so every mission stays flyable.

const Props := preload("res://scripts/world/props.gd")
const RouteCorridor := preload("res://scripts/world/route_corridor.gd")

## Street centre lines and widths (m). North-south streets at x, east-west at z.
const X_STREETS := [-130.0, -50.0, 30.0, 110.0]
const X_WIDTHS := [14.0, 14.0, 20.0, 14.0]
const Z_STREETS := [20.0, -60.0, -150.0, -230.0, -310.0]
const Z_WIDTHS := [14.0, 14.0, 20.0, 14.0, 14.0]
const X_BOUNDS := [-190.0, 170.0]
const Z_BOUNDS := [70.0, -360.0]
const SIDEWALK := 3.0
const FLOOR := 3.2
const AREA := Rect2(-200.0, -370.0, 380.0, 450.0)

## Special uses keyed by block index "ix,iz" (block between street ix-1..ix and iz-1..iz).
const SPECIAL := {"1,1": "depot", "2,2": "park", "1,3": "compound", "3,2": "construction", "3,4": "plaza"}

const WALL_COLORS := [Color(0.72, 0.68, 0.6), Color(0.62, 0.6, 0.58), Color(0.78, 0.74, 0.66), Color(0.55, 0.5, 0.46),
	Color(0.68, 0.62, 0.52), Color(0.5, 0.55, 0.58), Color(0.82, 0.8, 0.76), Color(0.6, 0.5, 0.42)]
const CAR_COLORS := [Color(0.75, 0.75, 0.78), Color(0.15, 0.16, 0.18), Color(0.55, 0.12, 0.1), Color(0.85, 0.85, 0.82),
	Color(0.2, 0.3, 0.5), Color(0.35, 0.37, 0.4), Color(0.85, 0.7, 0.2), Color(0.25, 0.4, 0.3)]

var rng := RandomNumberGenerator.new()
var corridor: RouteCorridor
var batch := Props.Batch.new()
var buildings := Props.Batch.new()
var colliders: Props.Colliders
var stats := {"buildings": 0, "streetlights": 0, "cars": 0, "trees": 0, "rejected": 0}

var _vc: StandardMaterial3D
var _box: BoxMesh
var _cyl: CylinderMesh
var _sphere: SphereMesh
var _lamp: BoxMesh


## Builds the city under `parent`. `route` = {spawn, checkpoints, landing} (Vector3s).
static func build(parent: Node3D, route: Dictionary, seed: int, reduced_effects := false) -> Dictionary:
	var builder = load("res://scripts/world/city_builder.gd").new()
	return builder._build(parent, route, seed, reduced_effects)


func _build(parent: Node3D, route: Dictionary, seed: int, reduced_effects: bool) -> Dictionary:
	rng.seed = seed
	corridor = RouteCorridor.new(route["spawn"], route["checkpoints"], route["landing"])
	_vc = Props.vertex_color_material()
	_box = Props.unit_box(_vc)
	_cyl = Props.unit_cylinder(_vc, 10)
	_sphere = Props.unit_sphere(_vc, 8)
	_lamp = Props.unit_box(Props.vertex_color_material(0.4, 2.5))
	Props.daylight(parent, reduced_effects, 0.0012, Color(0.72, 0.78, 0.84))
	parent.add_child(Props.ground(Color(0.3, 0.31, 0.3), Color(0.36, 0.36, 0.34)))
	var obstacles := Node3D.new()
	obstacles.name = "Obstacles"
	parent.add_child(obstacles)
	colliders = Props.Colliders.new(obstacles)
	_streets()
	for ix in X_STREETS.size() + 1:
		for iz in Z_STREETS.size() + 1:
			var rect := _block_rect(ix, iz)
			batch.add("Sidewalks", _box, Props.place(Vector3(rect.get_center().x, 0.07, rect.get_center().y),
				Vector3(rect.size.x + SIDEWALK * 2.0, 0.14, rect.size.y + SIDEWALK * 2.0)), Color(0.48, 0.47, 0.45), false)
			match SPECIAL.get("%d,%d" % [ix, iz], "lots"):
				"depot":
					_depot(rect)
				"park":
					_park(rect)
				"compound":
					_compound(rect)
				"construction":
					_construction(rect)
				"plaza":
					_plaza(rect)
				_:
					_lots(rect)
	var props := Node3D.new()
	props.name = "Props"
	parent.add_child(props)
	batch.build(props)
	var facade := Props.facade_material(FLOOR, 3.0, true, Color(0.25, 0.25, 0.26))
	var building_mesh := Props.unit_box(facade)
	var building_node := Node3D.new()
	building_node.name = "Buildings"
	parent.add_child(building_node)
	var facade_batch := Props.Batch.new()
	for i in buildings.transforms.get("b", []).size():
		facade_batch.add("Buildings", building_mesh, buildings.transforms["b"][i], buildings.colors["b"][i])
	facade_batch.build(building_node)
	stats["collision_shapes"] = colliders.shape_count
	stats["instances"] = batch.count() + facade_batch.count()
	return {"area": AREA, "stats": stats}


func _block_rect(ix: int, iz: int) -> Rect2:
	var xs := [X_BOUNDS[0]] + X_STREETS + [X_BOUNDS[1]]
	var zs := [Z_BOUNDS[0]] + Z_STREETS + [Z_BOUNDS[1]]
	var west: float = xs[ix] + (X_WIDTHS[ix - 1] * 0.5 + SIDEWALK if ix > 0 else 0.0)
	var east: float = xs[ix + 1] - (X_WIDTHS[ix] * 0.5 + SIDEWALK if ix < X_STREETS.size() else 0.0)
	var south: float = zs[iz] - (Z_WIDTHS[iz - 1] * 0.5 + SIDEWALK if iz > 0 else 0.0)
	var north: float = zs[iz + 1] + (Z_WIDTHS[iz] * 0.5 + SIDEWALK if iz < Z_STREETS.size() else 0.0)
	return Rect2(west, north, east - west, south - north)


# --- Streets ---------------------------------------------------------------------

func _streets() -> void:
	var length_x: float = Z_BOUNDS[0] - Z_BOUNDS[1]
	var length_z: float = X_BOUNDS[1] - X_BOUNDS[0]
	var mid_z: float = (Z_BOUNDS[0] + Z_BOUNDS[1]) * 0.5
	var mid_x: float = (X_BOUNDS[0] + X_BOUNDS[1]) * 0.5
	var asphalt := Color(0.2, 0.21, 0.22)
	for i in X_STREETS.size():
		batch.add("Roads", _box, Props.place(Vector3(X_STREETS[i], 0.01, mid_z), Vector3(X_WIDTHS[i], 0.02, length_x)), asphalt, false)
		_street_furniture(true, X_STREETS[i], X_WIDTHS[i], Z_BOUNDS[1], Z_BOUNDS[0], Z_STREETS)
	for i in Z_STREETS.size():
		batch.add("Roads", _box, Props.place(Vector3(mid_x, 0.012, Z_STREETS[i]), Vector3(length_z, 0.02, Z_WIDTHS[i])), asphalt, false)
		_street_furniture(false, Z_STREETS[i], Z_WIDTHS[i], X_BOUNDS[0], X_BOUNDS[1], X_STREETS)
	for i in X_STREETS.size():
		for j in Z_STREETS.size():
			_crossings(X_STREETS[i], Z_STREETS[j], X_WIDTHS[i], Z_WIDTHS[j])
	_gantry(Vector3(-50.0, 0.0, -105.0), X_WIDTHS[1])


## Lane markings, streetlights and parked cars along one street. `along_x` is false
## for north-south streets (they run along z).
func _street_furniture(north_south: bool, centre: float, width: float, from: float, to: float, crossing: Array) -> void:
	var white := Color(0.92, 0.92, 0.88)
	var near_crossing := func(p: float) -> bool:
		for c in crossing:
			if absf(p - c) < 14.0:
				return true
		return false
	var p := from + 4.0
	while p < to - 4.0:
		if not near_crossing.call(p):
			var at := Vector3(centre, 0.025, p) if north_south else Vector3(p, 0.025, centre)
			var size := Vector3(0.15, 0.02, 3.0) if north_south else Vector3(3.0, 0.02, 0.15)
			if width >= 20.0:
				# Main roads: a planted median instead of a dashed line.
				var median := Vector3(2.0, 0.25, 9.0) if north_south else Vector3(9.0, 0.25, 2.0)
				batch.add("Medians", _box, Props.place(at + Vector3(0, 0.1, 0), median), Color(0.3, 0.42, 0.24), false)
			else:
				batch.add("LaneMarkings", _box, Props.place(at, size), white, false)
		p += 9.0
	# Streetlights on both sides, arms pointing over the road.
	p = from + 16.0
	while p < to - 8.0:
		if not near_crossing.call(p):
			for s: float in [-1.0, 1.0]:
				var offset := (width * 0.5 + 0.8) * s
				var base := Vector3(centre + offset, 0.0, p) if north_south else Vector3(p, 0.0, centre + offset)
				_streetlight(base, Vector3(-s, 0, 0) if north_south else Vector3(0, 0, -s))
		p += 32.0
	# Parked cars along both kerbs.
	p = from + 6.0
	while p < to - 6.0:
		if not near_crossing.call(p) and rng.randf() < 0.55:
			var s := -1.0 if rng.randf() < 0.5 else 1.0
			var offset := (width * 0.5 - 1.4) * s
			var at := Vector3(centre + offset, 0.0, p) if north_south else Vector3(p, 0.0, centre + offset)
			_car(at, 0.0 if north_south else PI / 2.0)
		p += rng.randf_range(6.0, 9.0)


func _streetlight(base: Vector3, toward_road: Vector3) -> void:
	if corridor.blocks(base, Vector2(2.0, 2.0), 8.2):
		stats["rejected"] += 1
		return
	var pole := Color(0.32, 0.34, 0.36)
	batch.add("LightPoles", _cyl, Props.place(base + Vector3(0, 4.0, 0), Vector3(0.22, 8.0, 0.22)), pole)
	var arm_centre := base + Vector3(0, 7.9, 0) + toward_road * 0.9
	var arm_size := Vector3(1.8, 0.12, 0.12) if absf(toward_road.x) > 0.5 else Vector3(0.12, 0.12, 1.8)
	batch.add("LightArms", _box, Props.place(arm_centre, arm_size), pole)
	batch.add("Lamps", _lamp, Props.place(base + Vector3(0, 7.75, 0) + toward_road * 1.7, Vector3(0.6, 0.18, 0.35)), Color(1.0, 0.95, 0.8), false)
	colliders.box("Streetlight", base + Vector3(0, 4.0, 0), Vector3(0.35, 8.0, 0.35))
	stats["streetlights"] += 1


func _car(at: Vector3, yaw: float) -> void:
	var color: Color = CAR_COLORS[rng.randi() % CAR_COLORS.size()]
	var length := rng.randf_range(3.9, 4.6)
	batch.add("CarBodies", _box, Props.place(at + Vector3(0, 0.55, 0), Vector3(1.8, 0.75, length), yaw), color)
	batch.add("CarCabins", _box, Props.place(at + Vector3(0, 1.2, -0.1), Vector3(1.6, 0.6, length * 0.5), yaw), color.darkened(0.35))
	stats["cars"] += 1


func _crossings(x: float, z: float, wx: float, wz: float) -> void:
	var white := Color(0.9, 0.9, 0.86)
	for s: float in [-1.0, 1.0]:
		# Stripes across the north-south street just outside the intersection, and vice versa.
		var zc := z + s * (wz * 0.5 + 2.2)
		var stripe := -wx * 0.5 + 0.8
		while stripe < wx * 0.5 - 0.5:
			batch.add("Crossings", _box, Props.place(Vector3(x + stripe, 0.026, zc), Vector3(0.55, 0.02, 3.0)), white, false)
			stripe += 1.2
		var xc := x + s * (wx * 0.5 + 2.2)
		stripe = -wz * 0.5 + 0.8
		while stripe < wz * 0.5 - 0.5:
			batch.add("Crossings", _box, Props.place(Vector3(xc, 0.026, z + stripe), Vector3(3.0, 0.02, 0.55)), white, false)
			stripe += 1.2
	# A traffic sign on one corner of every intersection.
	var corner := Vector3(x + wx * 0.5 + 1.2, 0.0, z + wz * 0.5 + 1.2)
	batch.add("SignPoles", _cyl, Props.place(corner + Vector3(0, 1.5, 0), Vector3(0.1, 3.0, 0.1)), Color(0.4, 0.42, 0.44))
	batch.add("SignPlates", _box, Props.place(corner + Vector3(0, 2.8, 0), Vector3(0.8, 0.8, 0.06)), Color(0.15, 0.35, 0.65))


## Overhead direction-sign gantry across a north-south street (a low hazard to fly over).
func _gantry(at: Vector3, width: float) -> void:
	var grey := Color(0.45, 0.47, 0.5)
	for s: float in [-1.0, 1.0]:
		var post := at + Vector3(s * (width * 0.5 + 0.6), 3.5, 0)
		batch.add("GantryPosts", _box, Props.place(post, Vector3(0.4, 7.0, 0.4)), grey)
		colliders.box("Sign gantry", post, Vector3(0.4, 7.0, 0.4))
	batch.add("GantryBeams", _box, Props.place(at + Vector3(0, 6.8, 0), Vector3(width + 1.6, 0.4, 0.4)), grey)
	batch.add("GantrySigns", _box, Props.place(at + Vector3(0, 6.1, 0.25), Vector3(width * 0.7, 1.6, 0.08)), Color(0.1, 0.4, 0.25))
	colliders.box("Sign gantry", at + Vector3(0, 6.4, 0), Vector3(width + 1.6, 1.4, 0.6))


# --- Blocks ----------------------------------------------------------------------

## Splits a block into lots and puts a building (or a small car park) on each.
func _lots(rect: Rect2) -> void:
	var lots: Array = []
	_split(rect, lots, 0)
	var centre := Vector2(30.0, -150.0)
	for lot in lots:
		var r: Rect2 = lot
		if r.size.x < 9.0 or r.size.y < 9.0:
			continue
		if rng.randf() < 0.1:
			_car_park(r)
			continue
		var setback := rng.randf_range(0.6, 2.5)
		var footprint := Vector2(r.size.x - setback * 2.0, r.size.y - setback * 2.0)
		var distance := r.get_center().distance_to(centre)
		var floors := rng.randi_range(2, 5)
		if distance < 140.0:
			floors = rng.randi_range(4, 9)
			if rng.randf() < 0.25 and footprint.x > 14.0 and footprint.y > 14.0:
				floors = rng.randi_range(10, 16)
		_building(Vector3(r.get_center().x, 0.0, r.get_center().y), footprint, floors)


func _split(rect: Rect2, out: Array, depth: int) -> void:
	var longer := maxf(rect.size.x, rect.size.y)
	if (longer < 34.0 and depth > 0) or depth > 6:
		out.append(rect)
		return
	var cut := rng.randf_range(0.35, 0.65)
	if rect.size.x >= rect.size.y:
		var w := rect.size.x * cut
		_split(Rect2(rect.position, Vector2(w, rect.size.y)), out, depth + 1)
		_split(Rect2(rect.position + Vector2(w, 0), Vector2(rect.size.x - w, rect.size.y)), out, depth + 1)
	else:
		var h := rect.size.y * cut
		_split(Rect2(rect.position, Vector2(rect.size.x, h)), out, depth + 1)
		_split(Rect2(rect.position + Vector2(0, h), Vector2(rect.size.x, rect.size.y - h)), out, depth + 1)


func _building(base: Vector3, footprint: Vector2, floors: int) -> void:
	var height := floors * FLOOR + rng.randf_range(0.0, 1.2)
	var roof_extra := 0.0
	var big := footprint.x > 12.0 and footprint.y > 12.0
	if big:
		roof_extra = 3.5
	while floors > 2 and corridor.blocks(base, footprint, height + roof_extra):
		floors -= 2
		height = floors * FLOOR
	if corridor.blocks(base, footprint, height + roof_extra):
		stats["rejected"] += 1
		return
	var color: Color = WALL_COLORS[rng.randi() % WALL_COLORS.size()]
	color = color.lightened(rng.randf_range(-0.08, 0.08))
	buildings.add("b", _box, Props.place(base + Vector3(0, height * 0.5, 0), Vector3(footprint.x, height, footprint.y)), color)
	colliders.box("Building", base + Vector3(0, height * 0.5, 0), Vector3(footprint.x, height, footprint.y))
	stats["buildings"] += 1
	# Parapet.
	batch.add("Parapets", _box, Props.place(base + Vector3(0, height + 0.4, 0), Vector3(footprint.x + 0.3, 0.8, footprint.y + 0.3)), color.darkened(0.2))
	if not big:
		return
	var top := base + Vector3(0, height, 0)
	if rng.randf() < 0.7:
		var tank := top + Vector3(rng.randf_range(-0.25, 0.25) * footprint.x, 0, rng.randf_range(-0.25, 0.25) * footprint.y)
		var radius := rng.randf_range(1.0, 1.6)
		batch.add("TankStands", _box, Props.place(tank + Vector3(0, 0.6, 0), Vector3(radius * 1.6, 1.2, radius * 1.6)), Color(0.35, 0.33, 0.3))
		batch.add("WaterTanks", _cyl, Props.place(tank + Vector3(0, 2.2, 0), Vector3(radius * 2.0, 2.0, radius * 2.0)),
			[Color(0.15, 0.17, 0.2), Color(0.75, 0.75, 0.72), Color(0.3, 0.42, 0.6)][rng.randi() % 3])
		colliders.box("Rooftop water tank", tank + Vector3(0, 1.6, 0), Vector3(radius * 2.0, 3.2, radius * 2.0))
	for i in rng.randi_range(1, 3):
		var unit := top + Vector3(rng.randf_range(-0.35, 0.35) * footprint.x, 0.55, rng.randf_range(-0.35, 0.35) * footprint.y)
		batch.add("RooftopUnits", _box, Props.place(unit, Vector3(1.6, 1.1, 1.2), rng.randf() * PI), Color(0.7, 0.71, 0.7))
	var stair := top + Vector3(-footprint.x * 0.3, 1.4, footprint.y * 0.3)
	batch.add("StairHouses", _box, Props.place(stair, Vector3(3.0, 2.8, 3.0)), color.darkened(0.15))
	if rng.randf() < 0.15:
		# Rooftop billboard on two posts.
		var board := top + Vector3(0, 4.0, 0)
		batch.add("BillboardPosts", _box, Props.place(board + Vector3(0, -1.8, 0), Vector3(0.3, 3.0, 0.3)), Color(0.3, 0.3, 0.3))
		batch.add("Billboards", _box, Props.place(board, Vector3(minf(footprint.x * 0.8, 10.0), 3.0, 0.2)),
			[Color(0.75, 0.25, 0.2), Color(0.2, 0.45, 0.7), Color(0.85, 0.7, 0.25)][rng.randi() % 3])
		colliders.box("Rooftop billboard", board, Vector3(minf(footprint.x * 0.8, 10.0), 3.0, 0.4))


func _car_park(rect: Rect2) -> void:
	batch.add("Paving", _box, Props.place(Vector3(rect.get_center().x, 0.15, rect.get_center().y), Vector3(rect.size.x, 0.02, rect.size.y)), Color(0.3, 0.3, 0.31), false)
	var x := rect.position.x + 2.0
	while x < rect.end.x - 2.0:
		if rng.randf() < 0.7:
			_car(Vector3(x, 0.15, rect.get_center().y + rng.randf_range(-2.0, 2.0)), 0.0)
		x += 2.8


func _depot(rect: Rect2) -> void:
	batch.add("Paving", _box, Props.place(Vector3(rect.get_center().x, 0.15, rect.get_center().y), Vector3(rect.size.x, 0.02, rect.size.y)), Color(0.36, 0.36, 0.35), false)
	_fence(rect, Color(0.4, 0.42, 0.4), 2.2, "Depot fence")
	# Rows of shipping containers and two sheds along the edges.
	var z := rect.position.y + 4.0
	while z < rect.end.y - 4.0:
		var at := Vector3(rect.position.x + 5.0, 0.0, z)
		if not corridor.blocks(at, Vector2(2.6, 6.2), 2.7):
			batch.add("Containers", _box, Props.place(at + Vector3(0, 1.3, 0), Vector3(2.5, 2.6, 6.1)),
				[Color(0.6, 0.25, 0.15), Color(0.2, 0.35, 0.5), Color(0.3, 0.45, 0.3), Color(0.7, 0.6, 0.3)][rng.randi() % 4])
			colliders.box("Container", at + Vector3(0, 1.3, 0), Vector3(2.5, 2.6, 6.1))
		z += 7.0
	for corner in [Vector3(rect.end.x - 10.0, 0, rect.position.y + 9.0), Vector3(rect.end.x - 10.0, 0, rect.end.y - 9.0)]:
		if not corridor.blocks(corner, Vector2(14, 10), 6.5):
			batch.add("Sheds", _box, Props.place(corner + Vector3(0, 2.5, 0), Vector3(14, 5.0, 10)), Color(0.55, 0.57, 0.6))
			batch.add("ShedRoofs", _box, Props.place(corner + Vector3(0, 5.3, 0), Vector3(14.6, 0.6, 10.6)), Color(0.35, 0.37, 0.4))
			colliders.box("Depot shed", corner + Vector3(0, 2.8, 0), Vector3(14, 5.6, 10))


func _park(rect: Rect2) -> void:
	batch.add("Grass", _box, Props.place(Vector3(rect.get_center().x, 0.16, rect.get_center().y), Vector3(rect.size.x, 0.04, rect.size.y)), Color(0.3, 0.45, 0.22), false)
	# Cross paths and a small pond.
	batch.add("Paths", _box, Props.place(Vector3(rect.get_center().x, 0.19, rect.get_center().y), Vector3(rect.size.x, 0.02, 3.0)), Color(0.65, 0.6, 0.5), false)
	batch.add("Paths", _box, Props.place(Vector3(rect.get_center().x, 0.19, rect.get_center().y), Vector3(3.0, 0.02, rect.size.y)), Color(0.65, 0.6, 0.5), false)
	batch.add("Pond", _cyl, Props.place(Vector3(rect.get_center().x + rect.size.x * 0.25, 0.2, rect.get_center().y - rect.size.y * 0.22), Vector3(14, 0.04, 9)), Color(0.2, 0.32, 0.42), false)
	for i in 40:
		var at := Vector3(rng.randf_range(rect.position.x + 3.0, rect.end.x - 3.0), 0.0, rng.randf_range(rect.position.y + 3.0, rect.end.y - 3.0))
		if absf(at.x - rect.get_center().x) < 3.0 or absf(at.z - rect.get_center().y) < 3.0:
			continue
		_tree(at, rng.randf_range(6.0, 10.0), "Park tree")
	for i in 6:
		var bench := Vector3(rect.get_center().x + rng.randf_range(-20, 20), 0.45, rect.get_center().y + 2.5)
		batch.add("Benches", _box, Props.place(bench, Vector3(1.8, 0.5, 0.5)), Color(0.45, 0.32, 0.2))


func _tree(at: Vector3, height: float, collider_name: String) -> void:
	var crown := height * 0.45
	if corridor.blocks(at, Vector2(crown, crown), height):
		stats["rejected"] += 1
		return
	batch.add("TreeTrunks", _cyl, Props.place(at + Vector3(0, height * 0.3, 0), Vector3(0.35, height * 0.6, 0.35)), Color(0.33, 0.24, 0.16))
	batch.add("TreeCrowns", _sphere, Props.place(at + Vector3(0, height * 0.68, 0), Vector3(crown, height * 0.6, crown)),
		Color(0.2, 0.38, 0.16).lightened(rng.randf_range(-0.05, 0.12)))
	colliders.box(collider_name, at + Vector3(0, height * 0.55, 0), Vector3(crown * 0.8, height * 0.9, crown * 0.8))
	stats["trees"] += 1


func _compound(rect: Rect2) -> void:
	var inner := rect.grow(-2.0)
	var gate_gap := 8.0
	var wall := Color(0.66, 0.62, 0.55)
	var h := 2.6
	# Walls on four sides with a gate gap in the south wall.
	for side in ["north", "south", "east", "west"]:
		var pieces: Array = []
		match side:
			"north":
				pieces = [[Vector3(inner.get_center().x, 0, inner.position.y), Vector3(inner.size.x, h, 0.4)]]
			"east":
				pieces = [[Vector3(inner.end.x, 0, inner.get_center().y), Vector3(0.4, h, inner.size.y)]]
			"west":
				pieces = [[Vector3(inner.position.x, 0, inner.get_center().y), Vector3(0.4, h, inner.size.y)]]
			"south":
				var half := (inner.size.x - gate_gap) * 0.5
				pieces = [[Vector3(inner.position.x + half * 0.5, 0, inner.end.y), Vector3(half, h, 0.4)],
					[Vector3(inner.end.x - half * 0.5, 0, inner.end.y), Vector3(half, h, 0.4)]]
		for piece in pieces:
			var centre: Vector3 = piece[0] + Vector3(0, h * 0.5, 0)
			batch.add("Walls", _box, Props.place(centre, piece[1]), wall)
			colliders.box("Compound wall", centre, piece[1])
	# Gate: two posts and a red-and-white boom.
	var gate := Vector3(inner.get_center().x, 0, inner.end.y)
	for s: float in [-1.0, 1.0]:
		batch.add("GatePosts", _box, Props.place(gate + Vector3(s * gate_gap * 0.5, 1.6, 0), Vector3(0.6, 3.2, 0.6)), wall.darkened(0.2))
	batch.add("Booms", _box, Props.place(gate + Vector3(0, 1.1, 0.5), Vector3(gate_gap - 0.6, 0.15, 0.15)), Color(0.85, 0.2, 0.15))
	_building(Vector3(inner.get_center().x - inner.size.x * 0.2, 0, inner.get_center().y - inner.size.y * 0.15), Vector2(inner.size.x * 0.4, 16), 3)
	_building(Vector3(inner.get_center().x + inner.size.x * 0.25, 0, inner.get_center().y + inner.size.y * 0.1), Vector2(18, 14), 2)


func _construction(rect: Rect2) -> void:
	batch.add("Dirt", _box, Props.place(Vector3(rect.get_center().x, 0.15, rect.get_center().y), Vector3(rect.size.x, 0.02, rect.size.y)), Color(0.5, 0.42, 0.32), false)
	_fence(rect, Color(0.75, 0.6, 0.2), 2.0, "Site fence")
	# Half-built frame: columns and floor slabs.
	var frame := Vector3(rect.get_center().x - 8.0, 0, rect.get_center().y + 8.0)
	var concrete := Color(0.62, 0.62, 0.6)
	for i in 4:
		for j in 3:
			var column := frame + Vector3(-12 + i * 8.0, 10.0, -8 + j * 8.0)
			batch.add("Columns", _box, Props.place(column, Vector3(0.6, 20.0, 0.6)), concrete)
	for level: float in [6.4, 12.8, 19.2]:
		batch.add("Slabs", _box, Props.place(frame + Vector3(0, level, 0), Vector3(25.0, 0.4, 17.0)), concrete)
	colliders.box("Building frame", frame + Vector3(0, 10.0, 0), Vector3(25.0, 20.0, 17.0))
	# Tower crane, jib pointing east (away from the main avenue).
	var crane := Vector3(rect.get_center().x + 14.0, 0, rect.get_center().y - 12.0)
	var yellow := Color(0.9, 0.72, 0.15)
	batch.add("CraneTower", _box, Props.place(crane + Vector3(0, 21.0, 0), Vector3(1.8, 42.0, 1.8)), yellow)
	batch.add("CraneJib", _box, Props.place(crane + Vector3(16.0, 41.5, 0), Vector3(40.0, 1.2, 1.2)), yellow)
	batch.add("CraneCounterJib", _box, Props.place(crane + Vector3(-7.0, 41.5, 0), Vector3(12.0, 1.4, 1.6)), yellow.darkened(0.2))
	batch.add("CraneCab", _box, Props.place(crane + Vector3(0, 40.0, 1.6), Vector3(2.2, 2.0, 2.0)), Color(0.3, 0.32, 0.35))
	colliders.box("Tower crane", crane + Vector3(0, 21.0, 0), Vector3(1.8, 42.0, 1.8))
	colliders.box("Tower crane", crane + Vector3(10.0, 41.5, 0), Vector3(52.0, 1.6, 1.6))


func _plaza(rect: Rect2) -> void:
	var centre := Vector3(rect.get_center().x, 0, rect.get_center().y)
	batch.add("PlazaPaving", _box, Props.place(centre + Vector3(0, 0.15, 0), Vector3(rect.size.x, 0.02, rect.size.y)), Color(0.7, 0.66, 0.6), false)
	# Fountain and planters around the edges, away from the landing pad.
	var fountain := centre + Vector3(-rect.size.x * 0.3, 0, rect.size.y * 0.3)
	batch.add("Fountain", _cyl, Props.place(fountain + Vector3(0, 0.4, 0), Vector3(8.0, 0.8, 8.0)), Color(0.6, 0.6, 0.62))
	batch.add("FountainWater", _cyl, Props.place(fountain + Vector3(0, 0.82, 0), Vector3(7.2, 0.04, 7.2)), Color(0.3, 0.5, 0.65), false)
	batch.add("Fountain", _cyl, Props.place(fountain + Vector3(0, 1.5, 0), Vector3(1.0, 2.2, 1.0)), Color(0.6, 0.6, 0.62))
	for i in 10:
		var at := Vector3(rng.randf_range(rect.position.x + 3, rect.end.x - 3), 0, [rect.position.y + 3.0, rect.end.y - 3.0][i % 2])
		if corridor.blocks(at, Vector2(3, 3), 1.0):
			continue
		batch.add("Planters", _box, Props.place(at + Vector3(0, 0.45, 0), Vector3(3.0, 0.9, 1.4)), Color(0.5, 0.45, 0.4))
		batch.add("Shrubs", _sphere, Props.place(at + Vector3(0, 1.2, 0), Vector3(2.6, 1.0, 1.2)), Color(0.25, 0.42, 0.2))
	for i in 6:
		_tree(Vector3(rect.end.x - 4.0, 0, rect.position.y + 8.0 + i * 12.0), rng.randf_range(6, 8), "Plaza tree")


## Perimeter fence around a block rectangle, built from short panels so a panel near
## the route can be left out without removing the whole side.
func _fence(rect: Rect2, color: Color, height: float, collider_name: String) -> void:
	var r := rect.grow(-0.5)
	var corners := [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var panels := maxi(int(a.distance_to(b) / 6.0), 1)
		for k in panels:
			var p0 := a.lerp(b, float(k) / panels)
			var p1 := a.lerp(b, float(k + 1) / panels)
			var mid := (p0 + p1) * 0.5
			var length := p0.distance_to(p1)
			var size := Vector3(length, height, 0.1) if absf(b.y - a.y) < 0.01 else Vector3(0.1, height, length)
			var centre := Vector3(mid.x, height * 0.5, mid.y)
			if corridor.blocks(Vector3(mid.x, 0, mid.y), Vector2(size.x, size.z), height):
				continue
			batch.add("Fences", _box, Props.place(centre, size), color)
			batch.add("FencePosts", _box, Props.place(Vector3(p0.x, height * 0.5, p0.y), Vector3(0.15, height + 0.2, 0.15)), color.darkened(0.3))
			colliders.box(collider_name, centre, size)
