extends Control
## Full-window pause / result screen used by flight training and threat observation.
## Shows a title, a short detail text and a row of action buttons; "Controls" and
## "Settings" open inside the same card. Runs while the tree is paused.
## The owning scene decides what each action does (signal `action_pressed`).

signal action_pressed(id: String)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")

var title_label: Label
var detail_label: Label
var extra: VBoxContainer ## optional content owned by the owning scene (e.g. a report button)
var buttons_row: HFlowContainer
var buttons := {} ## id -> Button
var controls_box: VBoxContainer
var settings_box: VBoxContainer
var settings_panel: SettingsPanel
var _controls_rows: Array = []
var _card: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = UiKit.card(0.96)
	_card.custom_minimum_size = Vector2(640, 0)
	center.add_child(_card)
	var rows := UiKit.vbox(12)
	_card.add_child(rows)
	title_label = UiKit.label("", 32)
	rows.add_child(title_label)
	detail_label = UiKit.label("", 17, UiKit.MUTED, true)
	detail_label.custom_minimum_size = Vector2(600, 0)
	rows.add_child(detail_label)
	extra = UiKit.vbox(8)
	rows.add_child(extra)
	controls_box = UiKit.vbox(4)
	controls_box.visible = false
	rows.add_child(controls_box)
	settings_box = UiKit.vbox(8)
	settings_box.visible = false
	settings_panel = SettingsPanel.new()
	settings_box.add_child(settings_panel)
	rows.add_child(settings_box)
	buttons_row = HFlowContainer.new()
	buttons_row.add_theme_constant_override("h_separation", 10)
	buttons_row.add_theme_constant_override("v_separation", 10)
	rows.add_child(buttons_row)
	visible = false


## Shows the screen. `actions` is an array of [id, label]; "controls" and "settings"
## are handled here (they toggle a section) and are also reported to the owner.
func open(title: String, detail: String, actions: Array, controls: Array = []) -> void:
	title_label.text = title
	detail_label.text = detail
	detail_label.visible = not detail.is_empty()
	_controls_rows = controls
	controls_box.visible = false
	settings_box.visible = false
	for id in buttons:
		buttons[id].queue_free()
	buttons.clear()
	for entry in actions:
		var id: String = entry[0]
		var button := UiKit.button(entry[1], _on_button.bind(id), 150)
		buttons_row.add_child(button)
		buttons[id] = button
	visible = true
	if not actions.is_empty() and is_inside_tree():
		_focus.call_deferred(buttons[actions[0][0]])


## Keyboard users can operate the menu; deferred, so the button may be gone by then.
func _focus(button: Button) -> void:
	if is_instance_valid(button) and button.is_inside_tree() and visible:
		button.grab_focus()


func close() -> void:
	visible = false
	controls_box.visible = false
	settings_box.visible = false
	if is_inside_tree():
		get_viewport().gui_release_focus()


func press(id: String) -> void:
	_on_button(id)


func _on_button(id: String) -> void:
	match id:
		"controls":
			_fill_controls()
			controls_box.visible = not controls_box.visible
			settings_box.visible = false
		"settings":
			settings_box.visible = not settings_box.visible
			controls_box.visible = false
	action_pressed.emit(id)


func _fill_controls() -> void:
	for child in controls_box.get_children():
		child.queue_free()
	controls_box.add_child(UiKit.heading("Controls"))
	for row in _controls_rows:
		controls_box.add_child(UiKit.key_line(row[0], row[1]))
