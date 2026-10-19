extends RefCounted
## Small helpers so every menu and panel shares one readable style at 1600×900.

const BG := Color(0.05, 0.07, 0.09)
const PANEL := Color(0.03, 0.05, 0.08, 0.78)
const ACCENT := Color(1.0, 0.78, 0.25)
const MUTED := Color(0.7, 0.75, 0.8)
const GOOD := Color(0.4, 0.85, 0.5)
const WARN := Color(1.0, 0.6, 0.25)
const BAD := Color(1.0, 0.4, 0.35)


static func panel_style(alpha := 0.78) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL, alpha)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	return style


static func panel(alpha := 0.78) -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", panel_style(alpha))
	return container


static func label(text: String, size := 16, color := Color.WHITE, wrap := false) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	if wrap:
		result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


static func heading(text: String, size := 14) -> Label:
	return label(text.to_upper(), size, ACCENT)


static func button(text: String, callback: Callable, min_width := 0.0) -> Button:
	var result := Button.new()
	result.text = text
	result.add_theme_font_size_override("font_size", 18)
	result.custom_minimum_size = Vector2(min_width, 40)
	result.pressed.connect(callback)
	return result


static func vbox(separation := 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func hbox(separation := 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


## Full-window dark background for menu screens.
static func background(parent: Control) -> void:
	var rect := ColorRect.new()
	rect.color = BG
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
