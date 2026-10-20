extends VBoxContainer
## Practical settings shared by the Settings screen and the in-game pause menu.
## Every change is applied at once and saved to the local settings file.

const SettingsStore := preload("res://scripts/app/settings_store.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")

signal changed(key: String)

var sliders := {} ## setting key -> HSlider
var mute_toggle: CheckBox
var quality_option: OptionButton
var value_labels := {}


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UiKit.heading("Audio"))
	_slider_row("master_volume", "Master volume", 0.0, 1.0, 0.05, true)
	_slider_row("sfx_volume", "Sound effects", 0.0, 1.0, 0.05, true)
	_slider_row("ambience_volume", "Drone motor and ambience", 0.0, 1.0, 0.05, true)
	mute_toggle = CheckBox.new()
	mute_toggle.text = "Mute all sound (every alert also has an on-screen sign)"
	mute_toggle.button_pressed = SettingsStore.get_value("muted")
	mute_toggle.toggled.connect(func(on): _store("muted", on))
	add_child(mute_toggle)
	add_child(UiKit.heading("Controls"))
	_slider_row("mouse_sensitivity", "Mouse look sensitivity", 0.25, 3.0, 0.05, false)
	add_child(UiKit.heading("Graphics"))
	var row := UiKit.hbox(12)
	var caption := UiKit.label("Effects quality", 16)
	caption.custom_minimum_size = Vector2(240, 0)
	row.add_child(caption)
	quality_option = OptionButton.new()
	quality_option.add_item("Standard (shadows on)")
	quality_option.add_item("Reduced (no shadows, for slower laptops)")
	quality_option.select(SettingsStore.QUALITY.find(SettingsStore.get_value("quality")))
	quality_option.item_selected.connect(func(i): _store("quality", SettingsStore.QUALITY[i]))
	row.add_child(quality_option)
	add_child(row)
	add_child(UiKit.label("Quality changes apply from the next mission or exercise.", 14, UiKit.MUTED))
	add_child(UiKit.button("Reset settings to defaults", reset_defaults, 260))


func _slider_row(key: String, text: String, low: float, high: float, step: float, percent: bool) -> void:
	var row := UiKit.hbox(12)
	var caption := UiKit.label(text, 16)
	caption.custom_minimum_size = Vector2(240, 0)
	row.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.custom_minimum_size = Vector2(260, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = float(SettingsStore.get_value(key))
	var value_label := UiKit.label("", 16, UiKit.ACCENT)
	value_label.custom_minimum_size = Vector2(64, 0)
	value_labels[key] = value_label
	var display := func(v: float) -> void:
		value_label.text = ("%d%%" % roundi(v * 100.0)) if percent else ("×%.2f" % v)
	display.call(slider.value)
	slider.value_changed.connect(func(v):
		display.call(v)
		_store(key, v))
	row.add_child(slider)
	row.add_child(value_label)
	sliders[key] = slider
	add_child(row)


func _store(key: String, value: Variant) -> void:
	SettingsStore.set_value(key, value)
	SettingsStore.save()
	changed.emit(key)


func reset_defaults() -> void:
	SettingsStore.reset_to_defaults()
	SettingsStore.save()
	for key in sliders:
		sliders[key].set_value_no_signal(float(SettingsStore.get_value(key)))
		value_labels[key].text = ("×%.2f" % sliders[key].value) if key == "mouse_sensitivity" else ("%d%%" % roundi(sliders[key].value * 100.0))
	mute_toggle.set_pressed_no_signal(SettingsStore.get_value("muted"))
	quality_option.select(SettingsStore.QUALITY.find(SettingsStore.get_value("quality")))
	changed.emit("all")
