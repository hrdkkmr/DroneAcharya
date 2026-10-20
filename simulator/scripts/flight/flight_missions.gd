extends RefCounted
## Flight-training missions as data. `environment` selects the world: "course" is the
## original hand-built Stage 1 course (scenes/course/training_course.tscn); "city" and
## "village" are built procedurally from `route` by scripts/world/*.
## Route points are in metres (+X east, +Y up, -Z north). Checkpoints are rings the
## drone flies through in order; `landing` is the landing-zone centre on the ground.
## `hostile` enables the synthetic hazard layer (scripts/flight/flight_threats.gd).

const DEFAULT := "basic_course"
const ORDER := ["basic_course"]

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
}


static func has(id: String) -> bool:
	return MISSIONS.has(id)


static func resolve_id(id: String) -> String:
	return id if MISSIONS.has(id) else DEFAULT


static func get_mission(id: String) -> Dictionary:
	var mission: Dictionary = MISSIONS.get(id, MISSIONS[DEFAULT]).duplicate(true)
	mission["id"] = resolve_id(id)
	return mission
