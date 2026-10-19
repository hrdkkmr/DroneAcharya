extends RefCounted
## Simplified point-mass flight model for scripted target actors. A behaviour asks
## for a desired air velocity; this model limits acceleration, turn rate, speed and
## altitude, applies velocity damping and adds wind drift. It is a training-game
## approximation, not a validated aerodynamic model.

const VehicleState := preload("res://scripts/sim/vehicle_state.gd")

var max_speed := 12.0 ## m/s, air-relative
var max_acceleration := 4.0 ## m/s²
var max_turn_rate_degrees := 60.0 ## heading change limit, degrees per second
var max_climb_rate := 3.0 ## m/s
var damping := 0.2 ## 1/s; extra velocity decay that gives momentum a natural fade
var wind_factor := 0.3 ## 0 = unaffected by wind, 1 = drifts fully with the wind
var min_altitude := 5.0 ## m
var max_altitude := 400.0 ## m


static func from_profile(profile: Dictionary) -> RefCounted:
	var model: RefCounted = load("res://scripts/sim/flight_model.gd").new()
	for key in ["max_speed", "max_acceleration", "max_turn_rate_degrees", "max_climb_rate", "damping", "wind_factor", "min_altitude", "max_altitude"]:
		if profile.has(key):
			model.set(key, float(profile[key]))
	return model


## Advances `state` by `dt` seconds. `air_velocity` is the vehicle's own velocity
## relative to the air (stored separately so wind drift does not feed back into it).
## Returns the new air velocity.
func step(state: VehicleState, air_velocity: Vector3, desired: Vector3, wind: Vector3, dt: float) -> Vector3:
	if dt <= 0.0 or not is_finite(dt):
		return air_velocity
	desired = _limit_speed(desired)
	desired.y = clampf(desired.y, -max_climb_rate, max_climb_rate)
	var turned := _limit_turn(air_velocity, desired, dt)
	var change := (turned - air_velocity).limit_length(max_acceleration * dt)
	var new_air := (air_velocity + change) * (1.0 - clampf(damping * dt, 0.0, 1.0))
	if desired.length() > 0.01:
		new_air = new_air.limit_length(max_speed)
	var ground_velocity := new_air + wind * wind_factor
	var old_velocity := state.velocity
	state.position += ground_velocity * dt
	if state.position.y < min_altitude:
		state.position.y = min_altitude
		ground_velocity.y = maxf(ground_velocity.y, 0.0)
		new_air.y = maxf(new_air.y, 0.0)
	elif state.position.y > max_altitude:
		state.position.y = max_altitude
		ground_velocity.y = minf(ground_velocity.y, 0.0)
		new_air.y = minf(new_air.y, 0.0)
	state.velocity = ground_velocity
	state.acceleration = (ground_velocity - old_velocity) / dt
	if Vector2(new_air.x, new_air.z).length() > 0.3:
		state.yaw = atan2(-new_air.x, -new_air.z)
	state.time_s += dt
	return new_air


func _limit_speed(velocity: Vector3) -> Vector3:
	var horizontal := Vector2(velocity.x, velocity.z).limit_length(max_speed)
	return Vector3(horizontal.x, velocity.y, horizontal.y)


## Rotates the horizontal part of `current` toward `desired` by at most the turn limit.
func _limit_turn(current: Vector3, desired: Vector3, dt: float) -> Vector3:
	var from := Vector2(current.x, current.z)
	var to := Vector2(desired.x, desired.z)
	if from.length() < 0.5 or to.length() < 0.01:
		return desired
	var angle := from.angle_to(to)
	var limit := deg_to_rad(max_turn_rate_degrees) * dt
	if absf(angle) <= limit:
		return desired
	var heading := from.normalized().rotated(signf(angle) * limit) * to.length()
	return Vector3(heading.x, desired.y, heading.y)
