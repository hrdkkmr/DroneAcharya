extends Control
## Compact heading-up radar scope used by flight training and threat observation.
## It only draws what it is given: sensor contacts (or tracker tracks) and known
## navigation marks. It never reads the simulation's ground truth.
##
## Every contact kind has its own shape AND letter, so nothing depends on colour:
##   friendly ○ F   unknown □ U   hostile ◆ H   projectile ▲ P
##   track (observation) □ T   coasting/stale: hollow, dimmed, "?"   swarm group ⬡ S
## Marks: destination ⊕ LZ, next ring ● (number), briefed threat area: dashed circle.
## update_display() computes `drawn` (used by _draw and by tests, since _draw does
## not run headless).

signal contact_clicked(id: String)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const STYLES := {
	"friendly": {"shape": "circle", "letter": "F", "color": Color(0.45, 0.8, 1.0), "name": "Friendly (ID reply)"},
	"unknown": {"shape": "square", "letter": "U", "color": Color(1.0, 0.85, 0.35), "name": "Unknown drone"},
	"hostile": {"shape": "diamond", "letter": "H", "color": Color(1.0, 0.4, 0.35), "name": "Hostile (closing on you)"},
	"projectile": {"shape": "triangle", "letter": "P", "color": Color(1.0, 0.55, 0.2), "name": "Simulated projectile"},
	"track": {"shape": "square", "letter": "T", "color": Color(0.45, 1.0, 0.55), "name": "Sensor track"},
	"group": {"shape": "hexagon", "letter": "S", "color": Color(1.0, 0.55, 0.85), "name": "Swarm group"},
	"destination": {"shape": "cross_circle", "letter": "LZ", "color": Color(0.35, 1.0, 0.5), "name": "Landing zone"},
	"waypoint": {"shape": "dot", "letter": "", "color": Color(1.0, 0.78, 0.25), "name": "Next ring"},
	"threat_area": {"shape": "area", "letter": "", "color": Color(1.0, 0.35, 0.3), "name": "Briefed threat area"},
}
const STALE_NAME := "Not seen recently (last known position)"

@export var range_m := 160.0
@export var scope_size := 240.0
## Kinds listed in the legend, in order.
@export var legend_kinds: PackedStringArray = ["friendly", "unknown", "hostile", "projectile", "destination", "waypoint", "threat_area"]

var title := "RADAR"
var contacts: Array = [] ## {id, position: Vector3, kind, stale, label?, velocity?}
var marks: Array = [] ## {kind, position: Vector3, label?, radius?}
var selected_id := ""
var own_position := Vector3.ZERO
var own_yaw := 0.0 ## radians; 0 = facing north (-Z), positive = turned left
var drawn: Array = [] ## {id, kind, point: Vector2, stale, clamped, label}
var show_legend := false
var status_text := ""

var _legend: PanelContainer
var _toggle: Button


func _ready() -> void:
	custom_minimum_size = Vector2(scope_size, scope_size + 28)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_toggle = Button.new()
	_toggle.text = "Legend"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.add_theme_font_size_override("font_size", 13)
	_toggle.position = Vector2(scope_size - 70, scope_size + 2)
	_toggle.size = Vector2(70, 24)
	_toggle.pressed.connect(func(): set_legend_visible(not show_legend))
	add_child(_toggle)
	_legend = UiKit.panel(0.92)
	_legend.visible = false
	add_child(_legend)
	var rows := UiKit.vbox(2)
	_legend.add_child(rows)
	for kind in legend_kinds:
		var style: Dictionary = STYLES[kind]
		rows.add_child(UiKit.label("%s  %s" % [_glyph(kind), style["name"]], 13, style["color"]))
	rows.add_child(UiKit.label("?  " + STALE_NAME, 13, UiKit.MUTED))
	rows.add_child(UiKit.label("Heading up · rings at %d and %d m" % [int(range_m * 0.5), int(range_m)], 13, UiKit.MUTED))


func set_legend_visible(on: bool) -> void:
	show_legend = on
	_legend.visible = on
	_legend.position = Vector2(0, -_legend.get_combined_minimum_size().y - 6)


static func _glyph(kind: String) -> String:
	return {"friendly": "○ F", "unknown": "□ U", "hostile": "◆ H", "projectile": "▲ P", "track": "□ T", "group": "⬡ S",
		"destination": "⊕ LZ", "waypoint": "● 1", "threat_area": "◌"}.get(kind, kind)


func _process(_delta: float) -> void:
	update_display()
	queue_redraw()


## World position → scope point (centre = own position, forward = up).
func to_scope(world: Vector3) -> Vector2:
	var offset := Vector2(world.x - own_position.x, world.z - own_position.z)
	var rotated := offset.rotated(own_yaw)
	return rotated / range_m * (scope_size * 0.5)


func update_display() -> void:
	drawn.clear()
	var radius := scope_size * 0.5
	for mark in marks:
		var p := to_scope(mark["position"])
		var clamped := p.length() > radius - 8.0
		if clamped:
			if mark["kind"] == "threat_area":
				if p.length() - float(mark.get("radius", 0.0)) / range_m * radius > radius:
					continue
			else:
				p = p.normalized() * (radius - 8.0)
		drawn.append({"id": "", "kind": mark["kind"], "point": p, "stale": false, "clamped": clamped,
			"label": mark.get("label", ""), "radius": float(mark.get("radius", 0.0)) / range_m * radius})
	for contact in contacts:
		var p := to_scope(contact["position"])
		if p.length() > radius:
			continue
		var heading := Vector2.ZERO
		var velocity: Vector3 = contact.get("velocity", Vector3.ZERO)
		if velocity.length() > 0.5:
			heading = Vector2(velocity.x, velocity.z).rotated(own_yaw).normalized()
		drawn.append({"id": contact["id"], "kind": contact["kind"], "point": p, "stale": contact.get("stale", false),
			"clamped": false, "label": contact.get("label", contact["id"]), "heading": heading})


func _draw() -> void:
	var c := Vector2(scope_size, scope_size) * 0.5
	var radius := scope_size * 0.5
	var font := get_theme_default_font()
	draw_circle(c, radius, Color(0.02, 0.05, 0.06, 0.82))
	draw_arc(c, radius, 0, TAU, 64, Color(0.4, 0.6, 0.55, 0.9), 1.5)
	draw_arc(c, radius * 0.5, 0, TAU, 48, Color(0.4, 0.6, 0.55, 0.4), 1.0)
	draw_line(c - Vector2(radius, 0), c + Vector2(radius, 0), Color(0.4, 0.6, 0.55, 0.25))
	draw_line(c - Vector2(0, radius), c + Vector2(0, radius), Color(0.4, 0.6, 0.55, 0.25))
	# North marker on the rim.
	var north := c + Vector2(0, -1).rotated(own_yaw) * (radius - 10.0)
	draw_string(font, north + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.9, 0.85))
	draw_string(font, Vector2(6, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.85, 0.8))
	draw_string(font, Vector2(scope_size - 64, 16), "%d m" % int(range_m), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.85, 0.8))
	for item in drawn:
		_draw_item(c, item, font)
	# Own drone: white chevron pointing up.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(6, 6), c + Vector2(0, 2), c + Vector2(-6, 6)]), Color.WHITE)
	if not status_text.is_empty():
		draw_string(font, Vector2(4, scope_size + 18), status_text, HORIZONTAL_ALIGNMENT_LEFT, scope_size - 80, 12, Color(0.75, 0.8, 0.82))


func _draw_item(c: Vector2, item: Dictionary, font: Font) -> void:
	var style: Dictionary = STYLES.get(item["kind"], STYLES["unknown"])
	var color: Color = style["color"]
	var p: Vector2 = c + item["point"]
	if item["stale"]:
		color.a = 0.5
	var selected: bool = not String(item["id"]).is_empty() and item["id"] == selected_id
	var s := 6.0 if not selected else 8.0
	var width := 1.5 if not selected else 2.5
	match style["shape"]:
		"circle":
			draw_arc(p, s, 0, TAU, 16, color, width)
		"square":
			draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), color, not item["stale"] and item["kind"] == "track", width)
			if item["kind"] != "track" or item["stale"]:
				draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), color, false, width)
		"diamond":
			var points := PackedVector2Array([p + Vector2(0, -s - 1), p + Vector2(s + 1, 0), p + Vector2(0, s + 1), p + Vector2(-s - 1, 0)])
			if item["stale"]:
				points.append(points[0])
				draw_polyline(points, color, width)
			else:
				draw_colored_polygon(points, color)
		"triangle":
			var dir: Vector2 = item.get("heading", Vector2.ZERO)
			if dir == Vector2.ZERO:
				dir = Vector2(0, -1)
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([p + dir * 7.0, p - dir * 4.0 + side * 4.5, p - dir * 4.0 - side * 4.5]), color)
		"hexagon":
			var hex := PackedVector2Array()
			for k in 7:
				hex.append(p + Vector2(s + 2, 0).rotated(TAU * k / 6.0))
			draw_polyline(hex, color, width)
		"cross_circle":
			draw_arc(p, 7.0, 0, TAU, 16, color, 2.0)
			draw_line(p - Vector2(5, 0), p + Vector2(5, 0), color, 1.5)
			draw_line(p - Vector2(0, 5), p + Vector2(0, 5), color, 1.5)
		"dot":
			draw_circle(p, 4.0, color)
		"area":
			var r: float = item["radius"]
			var segments := 24
			for k in segments:
				if k % 2 == 0:
					draw_arc(p, r, TAU * k / segments, TAU * (k + 1) / segments, 3, Color(color, 0.7), 1.2)
	var letter: String = style["letter"]
	var label: String = String(item.get("label", ""))
	var text := letter
	if item["kind"] in ["waypoint", "destination"]:
		text = label if not label.is_empty() else letter
	elif selected and not label.is_empty():
		text = "%s %s" % [letter, label]
	if item["stale"]:
		text += "?"
	if not text.is_empty():
		draw_string(font, p + Vector2(9, -6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	if selected:
		draw_arc(p, 12.0, 0, TAU, 20, Color(1, 1, 1, 0.9), 1.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := Vector2(scope_size, scope_size) * 0.5
		var best := ""
		var best_distance := 14.0
		for item in drawn:
			if String(item["id"]).is_empty():
				continue
			var distance: float = (c + item["point"]).distance_to(event.position)
			if distance < best_distance:
				best_distance = distance
				best = item["id"]
		if not best.is_empty():
			contact_clicked.emit(best)
			accept_event()


## Counts of drawn contacts by kind (for tests and the HUD summary).
func counts() -> Dictionary:
	var out := {}
	for item in drawn:
		if not String(item["id"]).is_empty():
			out[item["kind"]] = out.get(item["kind"], 0) + 1
	return out
