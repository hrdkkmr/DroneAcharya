extends RefCounted
## Drone configurations for flight training. Every profile drives the same assisted
## flight controller (drone_controller.gd); only these numbers differ. Recon keeps the
## original Stage 1 tuning exactly, so the baseline feel and its tests are unchanged.
## To add a profile, add an entry with every key of `recon`.
## Values are training-game approximations, not data for any real aircraft.

const DEFAULT := "recon"
const ORDER := ["scout", "recon", "heavy"]

const PROFILES := {
	"scout": {
		"title": "Scout",
		"summary": "Compact and quick. Sharp turns and short stopping distance, but the smallest battery.",
		"max_horizontal_speed": 12.0, "max_ascent_speed": 5.0, "max_descent_speed": 4.0,
		"max_yaw_rate_degrees": 130.0, "horizontal_acceleration": 10.0, "horizontal_braking": 12.0,
		"vertical_acceleration": 9.0, "crash_speed": 3.0, "max_visual_tilt_degrees": 26.0,
		"visual_scale": 0.8, "body_color": Color(0.22, 0.27, 0.2),
		"follow_distance": 5.5, "follow_height": 2.4, "follow_smoothing": 7.0,
		"endurance_s": 300.0,
	},
	"recon": {
		"title": "Recon",
		"summary": "Balanced speed, turning and stability. The standard training drone.",
		"max_horizontal_speed": 8.0, "max_ascent_speed": 4.0, "max_descent_speed": 3.0,
		"max_yaw_rate_degrees": 90.0, "horizontal_acceleration": 6.0, "horizontal_braking": 8.0,
		"vertical_acceleration": 6.0, "crash_speed": 3.5, "max_visual_tilt_degrees": 18.0,
		"visual_scale": 1.0, "body_color": Color(0.16, 0.18, 0.2),
		"follow_distance": 7.0, "follow_height": 3.0, "follow_smoothing": 5.0,
		"endurance_s": 600.0,
	},
	"heavy": {
		"title": "Heavy utility",
		"summary": "Large and stable. Slow to speed up, turn and stop; slow climb and descent; longest endurance.",
		"max_horizontal_speed": 5.5, "max_ascent_speed": 2.5, "max_descent_speed": 2.0,
		"max_yaw_rate_degrees": 55.0, "horizontal_acceleration": 3.0, "horizontal_braking": 3.5,
		"vertical_acceleration": 3.0, "crash_speed": 4.5, "max_visual_tilt_degrees": 9.0,
		"visual_scale": 1.35, "body_color": Color(0.32, 0.3, 0.22),
		"follow_distance": 9.5, "follow_height": 4.0, "follow_smoothing": 3.5,
		"endurance_s": 900.0,
	},
}

## Controller properties copied from a profile.
const CONTROLLER_KEYS := ["max_horizontal_speed", "max_ascent_speed", "max_descent_speed", "max_yaw_rate_degrees",
	"horizontal_acceleration", "horizontal_braking", "vertical_acceleration", "crash_speed", "max_visual_tilt_degrees"]
const CAMERA_KEYS := ["follow_distance", "follow_height", "follow_smoothing"]


static func has(id: String) -> bool:
	return PROFILES.has(id)


## The profile for `id`, or the default when the id is unknown.
static func get_profile(id: String) -> Dictionary:
	return PROFILES.get(id, PROFILES[DEFAULT])


static func resolve_id(id: String) -> String:
	return id if PROFILES.has(id) else DEFAULT


## Ratings 1..5 for the briefing screen, derived from the numbers (not hand-set).
static func ratings(id: String) -> Dictionary:
	var p := get_profile(id)
	return {
		"Top speed": clampi(roundi(p["max_horizontal_speed"] / 2.5), 1, 5),
		"Agility": clampi(roundi(p["max_yaw_rate_degrees"] / 26.0), 1, 5),
		"Climb": clampi(roundi(p["max_ascent_speed"]), 1, 5),
		"Endurance": clampi(roundi(p["endurance_s"] / 180.0), 1, 5),
	}
