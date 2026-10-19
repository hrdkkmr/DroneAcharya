extends RefCounted
## Common description of a simulated vehicle at one instant, shared by the
## player-controlled training drone and the scripted target actors.
## Units: metres, metres per second, metres per second squared, radians, seconds.
## Axes: +X east, +Y up, -Z north. Yaw 0 faces north; positive yaw turns left.

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var acceleration := Vector3.ZERO
var yaw := 0.0
var time_s := 0.0


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Compass heading of travel in degrees (0 = north, 90 = east), or of the nose when stationary.
func heading_degrees() -> float:
	if horizontal_speed() > 0.05:
		return fposmod(rad_to_deg(atan2(velocity.x, -velocity.z)), 360.0)
	return fposmod(-rad_to_deg(yaw), 360.0)


func duplicate_state() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy.position = position
	copy.velocity = velocity
	copy.acceleration = acceleration
	copy.yaw = yaw
	copy.time_s = time_s
	return copy


func to_dict() -> Dictionary:
	return {
		"t": snappedf(time_s, 0.001),
		"position": [snappedf(position.x, 0.01), snappedf(position.y, 0.01), snappedf(position.z, 0.01)],
		"velocity": [snappedf(velocity.x, 0.01), snappedf(velocity.y, 0.01), snappedf(velocity.z, 0.01)],
		"yaw": snappedf(yaw, 0.0001),
	}
