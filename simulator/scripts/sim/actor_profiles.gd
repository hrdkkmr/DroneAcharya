extends RefCounted
## Synthetic actor profiles. All values are fictional training parameters chosen to
## make behaviours visually and statistically distinguishable; they do not describe
## any real aircraft, animal or sensor signature.
##
## truth_category uses VIGIL's vocabulary: routine / review / background.
## `significant` objects count as threats for missed-threat scoring.

const PROFILES := {
	"bird": {
		"label": "Bird (biological)",
		"truth_category": "background", "significant": false,
		"behaviors": ["erratic"],
		"size_m": 0.6, "radar_reflectivity": 0.25, "id_reply": false, "flaps": true,
		"max_speed": 15.0, "max_acceleration": 5.0, "max_turn_rate_degrees": 140.0,
		"max_climb_rate": 3.0, "damping": 0.3, "wind_factor": 0.25,
		"speed_mps": [6.0, 13.0], "altitude_m": [20.0, 90.0],
	},
	"balloon": {
		"label": "Drifting balloon",
		"truth_category": "background", "significant": false,
		"behaviors": ["drift"],
		"size_m": 1.8, "radar_reflectivity": 0.6, "id_reply": false,
		"max_speed": 1.0, "max_acceleration": 0.5, "max_turn_rate_degrees": 30.0,
		"max_climb_rate": 0.6, "damping": 0.5, "wind_factor": 1.0,
		"speed_mps": [0.0, 0.0], "altitude_m": [60.0, 200.0],
	},
	"authorised_uav": {
		"label": "Authorised UAV",
		"truth_category": "routine", "significant": false,
		"behaviors": ["transit"],
		"size_m": 0.9, "radar_reflectivity": 0.45, "id_reply": true,
		"max_speed": 16.0, "max_acceleration": 3.0, "max_turn_rate_degrees": 25.0,
		"max_climb_rate": 2.0, "damping": 0.05, "wind_factor": 0.2,
		"speed_mps": [10.0, 14.0], "altitude_m": [60.0, 120.0],
	},
	"unidentified_uav": {
		"label": "Unidentified UAV",
		"truth_category": "review", "significant": true,
		"behaviors": ["transit", "loiter", "hover"],
		"size_m": 0.7, "radar_reflectivity": 0.35, "id_reply": false,
		"max_speed": 14.0, "max_acceleration": 4.0, "max_turn_rate_degrees": 50.0,
		"max_climb_rate": 3.0, "damping": 0.1, "wind_factor": 0.25,
		"speed_mps": [5.0, 11.0], "altitude_m": [40.0, 110.0],
	},
	"swarm_uav": {
		"label": "Coordinated swarm UAV",
		"truth_category": "review", "significant": true,
		"behaviors": ["transit", "loiter"],
		"size_m": 0.5, "radar_reflectivity": 0.3, "id_reply": false,
		"max_speed": 14.0, "max_acceleration": 5.0, "max_turn_rate_degrees": 70.0,
		"max_climb_rate": 3.0, "damping": 0.1, "wind_factor": 0.25,
		"speed_mps": [6.0, 10.0], "altitude_m": [40.0, 100.0],
	},
}


static func names() -> Array:
	return PROFILES.keys()


static func get_profile(name: String) -> Dictionary:
	return PROFILES.get(name, {})
