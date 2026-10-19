extends Control
## Draws track markers at the tracker's *estimated* positions (never ground truth).
##  * tentative: small grey square   * confirmed: green brackets
##  * coasting: amber dashed brackets with the time since the last update
##  * selected: yellow, thicker
##  * swarm group members: brackets only, plus one group label at the group centroid
## Left-click near a marker selects that track.

signal track_clicked(track_id: String)

const PICK_RADIUS_PX := 32.0

var session: RefCounted
var camera: Camera3D
var selected_id := ""
var markers: Array = [] ## {id, point, track, world_position} from the last update
var _screen_positions := {} ## track id -> Vector2


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _process(_delta: float) -> void:
	update_markers()
	queue_redraw()


## Projects every active track's estimated position to the screen.
func update_markers() -> void:
	markers.clear()
	_screen_positions.clear()
	if session == null or camera == null:
		return
	var now: float = session.time_s()
	var screen := Rect2(Vector2.ZERO, get_viewport_rect().size)
	for id in session.tracker.tracks:
		var track: Dictionary = session.tracker.tracks[id]
		var world_position: Vector3 = session.tracker.estimated_position(track, now)
		if camera.is_position_behind(world_position):
			continue
		var point := camera.unproject_position(world_position)
		if not screen.has_point(point):
			continue
		_screen_positions[id] = point
		markers.append({"id": id, "point": point, "track": track, "world_position": world_position})


func _draw() -> void:
	if session == null or camera == null:
		return
	var now: float = session.time_s()
	var font := get_theme_default_font()
	for marker in markers:
		var id: String = marker["id"]
		var track: Dictionary = marker["track"]
		var point: Vector2 = marker["point"]
		var world_position: Vector3 = marker["world_position"]
		var status: String = track["status"]
		if status == "tentative":
			draw_rect(Rect2(point - Vector2(4, 4), Vector2(8, 8)), Color(0.75, 0.75, 0.75, 0.7), false, 1.0)
			continue
		var selected: bool = id == selected_id
		var color := Color(0.35, 1.0, 0.45) if status == "confirmed" else Color(1.0, 0.65, 0.2)
		if selected:
			color = Color(1.0, 0.9, 0.2)
		_brackets(point, 14.0 if selected else 11.0, color, 2.5 if selected else 1.5, status == "coasting")
		var grouped := not String(track["swarm_group"]).is_empty()
		if grouped and not selected:
			continue
		var range_m := (world_position - camera.global_position).length()
		var text := "%s  %.0f m" % [id, range_m]
		if grouped:
			text += "  [%s]" % track["swarm_group"]
		if status == "coasting":
			text += "  no update %.1f s" % (now - float(track["last_update_t"]))
		draw_string_outline(font, point + Vector2(16, -10), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
		draw_string(font, point + Vector2(16, -10), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
	for gid in session.tracker.groups:
		var group: Dictionary = session.tracker.groups[gid]
		var centroid: Vector3 = group["centroid"]
		if camera.is_position_behind(centroid):
			continue
		var at := camera.unproject_position(centroid) + Vector2(0, 26)
		var label := "%s · swarm group · %d tracks" % [gid, group["members"].size()]
		draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 15, 4, Color.BLACK)
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 15, Color(1.0, 0.55, 0.85))


func _brackets(center: Vector2, half: float, color: Color, width: float, dashed: bool) -> void:
	var arm := half * 0.6
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector2 = center + corner * half
		if dashed:
			draw_line(p, p - Vector2(corner.x * arm * 0.5, 0), color, width)
			draw_line(p, p - Vector2(0, corner.y * arm * 0.5), color, width)
		else:
			draw_line(p, p - Vector2(corner.x * arm, 0), color, width)
			draw_line(p, p - Vector2(0, corner.y * arm), color, width)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := nearest_track(event.position)
		if not id.is_empty():
			track_clicked.emit(id)
			accept_event()


func nearest_track(point: Vector2) -> String:
	var best := ""
	var best_distance := PICK_RADIUS_PX
	for id in _screen_positions:
		var distance: float = (_screen_positions[id] as Vector2).distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = id
	return best
