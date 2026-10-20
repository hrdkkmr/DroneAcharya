extends RefCounted
## The flight route of a mission as a clear corridor. Environment builders ask it
## whether a prop would block the route, so every mission stays flyable whatever
## the random placement: a prop is rejected when it is within `clearance` metres
## (horizontally) of a route segment and its top is less than `headroom` metres below
## the route there, or when it stands on the launch or landing pad area.
## Segments: launch pad → first ring (straight climb-out), ring → ring, last ring → landing.

var segments: Array = [] ## [Vector3 a, Vector3 b]
var pads: Array = [] ## Vector3 centres (ground) of the launch and landing areas
var clearance := 8.0
var headroom := 4.0
var pad_radius := 11.0


func _init(spawn: Vector3, checkpoints: Array, landing: Vector3, corridor_clearance := 8.0) -> void:
	clearance = corridor_clearance
	var points: Array = [spawn]
	if not checkpoints.is_empty():
		points.append(Vector3(spawn.x, checkpoints[0].y, spawn.z))
	points.append_array(checkpoints)
	if not checkpoints.is_empty():
		points.append(Vector3(landing.x, checkpoints[-1].y, landing.z))
	points.append(landing)
	for i in points.size() - 1:
		segments.append([points[i], points[i + 1]])
	if not checkpoints.is_empty():
		segments.append([spawn, checkpoints[0]])
	pads = [spawn, landing]


## True when a box with this footprint centre/size and top height would block the route.
## `size` is the full footprint (x, z); the box is axis-aligned after `yaw` is ignored
## conservatively by using its bounding circle.
func blocks(center: Vector3, size: Vector2, top: float) -> bool:
	var reach := size.length() * 0.5
	var p := Vector2(center.x, center.z)
	for pad in pads:
		if p.distance_to(Vector2(pad.x, pad.z)) < pad_radius + reach and top > 0.25:
			return true
	for segment in segments:
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var along := b2 - a2
		var t := 0.0
		if along.length_squared() > 0.0001:
			t = clampf((p - a2).dot(along) / along.length_squared(), 0.0, 1.0)
		var distance := p.distance_to(a2 + along * t)
		if distance > clearance + reach:
			continue
		var route_height := lerpf(a.y, b.y, t)
		if top > route_height - headroom:
			return true
	return false
