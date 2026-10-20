extends RefCounted
## Flight-training missions as data. `environment` selects the world: "course" is the
## original hand-built Stage 1 course (scenes/course/training_course.tscn); "city" and
## "village" are built procedurally from `route` by scripts/world/*.
## Route points are in metres (+X east, +Y up, -Z north). Checkpoints are rings the
## drone flies through in order; `landing` is the landing-zone centre on the ground.
## `traffic` adds friendly and unknown drones (radar practice); `hostile` adds the
## synthetic hazard layer (scripts/flight/flight_traffic.gd): emplacement `sites`
## (briefed threat areas) and a hostile drone patrolling near `hostile_patrol`.

const DEFAULT := "basic_course"
const ORDER := ["basic_course", "city_delivery", "village_supply", "city_hostile", "village_hostile"]

const CITY_ROUTE := {
	"spawn": Vector3(-90, 0, -20),
	"checkpoints": [Vector3(-90, 12, -60), Vector3(-50, 12, -60), Vector3(-50, 18, -150), Vector3(30, 16, -150), Vector3(30, 14, -230)],
	"landing": Vector3(70, 0, -270),
}
const VILLAGE_ROUTE := {
	"spawn": Vector3(-40, 0, 30),
	"checkpoints": [Vector3(-40, 12, -15), Vector3(0, 14, -75), Vector3(25, 18, -150), Vector3(90, 15, -205), Vector3(112, 14, -258)],
	"landing": Vector3(140, 0, -300),
}

const MISSIONS := {
	"basic_course": {
		"title": "Basic course",
		"environment": "course",
		"summary": "Take off, fly through four rings in order around pillars and walls, then land in the green zone.",
		"time_limit_s": 180.0,
		"hostile": false,
		"traffic": false,
		"hazards": "Pillars, two walls and crates beside the rings.",
	},
	"city_delivery": {
		"title": "City delivery",
		"environment": "city",
		"seed": 7101,
		"summary": "Climb out of the depot yard, follow the streets through five rings and land on the pad in the city plaza.",
		"time_limit_s": 240.0,
		"hostile": false,
		"traffic": true,
		"hazards": "Buildings line the streets; streetlights, a sign gantry over the avenue, rooftop tanks and a tower crane near the main avenue.",
		"route": CITY_ROUTE,
	},
	"village_supply": {
		"title": "Village supply run",
		"environment": "village",
		"seed": 8202,
		"summary": "Take off from the farmyard, fly over the village and fields through five rings and land on the camp helipad.",
		"time_limit_s": 240.0,
		"hostile": false,
		"traffic": true,
		"hazards": "Overhead power lines along the main road (about 9 m high), the water-tank tower, tall trees and the camp watchtower.",
		"route": VILLAGE_ROUTE,
	},
	"city_hostile": {
		"title": "City transit — hostile area",
		"environment": "city",
		"seed": 7101,
		"summary": "The city delivery route through a simulated hostile area. Watch the radar and warnings, keep moving and avoid simulated projectiles and the hostile drone.",
		"time_limit_s": 300.0,
		"hostile": true,
		"traffic": true,
		"hazards": "As City delivery, plus fictional ground emplacements that launch slow simulated projectiles and a hostile drone that follows you when near.",
		"route": CITY_ROUTE,
		"sites": [Vector3(-10, 0, -105), Vector3(-90, 0, -192), Vector3(72, 0, -112)],
		"hostile_patrol": Vector3(-10, 34, -190),
	},
	"village_hostile": {
		"title": "Village transit — hostile area",
		"environment": "village",
		"seed": 8202,
		"summary": "The village supply route through a simulated hostile area. Use the radar and warnings to keep clear of simulated threats.",
		"time_limit_s": 300.0,
		"hostile": true,
		"traffic": true,
		"hazards": "As Village supply run, plus fictional ground emplacements that launch slow simulated projectiles and a hostile drone that follows you when near.",
		"route": VILLAGE_ROUTE,
		"sites": [Vector3(-85, 0, -55), Vector3(75, 0, -150), Vector3(45, 0, -255)],
		"hostile_patrol": Vector3(20, 30, -125),
	},
}


static func has(id: String) -> bool:
	return MISSIONS.has(id)


static func resolve_id(id: String) -> String:
	return id if MISSIONS.has(id) else DEFAULT


static func get_mission(id: String) -> Dictionary:
	var mission: Dictionary = MISSIONS.get(id, MISSIONS[DEFAULT]).duplicate(true)
	mission["id"] = resolve_id(id)
	return mission
