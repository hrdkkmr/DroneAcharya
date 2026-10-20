extends Control
## Threat-detection tutorial: nine short steps with simple drawn diagrams and two
## hands-on practice steps (select a contact on a practice radar; choose and confirm
## a classification with the wheel and right-click). Used full-screen before the
## first exercise and as an overlay from the observation pause menu.
## Every instruction is on-screen text (there is no voice narration; see
## docs/IMPROVEMENT_PLAN.md). Step cues use the shared sound cues when available.

signal finished(skipped: bool)
signal step_changed(index: int)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const RadarDisplay := preload("res://scripts/ui/radar_display.gd")
const Vocabulary := preload("res://scripts/ai/vocabulary.gd")

const STEPS := [
	{"title": "Your task", "diagram": "task",
		"text": "You watch a fictional protected area from an observation post. Synthetic sensors report contacts in the sky.\nFor each contact: inspect it, classify it, then choose a procedural response. Nothing here controls any real system."},
	{"title": "What you see", "diagram": "views",
		"text": "Eye view, or the simulated sensor camera with V (TV by day, thermal style at night).\nBrackets mark where the tracker estimates a contact is. Dashed amber brackets mean no recent update: the position is a guess."},
	{"title": "Radar symbols", "diagram": "symbols",
		"text": "The radar in the bottom-right corner is heading-up: the top is where you are looking, and the lines show your field of view.\nEach symbol has a shape and a letter, so colour is never the only cue."},
	{"title": "Try it: inspect a contact", "diagram": "practice_select",
		"text": "Left-click a marker, a radar symbol or a row in the Contacts list to select it. Hovering shows its range.\nPractice: click contact T2 on the practice radar."},
	{"title": "Try it: classify", "diagram": "practice_classify",
		"text": "With a contact selected, the mouse wheel moves the highlight in the decision card (↑ ↓ also work). 1, 2 and 3 set the confidence.\nRight-click (or Enter) confirms. Practice: scroll to \"Unknown / insufficient evidence\" and right-click."},
	{"title": "Choose a response", "diagram": "respond",
		"text": "After classifying, the card moves to the response. Routine responses are confirmed with one right-click.\nAlarm responses (notify the supervisor, training-area alert) ask for one more explicit Confirm, so they never happen by accident."},
	{"title": "Revise or cancel", "diagram": "revise",
		"text": "Backspace (or Back) goes one step back. You may revise a classification until you give a response; more than three changes count as repeated actions.\nA response is final for that contact. Swarm decisions apply to the whole group, and the card says so before you confirm."},
	{"title": "How the exercise ends", "diagram": "end",
		"text": "The exercise ends when its time runs out. Esc pauses it and lets you restart, change settings, replay this tutorial or exit.\nContacts that are never classified or answered count as missed."},
	{"title": "Score and report", "diagram": "report",
		"text": "Your score comes from: noticing contacts quickly, classifying them correctly, matching confidence to evidence, choosing suitable responses in time, and handling degraded sensors.\nAfter the exercise, a short report lists what went well, what to improve, and what to practise next."},
]

var step_index := 0
var practice_done := {"practice_select": false, "practice_classify": false}
var embedded := false ## true when shown over a paused exercise
var title_label: Label
var text_label: Label
var counter_label: Label
var diagram: Control
var practice_box: VBoxContainer
var practice_radar: RadarDisplay
var practice_options: VBoxContainer
var practice_feedback: Label
var practice_highlight := 0
var next_button: Button
var back_button: Button
var skip_button: Button
var skip_confirm: HBoxContainer


## Draws the static diagrams with the same symbol styles as the real radar.
class Diagram extends Control:
	var kind := ""

	func _draw() -> void:
		var font := get_theme_default_font()
		var c := size * 0.5
		var muted := Color(0.7, 0.75, 0.8)
		match kind:
			"task":
				draw_rect(Rect2(c + Vector2(-140, 40), Vector2(40, 60)), Color(0.45, 0.38, 0.3))
				draw_string(font, c + Vector2(-160, 120), "observation post", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, muted)
				draw_arc(c + Vector2(-120, 80), 150, -PI * 0.75, -PI * 0.1, 32, Color(0.45, 0.95, 0.55, 0.6), 2.0)
				for p in [Vector2(40, -60), Vector2(100, -10), Vector2(10, 10)]:
					_symbol("track", c + p)
				draw_string(font, c + Vector2(60, 60), "contacts in the sky", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, muted)
			"views":
				for i in 2:
					var r := Rect2(c + Vector2(-230 + i * 240, -70), Vector2(210, 130))
					draw_rect(r, Color(0.3, 0.4, 0.5) if i == 0 else Color(0.25, 0.25, 0.25))
					draw_string(font, r.position + Vector2(8, 20), ["Eye view", "Sensor camera (V)"][i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
					_brackets(r.get_center() + Vector2(-30, 10), Color(0.35, 1.0, 0.45), false)
					_brackets(r.get_center() + Vector2(40, -15), Color(1.0, 0.65, 0.2), true)
				draw_string(font, c + Vector2(-230, 90), "solid: recent update     dashed: no update, position estimated", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, muted)
			"symbols":
				var y := -80.0
				for k in ["track", "group", "zone"]:
					_symbol(k, c + Vector2(-150, y))
					draw_string(font, c + Vector2(-120, y + 5), RadarDisplay.STYLES[k]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
					y += 40.0
				var stale := Color(0.45, 1.0, 0.55, 0.5)
				draw_rect(Rect2(c + Vector2(-156, y - 6), Vector2(12, 12)), stale, false, 1.5)
				draw_string(font, c + Vector2(-120, y + 5), "Coasting track (shown with ?): last estimate only", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
				y += 40.0
				draw_line(c + Vector2(-150, y + 20), c + Vector2(-170, y - 15), Color(1, 1, 1, 0.5))
				draw_line(c + Vector2(-150, y + 20), c + Vector2(-130, y - 15), Color(1, 1, 1, 0.5))
				draw_string(font, c + Vector2(-120, y + 5), "Your field of view", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
			"respond":
				_card(c + Vector2(-170, -80), ["Continue observing", "Request additional identification", "Log the observation", "Notify the supervisor (alarm)"], 3)
				draw_rect(Rect2(c + Vector2(-170, 70), Vector2(340, 40)), Color(1.0, 0.6, 0.25, 0.25))
				draw_string(font, c + Vector2(-160, 96), "Confirm: Notify the supervisor? This is final.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.7, 0.35))
			"revise":
				var labels := ["1  Classify", "2  Respond", "✓ final"]
				for i in labels.size():
					draw_rect(Rect2(c + Vector2(-220 + i * 160, -20), Vector2(130, 40)), Color(0.13, 0.15, 0.17))
					draw_string(font, c + Vector2(-205 + i * 160, 6), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
				draw_string(font, c + Vector2(-200, 60), "← Backspace goes back a step (until the response)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, muted)
			"end":
				draw_string(font, c + Vector2(-60, -10), "00:00", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color.WHITE)
				draw_string(font, c + Vector2(-80, 30), "time runs out → exercise ends", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, muted)
			"report":
				var parts := ["Mission result", "What went well", "What to improve", "Important decisions", "Next practice"]
				for i in parts.size():
					draw_rect(Rect2(c + Vector2(-150, -100 + i * 40), Vector2(300, 32)), Color(0.13, 0.15, 0.17))
					draw_string(font, c + Vector2(-140, -78 + i * 40), parts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)

	func _symbol(kind: String, p: Vector2) -> void:
		var style: Dictionary = RadarDisplay.STYLES[kind]
		var color: Color = style["color"]
		match style["shape"]:
			"square":
				draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), color)
			"hexagon":
				var hex := PackedVector2Array()
				for k in 7:
					hex.append(p + Vector2(9, 0).rotated(TAU * k / 6.0))
				draw_polyline(hex, color, 2.0)
			"area":
				draw_arc(p, 9, 0, TAU, 16, color, 1.5)
		draw_string(get_theme_default_font(), p + Vector2(10, -6), style["letter"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

	func _brackets(p: Vector2, color: Color, dashed: bool) -> void:
		var half := 12.0
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var q: Vector2 = p + corner * half
			var arm := 4.0 if dashed else 7.0
			draw_line(q, q - Vector2(corner.x * arm, 0), color, 2.0)
			draw_line(q, q - Vector2(0, corner.y * arm), color, 2.0)

	func _card(at: Vector2, rows: Array, selected: int) -> void:
		var font := get_theme_default_font()
		for i in rows.size():
			var on: bool = i == selected
			draw_rect(Rect2(at + Vector2(0, i * 34), Vector2(340, 30)), Color(0.2, 0.17, 0.09) if on else Color(0.13, 0.15, 0.17))
			draw_string(font, at + Vector2(10, i * 34 + 21), ("▶ " if on else "   ") + rows[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.78, 0.25) if on else Color.WHITE)


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var background := ColorRect.new()
	background.color = Color(UiKit.BG, 0.97)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var column := UiKit.screen_column(self, 1100, 12)
	column.add_child(UiKit.heading("Threat detection tutorial"))
	var top := UiKit.hbox(12)
	title_label = UiKit.label("", 32)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_label)
	counter_label = UiKit.label("", 16, UiKit.MUTED)
	top.add_child(counter_label)
	column.add_child(top)
	text_label = UiKit.label("", 19, UiKit.TEXT, true)
	text_label.custom_minimum_size = Vector2(1100, 90)
	column.add_child(text_label)
	var stage := UiKit.panel(0.9)
	stage.custom_minimum_size = Vector2(1100, 380)
	column.add_child(stage)
	var stage_box := Control.new()
	stage_box.custom_minimum_size = Vector2(1076, 356)
	stage.add_child(stage_box)
	diagram = Diagram.new()
	diagram.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	diagram.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(diagram)
	practice_box = UiKit.vbox(8)
	practice_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	stage_box.add_child(practice_box)
	_build_practice()
	var buttons := UiKit.hbox(12)
	skip_button = UiKit.button("Skip tutorial", request_skip, 170)
	buttons.add_child(skip_button)
	skip_confirm = UiKit.hbox(8)
	skip_confirm.add_child(UiKit.label("Skip? You can replay it from the menu or the pause screen.", 15, UiKit.WARN))
	skip_confirm.add_child(UiKit.button("Skip", confirm_skip, 90))
	skip_confirm.add_child(UiKit.button("Keep going", func(): skip_confirm.visible = false, 140))
	skip_confirm.visible = false
	buttons.add_child(skip_confirm)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	back_button = UiKit.button("Back", previous, 120)
	buttons.add_child(back_button)
	next_button = UiKit.primary_button("Next", next, 200)
	buttons.add_child(next_button)
	column.add_child(buttons)
	show_step(0)


func _build_practice() -> void:
	practice_radar = RadarDisplay.new()
	practice_radar.scope_size = 300.0
	practice_radar.show_labels = true
	practice_radar.range_m = 1000.0
	practice_radar.title = "PRACTICE RADAR"
	practice_radar.legend_kinds = PackedStringArray(["track", "group", "zone"])
	practice_radar.view_fov_deg = 70.0
	practice_radar.contacts = [
		{"id": "T1", "kind": "track", "position": Vector3(-300, 50, -500), "label": "T1"},
		{"id": "T2", "kind": "track", "position": Vector3(250, 60, -350), "label": "T2"},
		{"id": "T3", "kind": "track", "position": Vector3(100, 40, -800), "label": "T3", "stale": true},
	]
	practice_radar.contact_clicked.connect(_on_practice_click)
	practice_box.add_child(practice_radar)
	practice_options = UiKit.vbox(2)
	practice_options.mouse_filter = Control.MOUSE_FILTER_STOP
	practice_options.custom_minimum_size = Vector2(420, 220)
	practice_options.gui_input.connect(_on_practice_classify_input)
	practice_box.add_child(practice_options)
	practice_feedback = UiKit.label("", 17, UiKit.GOOD)
	practice_box.add_child(practice_feedback)


func show_step(index: int) -> void:
	step_index = clampi(index, 0, STEPS.size() - 1)
	var step: Dictionary = STEPS[step_index]
	title_label.text = step["title"]
	text_label.text = step["text"]
	counter_label.text = "Step %d of %d" % [step_index + 1, STEPS.size()]
	var kind: String = step["diagram"]
	diagram.kind = kind
	diagram.visible = not kind.begins_with("practice")
	diagram.queue_redraw()
	practice_box.visible = kind.begins_with("practice")
	practice_radar.visible = kind == "practice_select"
	practice_options.visible = kind == "practice_classify"
	practice_feedback.text = "Done ✓" if practice_done.get(kind, false) else ""
	if kind == "practice_classify":
		_render_practice_options()
	back_button.disabled = step_index == 0
	next_button.text = "Start training" if step_index == STEPS.size() - 1 and not embedded else ("Close tutorial" if step_index == STEPS.size() - 1 else "Next")
	skip_confirm.visible = false
	step_changed.emit(step_index)


func next() -> void:
	if step_index >= STEPS.size() - 1:
		finished.emit(false)
		return
	show_step(step_index + 1)


func previous() -> void:
	show_step(step_index - 1)


## Skipping asks once for confirmation.
func request_skip() -> void:
	skip_confirm.visible = true


func confirm_skip() -> void:
	finished.emit(true)


func _on_practice_click(id: String) -> void:
	practice_radar.selected_id = id
	if id == "T2":
		practice_done["practice_select"] = true
		practice_feedback.text = "Done ✓ — T2 is selected. Press Next."
	else:
		practice_feedback.text = "That is %s. Click T2." % id


func _render_practice_options() -> void:
	for child in practice_options.get_children():
		child.queue_free()
	practice_options.add_child(UiKit.label("Practice card · contact T2 · scroll, then right-click", 14, UiKit.ACCENT))
	for i in Vocabulary.CATEGORIES.size():
		var on := i == practice_highlight
		practice_options.add_child(UiKit.label(("▶  " if on else "    ") + Vocabulary.CATEGORY_LABELS[Vocabulary.CATEGORIES[i]], 16, UiKit.ACCENT if on else UiKit.TEXT))


## Wheel moves the highlight; right-click confirms (same as the real card).
func _on_practice_classify_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_DOWN:
			practice_scroll(1)
		MOUSE_BUTTON_WHEEL_UP:
			practice_scroll(-1)
		MOUSE_BUTTON_RIGHT:
			practice_confirm()


func practice_scroll(delta: int) -> void:
	practice_highlight = posmod(practice_highlight + delta, Vocabulary.CATEGORIES.size())
	_render_practice_options()


func practice_confirm() -> bool:
	var chosen: String = Vocabulary.CATEGORIES[practice_highlight]
	if chosen == "unknown":
		practice_done["practice_classify"] = true
		practice_feedback.text = "Done ✓ — classified as Unknown with low confidence. Press Next."
		return true
	practice_feedback.text = "You confirmed \"%s\". Scroll to \"Unknown / insufficient evidence\" and right-click." % Vocabulary.CATEGORY_LABELS[chosen]
	return false
