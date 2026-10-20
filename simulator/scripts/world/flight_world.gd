extends RefCounted
## Builds a complete flight-training world for a mission whose environment is not the
## hand-built course: the procedural environment (city or village), the launch pad,
## the numbered rings and the landing zone. Returns where the drone starts and the
## training area. Node names match the original course ("Checkpoints",
## "LandingZone"), so mission.gd works unchanged.

const CityBuilder := preload("res://scripts/world/city_builder.gd")
const VillageBuilder := preload("res://scripts/world/village_builder.gd")
const CHECKPOINT := preload("res://scenes/course/checkpoint.tscn")
const LANDING_ZONE := preload("res://scripts/course/landing_zone.gd")
const BUILDERS := {"city": CityBuilder, "village": VillageBuilder}


static func supports(environment: String) -> bool:
	return BUILDERS.has(environment)


## Returns {ok, spawn: Transform3D, area: Rect2, stats} (ok false for an unknown environment).
static func build(parent: Node3D, mission: Dictionary, reduced_effects := false) -> Dictionary:
	var builder = BUILDERS.get(mission["environment"])
	if builder == null:
		return {"ok": false, "error": "unknown environment '%s'" % mission["environment"]}
	var route: Dictionary = mission["route"]
	var result: Dictionary = builder.build(parent, route, int(mission.get("seed", 1)), reduced_effects)
	var spawn: Vector3 = route["spawn"]
	parent.add_child(_launch_pad(spawn))
	var checkpoints := Node3D.new()
	checkpoints.name = "Checkpoints"
	parent.add_child(checkpoints)
	var previous := spawn
	for i in route["checkpoints"].size():
		var position: Vector3 = route["checkpoints"][i]
		var ring := CHECKPOINT.instantiate()
		ring.name = "Checkpoint%d" % (i + 1)
		var approach := Vector3(position.x - previous.x, 0.0, position.z - previous.z)
		ring.transform = Transform3D(Basis.looking_at(approach.normalized() if approach.length() > 0.1 else Vector3.FORWARD, Vector3.UP), position)
		checkpoints.add_child(ring)
		previous = position
	parent.add_child(_landing_zone(route["landing"]))
	# The drone faces its first ring from the pad.
	var first: Vector3 = route["checkpoints"][0] if not route["checkpoints"].is_empty() else spawn + Vector3.FORWARD
	var facing := Vector3(first.x - spawn.x, 0, first.z - spawn.z).normalized()
	return {"ok": true, "spawn": Transform3D(Basis.looking_at(facing, Vector3.UP), spawn), "area": result["area"], "stats": result["stats"]}


static func _launch_pad(at: Vector3) -> Node3D:
	var pad := Node3D.new()
	pad.name = "LaunchPad"
	pad.position = at
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.5
	mesh.bottom_radius = 2.5
	mesh.height = 0.04
	mesh.radial_segments = 32
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.55, 0.1)
	mesh.material = material
	disc.mesh = mesh
	disc.position = Vector3(0, -0.005, 0)
	pad.add_child(disc)
	var label := Label3D.new()
	label.text = "LAUNCH"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 10
	label.position = Vector3(0, 3.0, 3.0)
	pad.add_child(label)
	return pad


static func _landing_zone(at: Vector3) -> Node3D:
	var zone := Node3D.new()
	zone.name = "LandingZone"
	zone.set_script(LANDING_ZONE)
	zone.position = at
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 4.0
	mesh.bottom_radius = 4.0
	mesh.height = 0.04
	mesh.radial_segments = 48
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.75, 0.3)
	material.emission_enabled = true
	material.emission = Color(0.1, 0.6, 0.25)
	material.emission_energy_multiplier = 0.4
	mesh.material = material
	disc.mesh = mesh
	disc.position = Vector3(0, 0.02, 0)
	zone.add_child(disc)
	var beacon := MeshInstance3D.new()
	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.25
	beacon_mesh.bottom_radius = 0.25
	beacon_mesh.height = 6.0
	var beacon_material := StandardMaterial3D.new()
	beacon_material.albedo_color = Color(0.2, 1.0, 0.4)
	beacon_material.emission_enabled = true
	beacon_material.emission = Color(0.2, 1.0, 0.4)
	beacon_material.emission_energy_multiplier = 1.5
	beacon_mesh.material = beacon_material
	beacon.mesh = beacon_mesh
	beacon.position = Vector3(4.6, 3.0, 0)
	zone.add_child(beacon)
	var label := Label3D.new()
	label.text = "LAND"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.outline_size = 16
	label.position = Vector3(0, 4.0, 0)
	zone.add_child(label)
	return zone
