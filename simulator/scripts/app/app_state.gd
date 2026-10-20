extends RefCounted
## Values passed between screens (menu → scenario selection → briefing → exercise →
## review). Static so it works without an autoload, including in headless tests.

const SCENES := {
	"menu": "res://scenes/main.tscn",
	"flight": "res://scenes/flight/flight_training.tscn",
	"flight_briefing": "res://scenes/menu/flight_briefing.tscn",
	"scenario_select": "res://scenes/menu/scenario_select.tscn",
	"briefing": "res://scenes/menu/briefing.tscn",
	"observation": "res://scenes/observation/observation.tscn",
	"history": "res://scenes/menu/history.tscn",
	"settings": "res://scenes/menu/settings.tscn",
	"tutorial": "res://scenes/menu/tutorial.tscn",
}

## Validated droneacharya-scenario config chosen on the selection screen.
static var selected_config: Dictionary = {}
## Session to review or replay (a parsed droneacharya-session dictionary), if any.
static var review_session: Dictionary = {}
## When true the observation scene replays review_session instead of running live.
static var replay_requested := false
## Settings: use the trained ML classifier (Model 2) in decision support when it loads.
static var use_ml := true
## Where session records are saved and read. Tests redirect this to a scratch folder.
static var sessions_dir := "user://sessions"
## Flight training: mission and drone profile chosen on the flight briefing screen
## (ids from scripts/flight/flight_missions.gd and drone_profiles.gd).
static var flight_mission := "basic_course"
static var flight_profile := "recon"
## Where flight-mission records (droneacharya-flight-session) are saved.
static var flight_sessions_dir := "user://flight_sessions"
## Where the history screen writes exported files. Tests redirect this too.
static var exports_dir := "user://exports"


static func goto(tree: SceneTree, scene: String) -> void:
	var path: String = SCENES.get(scene, scene)
	tree.paused = false
	tree.change_scene_to_file(path)
