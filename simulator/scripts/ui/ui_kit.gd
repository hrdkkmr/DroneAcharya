extends RefCounted
## Shared visual language for every screen: dark neutral surfaces, one amber accent,
## readable text (14 px minimum), and status colours that are always paired with a
## word or a shape so nothing depends on colour alone. Layouts are designed at
## 1600×900; the project's canvas_items stretch mode scales them to other windows.

const BG := Color(0.055, 0.065, 0.075)
const SURFACE := Color(0.09, 0.105, 0.12)
const SURFACE_HI := Color(0.13, 0.15, 0.17)
const LINE := Color(0.24, 0.27, 0.3)
const PANEL := Color(0.03, 0.05, 0.08, 0.78)
const ACCENT := Color(1.0, 0.78, 0.25)
const ACCENT_DIM := Color(0.55, 0.43, 0.15)
const TEXT := Color(0.92, 0.93, 0.94)
const MUTED := Color(0.7, 0.75, 0.8)
const GOOD := Color(0.4, 0.85, 0.5)
const WARN := Color(1.0, 0.6, 0.25)
const BAD := Color(1.0, 0.4, 0.35)
const INFO := Color(0.45, 0.75, 1.0)

static var _theme: Theme


## One Theme instance shared by every screen (assign to the root Control).
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		t.set_stylebox(state, "Button", _button_box(state))
		t.set_stylebox(state, "OptionButton", _button_box(state))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.45))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	var flat := StyleBoxFlat.new()
	flat.bg_color = SURFACE
	flat.set_corner_radius_all(4)
	flat.set_content_margin_all(6)
	flat.border_color = LINE
	flat.set_border_width_all(1)
	for type in ["ItemList", "Tree", "LineEdit", "SpinBox", "TextEdit"]:
		t.set_stylebox("panel", type, flat)
		t.set_stylebox("normal", type, flat)
	t.set_stylebox("panel", "PopupMenu", flat)
	t.set_stylebox("panel", "TooltipPanel", flat)
	t.set_color("font_color", "TooltipLabel", TEXT)
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(ACCENT, 0.22)
	selected.border_color = ACCENT
	selected.set_border_width_all(1)
	for name in ["selected", "selected_focus", "cursor"]:
		t.set_stylebox(name, "ItemList", selected)
		t.set_stylebox(name, "Tree", selected)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("title_button_color", "Tree", ACCENT)
	var slider := StyleBoxFlat.new()
	slider.bg_color = LINE
	slider.set_content_margin_all(3)
	slider.set_corner_radius_all(3)
	t.set_stylebox("slider", "HSlider", slider)
	var fill := slider.duplicate()
	fill.bg_color = ACCENT_DIM
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	_theme = t
	return t


static func _button_box(state: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(4)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	box.bg_color = SURFACE_HI
	box.border_color = LINE
	box.set_border_width_all(1)
	match state:
		"hover", "hover_pressed":
			box.bg_color = Color(0.17, 0.19, 0.21)
			box.border_color = ACCENT_DIM
		"pressed":
			box.bg_color = Color(0.2, 0.18, 0.12)
			box.border_color = ACCENT
		"focus":
			box.draw_center = false
			box.border_color = ACCENT
			box.set_border_width_all(2)
		"disabled":
			box.bg_color = Color(SURFACE, 0.6)
			box.border_color = Color(LINE, 0.5)
	return box


static func panel_style(alpha := 0.78) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL, alpha)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	style.border_color = Color(LINE, 0.6)
	style.set_border_width_all(1)
	return style


static func panel(alpha := 0.78) -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", panel_style(alpha))
	return container


## A panel with a thin accent bar on the left, used for the primary card on a screen.
static func card(alpha := 0.9) -> PanelContainer:
	var container := panel(alpha)
	var style: StyleBoxFlat = container.get_theme_stylebox("panel")
	style.border_width_left = 3
	style.border_color = ACCENT_DIM
	return container


static func label(text: String, size := 16, color := TEXT, wrap := false) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	if wrap:
		result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


static func heading(text: String, size := 14) -> Label:
	return label(text.to_upper(), size, ACCENT)


static func rich(size := 16, fit := true) -> RichTextLabel:
	var result := RichTextLabel.new()
	result.bbcode_enabled = true
	result.fit_content = fit
	result.scroll_active = not fit
	result.add_theme_font_size_override("normal_font_size", size)
	result.add_theme_font_size_override("bold_font_size", size)
	result.add_theme_font_size_override("italics_font_size", size)
	return result


static func button(text: String, callback: Callable, min_width := 0.0) -> Button:
	var result := Button.new()
	result.text = text
	result.add_theme_font_size_override("font_size", 18)
	result.custom_minimum_size = Vector2(min_width, 40)
	result.pressed.connect(callback)
	return result


## The main call to action on a screen: accent outline and larger text.
static func primary_button(text: String, callback: Callable, min_width := 0.0) -> Button:
	var result := button(text, callback, min_width)
	result.custom_minimum_size.y = 48
	var box := _button_box("normal")
	box.border_color = ACCENT
	box.bg_color = Color(0.2, 0.17, 0.09)
	result.add_theme_stylebox_override("normal", box)
	return result


## In-game buttons must not take keyboard focus, so Space/Enter used for flying or
## deciding can never press them by accident.
static func no_focus(control: Control) -> Control:
	control.focus_mode = Control.FOCUS_NONE
	return control


static func vbox(separation := 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func hbox(separation := 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func spacer(height := 8.0) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


## Full-window dark background for menu screens (also applies the shared theme).
static func background(parent: Control) -> void:
	parent.theme = theme()
	var rect := ColorRect.new()
	rect.color = BG
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	var band := ColorRect.new()
	band.color = Color(ACCENT, 0.7)
	band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = 3
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(band)


## Screen header: small accent kicker, large title, optional muted subtitle.
static func header(kicker: String, title: String, subtitle := "") -> VBoxContainer:
	var box := vbox(2)
	box.add_child(heading(kicker, 14))
	box.add_child(label(title, 32))
	if not subtitle.is_empty():
		box.add_child(label(subtitle, 16, MUTED, true))
	return box


## Centred content column of fixed width on a full-window screen, with margins.
static func screen_column(parent: Control, width := 1200.0, separation := 12) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	parent.add_child(margin)
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(center)
	var column := vbox(separation)
	column.custom_minimum_size = Vector2(width, 0)
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(column)
	return column


## Key-cap style text for control references, e.g. key_line("Esc", "pause").
static func key_line(keys: String, action: String) -> HBoxContainer:
	var row := hbox(10)
	var cap := label(keys, 15, ACCENT)
	cap.custom_minimum_size = Vector2(170, 0)
	row.add_child(cap)
	row.add_child(label(action, 15, TEXT, true))
	row.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row
