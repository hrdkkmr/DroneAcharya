extends Control
## Observation-mode HUD. Shows only trainee-visible information: scenario conditions,
## sensor status, tracker output and the trainee's own actions. It never reads ground
## truth. User actions are reported through signals; observation_main.gd acts on them.
##
## Layout (1600×900 design): status card (top left), decision card for the selected
## contact (bottom left), contacts list with collapsible details and decision support
## (top right), radar (bottom right). Everything secondary is collapsed or moved to
## the after-action report.
##
## Decision card workflow (one card, bound to the selected contact):
##   step "classify": wheel / ↑↓ change the highlighted category, 1/2/3 the confidence,
##                    right-click / Enter confirms (an unacknowledged contact is marked
##                    seen at the same time);
##   step "respond":  wheel / ↑↓ change the highlighted response, right-click / Enter
##                    confirms routine responses at once;
##   step "confirm":  alarm responses (notify supervisor, area alert) need one more
##                    explicit Confirm click (or Enter); Backspace / Cancel goes back;
##   step "done":     the response is final; further confirms are ignored (no penalty).
## The card only ever acts on the contact it is bound to.

signal track_selected(track_id: String)
signal centre_requested
signal resume_requested
signal restart_requested
signal exit_requested
signal tutorial_requested
signal acknowledge_requested
signal classify_requested(category: String, confidence: int)
signal respond_requested(response: String)
signal deselect_requested
signal decision_support_toggled(visible: bool)
signal review_requested
signal replay_play_toggled
signal replay_speed_changed(speed: float)
signal replay_seek_requested(tick: int)
signal truth_labels_toggled(visible: bool)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const RadarDisplay := preload("res://scripts/ui/radar_display.gd")
const ControlsReference := preload("res://scripts/ui/controls_reference.gd")
const Vocabulary := preload("res://scripts/ai/vocabulary.gd")
const AudioCues := preload("res://scripts/audio/audio_cues.gd")
const PAUSE_ACTIONS := [["resume", "Resume"], ["restart", "Restart exercise"], ["controls", "Controls"], ["settings", "Settings"], ["tutorial", "Tutorial"], ["menu", "Exit to menu"]]
const RESULT_ACTIONS := [["restart", "Run again"], ["menu", "Exit to menu"]]
const CONFIDENCE_LEVELS := [["Low", 30], ["Medium", 60], ["High", 90]]
const CONFIRM_GUARD_MS := 350 ## ignore a second confirm this soon (double click)
const LEFT_WIDTH := 450.0
const RIGHT_WIDTH := 420.0

## One-line help shown for the highlighted option.
const CATEGORY_HELP := {
	"bird": "Biological: wing beat seen, winding path, no ID reply.",
	"balloon": "Drifts with the wind; slow and steady.",
	"authorised_uav": "Sends a cooperative ID reply.",
	"unidentified_uav": "Powered flight, no ID reply, not a bird.",
	"swarm": "Several tracks moving together. Applies to the whole group.",
	"unknown": "Not enough evidence yet. Keep the confidence low.",
}
const RESPONSE_HELP := {
	"continue_observing": "Keep watching without further action.",
	"request_identification": "Ask for more identification of this contact.",
	"log_observation": "Record it. No alarm is raised.",
	"notify_supervisor": "Raises an alarm to the supervisor. Asks you to confirm.",
	"training_area_alert": "Area-level alarm. Asks you to confirm.",
}

# Panels and labels (names kept stable for tests and the replay screen).
var info_label: Label
var clock_label: Label
var objective_label: Label
var alerts_box: VBoxContainer
var sensor_label: RichTextLabel
var track_tree: Tree
var details_label: RichTextLabel
var overlay: PauseMenu
var overlay_title: Label
var overlay_detail: Label
var right_column: VBoxContainer
var left_column: VBoxContainer
var sensor_shade: ColorRect
var trainee_label: Label
var feedback_label: Label
var support_toggle: CheckBox
var support_label: RichTextLabel
var decision_panel: PanelContainer
var review_button: Button
var replay_bar: PanelContainer
var replay_slider: HSlider
var replay_time: Label
var replay_play: Button
var truth_toggle: CheckBox
var radar: RadarDisplay
var tutorial_layer: Control

# Decision card state (UI only; the session holds the trainee's actual decisions).
var card_track := ""
var card_step := "none" ## none | classify | respond | confirm | done
var highlight := {"classify": 5, "respond": 0}
var confidence := 60
var card_header: RichTextLabel
var card_scope: Label
var card_steps: RichTextLabel
var card_options: VBoxContainer
var card_help: Label
var confidence_row: HBoxContainer
var confirm_row: HBoxContainer
var confirm_text: Label
var card_hint: Label
var card_confirm_button: Button

var _session: RefCounted
var _replay_end := 1
var _slider_updating := false
var _rows := {} ## track id or "group:Sxx" -> TreeItem
var _refresh_left := 0.0
var _busy_until_ms := 0
## True while the Contacts list is selecting a row from code: that only mirrors the
## current selection and must not re-bind (and so reset) the decision card.
var _syncing_selection := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiKit.theme()
	sensor_shade = ColorRect.new()
	sensor_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sensor_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/sensor_view.gdshader")
	sensor_shade.material = material
	sensor_shade.visible = false
	add_child(sensor_shade)
	var reticle := UiKit.label("+", 28, Color(1, 1, 1, 0.6))
	reticle.name = "Reticle"
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.position -= Vector2(8, 20)
	sensor_shade.add_child(reticle)
	_build_status_card()
	_build_decision_card()
	_build_right_column()
	_build_radar()
	_build_overlay()


# --- Layout ----------------------------------------------------------------------

func _build_status_card() -> void:
	left_column = UiKit.vbox(8)
	left_column.position = Vector2(16, 16)
	left_column.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	add_child(left_column)
	var card := UiKit.panel(0.8)
	card.name = "Status"
	left_column.add_child(card)
	var rows := UiKit.vbox(4)
	card.add_child(rows)
	info_label = UiKit.label("", 14, UiKit.ACCENT)
	rows.add_child(info_label)
	var clock_row := UiKit.hbox(10)
	clock_label = UiKit.label("00:00", 30, Color.WHITE)
	clock_row.add_child(clock_label)
	var left_caption := UiKit.label("left", 15, UiKit.MUTED)
	left_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_row.add_child(left_caption)
	rows.add_child(clock_row)
	objective_label = UiKit.label("Select each contact, classify it and choose a response.", 15, UiKit.TEXT, true)
	objective_label.custom_minimum_size = Vector2(LEFT_WIDTH - 30, 0)
	rows.add_child(objective_label)
	alerts_box = UiKit.vbox(4)
	rows.add_child(alerts_box)
	sensor_label = UiKit.rich(14)
	sensor_label.custom_minimum_size = Vector2(LEFT_WIDTH - 30, 0)
	rows.add_child(_section("Sensor status", sensor_label, false))


func _build_decision_card() -> void:
	decision_panel = UiKit.card(0.9)
	decision_panel.name = "DecisionCard"
	decision_panel.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	decision_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	decision_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(decision_panel)
	var rows := UiKit.vbox(6)
	decision_panel.add_child(rows)
	rows.add_child(UiKit.heading("Selected contact"))
	card_header = UiKit.rich(16)
	rows.add_child(card_header)
	card_scope = UiKit.label("", 14, UiKit.INFO, true)
	card_scope.custom_minimum_size = Vector2(LEFT_WIDTH - 30, 0)
	rows.add_child(card_scope)
	card_steps = UiKit.rich(15)
	rows.add_child(card_steps)
	card_options = UiKit.vbox(2)
	rows.add_child(card_options)
	card_help = UiKit.label("", 14, UiKit.MUTED, true)
	card_help.custom_minimum_size = Vector2(LEFT_WIDTH - 30, 0)
	rows.add_child(card_help)
	confidence_row = UiKit.hbox(6)
	confidence_row.add_child(UiKit.label("Confidence", 14, UiKit.MUTED))
	for level in CONFIDENCE_LEVELS:
		var chip := UiKit.no_focus(UiKit.button("", set_confidence.bind(level[1]), 104)) as Button
		chip.add_theme_font_size_override("font_size", 14)
		chip.custom_minimum_size.y = 30
		chip.set_meta("value", level[1])
		chip.set_meta("label", level[0])
		confidence_row.add_child(chip)
	rows.add_child(confidence_row)
	confirm_row = UiKit.hbox(8)
	confirm_text = UiKit.label("", 15, UiKit.WARN, true)
	confirm_text.custom_minimum_size = Vector2(LEFT_WIDTH - 30, 0)
	rows.add_child(confirm_text)
	confirm_row.add_child(UiKit.no_focus(UiKit.primary_button("Confirm", confirm, 160)))
	confirm_row.add_child(UiKit.no_focus(UiKit.button("Cancel", back, 120)))
	rows.add_child(confirm_row)
	var actions := UiKit.hbox(8)
	var confirm_button := UiKit.no_focus(UiKit.button("Confirm  (right-click)", confirm, 210)) as Button
	confirm_button.name = "ConfirmButton"
	card_confirm_button = confirm_button
	actions.add_child(confirm_button)
	actions.add_child(UiKit.no_focus(UiKit.button("Back", back, 90)))
	actions.add_child(UiKit.no_focus(UiKit.button("Centre", func(): centre_requested.emit(), 90)))
	rows.add_child(actions)
	feedback_label = UiKit.label("", 15, UiKit.ACCENT, true)
	feedback_label.custom_minimum_size = Vector2(LEFT_WIDTH - 30, 0)
	rows.add_child(feedback_label)
	trainee_label = UiKit.label("", 14, UiKit.MUTED, true)
	trainee_label.custom_minimum_size = Vector2(LEFT_WIDTH - 30, 0)
	rows.add_child(trainee_label)
	card_hint = UiKit.label("Wheel or ↑↓: change · Right-click or Enter: confirm · Backspace: back", 13, UiKit.MUTED, true)
	card_hint.custom_minimum_size = Vector2(LEFT_WIDTH - 30, 0)
	rows.add_child(card_hint)
	_render_card()


func _build_right_column() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "RightColumn"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE, Control.PRESET_MODE_KEEP_SIZE)
	scroll.offset_left = -RIGHT_WIDTH - 16
	scroll.offset_right = -16
	scroll.offset_top = 16
	scroll.offset_bottom = -330
	add_child(scroll)
	right_column = UiKit.vbox(8)
	right_column.custom_minimum_size = Vector2(RIGHT_WIDTH, 0)
	scroll.add_child(right_column)
	var contacts := UiKit.panel(0.8)
	right_column.add_child(contacts)
	var rows := UiKit.vbox(4)
	contacts.add_child(rows)
	rows.add_child(UiKit.heading("Contacts"))
	track_tree = Tree.new()
	track_tree.columns = 4
	track_tree.hide_root = true
	track_tree.select_mode = Tree.SELECT_ROW
	track_tree.column_titles_visible = true
	for i in 4:
		track_tree.set_column_title(i, ["Contact", "State", "Range", "Your call"][i])
		track_tree.set_column_expand(i, i == 0 or i == 3)
		track_tree.set_column_custom_minimum_width(i, [158, 86, 64, 96][i])
	track_tree.custom_minimum_size = Vector2(RIGHT_WIDTH - 24, 210)
	track_tree.add_theme_font_size_override("font_size", 14)
	track_tree.item_selected.connect(_on_tree_selected)
	track_tree.focus_mode = Control.FOCUS_NONE
	track_tree.create_item()
	rows.add_child(track_tree)
	details_label = UiKit.rich(14)
	details_label.custom_minimum_size = Vector2(RIGHT_WIDTH - 24, 0)
	right_column.add_child(_panel_section("Contact details", details_label, false))
	var support := UiKit.panel(0.8)
	right_column.add_child(support)
	var support_rows := UiKit.vbox(4)
	support.add_child(support_rows)
	support_toggle = CheckBox.new()
	support_toggle.text = "Decision support (training aid)"
	support_toggle.focus_mode = Control.FOCUS_NONE
	support_toggle.button_pressed = true
	support_toggle.toggled.connect(_on_support_toggled)
	support_rows.add_child(support_toggle)
	support_label = UiKit.rich(14)
	support_label.custom_minimum_size = Vector2(RIGHT_WIDTH - 24, 0)
	support_rows.add_child(support_label)


func _build_radar() -> void:
	radar = RadarDisplay.new()
	radar.name = "Radar"
	radar.title = "RADAR · tracks"
	radar.legend_kinds = PackedStringArray(["track", "group", "zone"])
	radar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	radar.offset_left = -radar.scope_size - 16
	radar.offset_top = -radar.scope_size - 16 - 28
	radar.offset_right = -16
	radar.offset_bottom = -16
	radar.contact_clicked.connect(func(id): track_selected.emit(id))
	add_child(radar)


## A header button that shows or hides `content` (for secondary information).
func _section(title: String, content: Control, expanded: bool) -> VBoxContainer:
	var box := UiKit.vbox(2)
	var toggle := Button.new()
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_font_size_override("font_size", 14)
	toggle.add_theme_color_override("font_color", UiKit.ACCENT)
	var update := func():
		toggle.text = ("▾ " if content.visible else "▸ ") + title.to_upper()
	toggle.pressed.connect(func():
		content.visible = not content.visible
		update.call())
	content.visible = expanded
	update.call()
	box.add_child(toggle)
	box.add_child(content)
	return box


func _panel_section(title: String, content: Control, expanded: bool) -> PanelContainer:
	var panel := UiKit.panel(0.8)
	panel.add_child(_section(title, content, expanded))
	return panel


func _on_support_toggled(on: bool) -> void:
	support_label.visible = on
	decision_support_toggled.emit(on)


# --- Decision card ---------------------------------------------------------------

## Binds the card to `track_id` (or clears it) and starts at the right step.
func bind_card(session: RefCounted, track_id: String) -> void:
	_session = session
	card_track = track_id
	if track_id.is_empty():
		card_step = "none"
		_render_card()
		return
	var state: Dictionary = session.trainee_state(track_id)
	var category: String = state.get("category", "")
	highlight["classify"] = Vocabulary.CATEGORIES.find(category if not category.is_empty() else "unknown")
	highlight["respond"] = 0
	confidence = int(state.get("confidence", 30)) if not category.is_empty() else 30
	if not String(state.get("response", "")).is_empty():
		card_step = "done"
	elif not category.is_empty():
		card_step = "respond"
	else:
		card_step = "classify"
	_render_card()


## Mouse wheel / arrow keys: moves the highlight of the bound contact's current step.
## Returns false (and changes nothing) when no contact is bound.
func cycle_option(delta: int) -> bool:
	if card_track.is_empty() or card_step in ["none", "done", "confirm"]:
		return false
	var count := Vocabulary.CATEGORIES.size() if card_step == "classify" else Vocabulary.RESPONSES.size()
	highlight[card_step] = posmod(int(highlight[card_step]) + delta, count)
	_render_card()
	return true


func set_confidence(value: int) -> void:
	confidence = clampi(value, 0, 100)
	_render_card()


func highlighted_category() -> String:
	return Vocabulary.CATEGORIES[highlight["classify"]]


func highlighted_response() -> String:
	return Vocabulary.RESPONSES[highlight["respond"]]


## Right-click / Enter / Confirm button. Returns what happened (for tests):
## "none", "busy", "classify", "respond", "confirm_needed", "final".
func confirm() -> String:
	if card_track.is_empty() or card_step == "none":
		show_feedback("Select a contact first: click its marker, its radar symbol or its row.", false)
		return "none"
	if Time.get_ticks_msec() < _busy_until_ms:
		return "busy"
	_busy_until_ms = Time.get_ticks_msec() + CONFIRM_GUARD_MS
	match card_step:
		"classify":
			classify_requested.emit(highlighted_category(), confidence)
			return "classify"
		"respond":
			if highlighted_response() in Vocabulary.ALARM_RESPONSES:
				card_step = "confirm"
				_render_card()
				AudioCues.play_global("confirm_needed")
				return "confirm_needed"
			respond_requested.emit(highlighted_response())
			return "respond"
		"confirm":
			respond_requested.emit(highlighted_response())
			return "respond"
	show_feedback("%s already has a final response." % card_track, false)
	return "final"


## Backspace / Back / Cancel: one step back without touching other contacts.
func back() -> void:
	match card_step:
		"confirm":
			card_step = "respond"
		"respond":
			card_step = "classify"
			show_feedback("Revise the classification, or press Back again to leave this contact.", true)
		_:
			deselect_requested.emit()
			return
	_render_card()


## Called by observation_main after the session accepted or rejected an action.
func on_result(kind: String, ok: bool) -> void:
	if ok:
		if kind == "classify":
			card_step = "respond"
		elif kind == "respond":
			card_step = "done"
	_render_card()


## Legacy keyboard shortcuts (K / Enter in Stage 3): submit the highlighted option.
func submit_classification() -> void:
	classify_requested.emit(highlighted_category(), confidence)


func submit_response() -> void:
	respond_requested.emit(highlighted_response())


func _render_card() -> void:
	if card_options == null:
		return
	for child in card_options.get_children():
		child.queue_free()
	var has := not card_track.is_empty() and card_step != "none"
	card_scope.visible = has
	card_steps.visible = has
	card_help.visible = has
	confidence_row.visible = has and card_step == "classify"
	confirm_row.visible = card_step == "confirm"
	confirm_text.visible = card_step == "confirm"
	card_confirm_button.visible = card_step != "confirm"
	if not has:
		card_header.text = "[color=#a0a8b0]No contact selected.[/color]"
		card_help.text = ""
		return
	card_header.text = _header_text()
	var steps := ["1  Classify", "2  Respond"]
	var active := 0 if card_step == "classify" else 1
	var parts := PackedStringArray()
	for i in steps.size():
		parts.append(("[b][color=#ffc740]%s[/color][/b]" if i == active and card_step != "done" else "[color=#8a949e]%s[/color]") % steps[i])
	card_steps.text = "   ›   ".join(parts) + ("   [color=#6fdc80]✓ final[/color]" if card_step == "done" else "")
	var category := highlighted_category() if card_step == "classify" else _current_category()
	var scope: Array = _session.decision_scope(card_track, category) if _session else [card_track]
	card_scope.text = "Applies to %s" % ("this contact only" if scope.size() <= 1 else "the whole swarm group (%d contacts: %s)" % [scope.size(), ", ".join(scope)])
	if card_step == "done":
		var state: Dictionary = _session.trainee_state(card_track) if _session else {}
		card_help.text = "Final response: %s. Select another contact." % Vocabulary.RESPONSE_LABELS.get(state.get("response", ""), "given")
		return
	var classify := card_step == "classify"
	var options: Array = Vocabulary.CATEGORIES if classify else Vocabulary.RESPONSES
	var labels: Dictionary = Vocabulary.CATEGORY_LABELS if classify else Vocabulary.RESPONSE_LABELS
	var current: int = highlight["classify" if classify else "respond"]
	for i in options.size():
		var on := i == current
		var row := UiKit.label(("▶  " if on else "    ") + labels[options[i]] + (" (alarm)" if not classify and options[i] in Vocabulary.ALARM_RESPONSES else ""),
			16 if on else 15, UiKit.ACCENT if on else UiKit.TEXT)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(_on_option_input.bind(i))
		card_options.add_child(row)
	card_help.text = (CATEGORY_HELP if classify else RESPONSE_HELP)[options[current]]
	for chip in confidence_row.get_children():
		if chip is Button:
			var value: int = chip.get_meta("value")
			chip.text = ("● " if value == confidence else "") + "%s %d%%" % [chip.get_meta("label"), value]
	if card_step == "confirm":
		confirm_text.text = "Confirm: %s for %s%s? This is final." % [Vocabulary.RESPONSE_LABELS[highlighted_response()], card_track,
			" and %d other contact(s)" % (scope.size() - 1) if scope.size() > 1 else ""]


## Clicking an option highlights it (mouse-first); confirming is still explicit.
func _on_option_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if card_step in ["classify", "respond"]:
			highlight[card_step] = index
			_render_card()


func _current_category() -> String:
	if _session == null:
		return ""
	return String(_session.trainee_state(card_track).get("category", ""))


func _header_text() -> String:
	if _session == null:
		return "[b]%s[/b]" % card_track
	var track: Dictionary = _session.tracker.tracks.get(card_track, {})
	if track.is_empty():
		return "[b]%s[/b] · [color=#ffa640]no longer tracked[/color]" % card_track
	var now: float = _session.time_s()
	var p: Vector3 = _session.tracker.estimated_position(track, now)
	var offset: Vector3 = p - _session.definition["observer_position"]
	var status: String = track["status"]
	var state := "[color=#ffa640]coasting (no update %.1f s)[/color]" % (now - float(track["last_update_t"])) if status == "coasting" else status
	return "[b]%s[/b] · %s · %.0f m · brg %03d° · alt %.0f m" % [card_track, state, offset.length(),
		int(fposmod(rad_to_deg(atan2(offset.x, -offset.z)), 360.0)), p.y]


func show_feedback(text: String, ok: bool) -> void:
	feedback_label.text = ("✓ " if ok else "✗ ") + text if not text.is_empty() else ""
	feedback_label.add_theme_color_override("font_color", UiKit.GOOD if ok else UiKit.WARN)


# --- Pause / results / replay ------------------------------------------------------

func _build_overlay() -> void:
	overlay = PauseMenu.new()
	overlay.name = "PauseMenu"
	add_child(overlay)
	overlay_title = overlay.title_label
	overlay_detail = overlay.detail_label
	overlay.action_pressed.connect(_on_overlay_action)
	review_button = UiKit.primary_button("Open the after-action report", func(): review_requested.emit(), 320)
	review_button.visible = false
	overlay.extra.add_child(review_button)
	_build_replay_bar()


func _on_overlay_action(id: String) -> void:
	match id:
		"resume":
			resume_requested.emit()
		"restart":
			restart_requested.emit()
		"menu":
			exit_requested.emit()
		"tutorial":
			tutorial_requested.emit()


func _build_replay_bar() -> void:
	replay_bar = UiKit.panel(0.85)
	replay_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	replay_bar.custom_minimum_size = Vector2(640, 0)
	replay_bar.position += Vector2(-320, -70)
	var row := UiKit.hbox(8)
	replay_bar.add_child(row)
	row.add_child(UiKit.label("REPLAY", 15, UiKit.ACCENT))
	replay_play = UiKit.no_focus(UiKit.button("Pause", func(): replay_play_toggled.emit(), 80)) as Button
	row.add_child(replay_play)
	var speed := OptionButton.new()
	speed.focus_mode = Control.FOCUS_NONE
	for s in ["1×", "2×", "4×", "8×"]:
		speed.add_item(s)
	speed.item_selected.connect(func(i): replay_speed_changed.emit([1.0, 2.0, 4.0, 8.0][i]))
	row.add_child(speed)
	replay_slider = HSlider.new()
	replay_slider.custom_minimum_size = Vector2(200, 0)
	replay_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replay_slider.focus_mode = Control.FOCUS_NONE
	replay_slider.value_changed.connect(_on_slider)
	row.add_child(replay_slider)
	replay_time = UiKit.label("00:00", 15)
	row.add_child(replay_time)
	truth_toggle = CheckBox.new()
	truth_toggle.text = "Truth labels"
	truth_toggle.focus_mode = Control.FOCUS_NONE
	truth_toggle.toggled.connect(func(on): truth_labels_toggled.emit(on))
	row.add_child(truth_toggle)
	replay_bar.visible = false
	add_child(replay_bar)


func _on_slider(value: float) -> void:
	if not _slider_updating:
		replay_seek_requested.emit(int(value))


## Replay mode hides trainee decision controls and shows the replay bar.
func set_replay_mode(enabled: bool, end_tick: int) -> void:
	replay_bar.visible = enabled
	decision_panel.visible = not enabled
	review_button.visible = false
	_replay_end = maxi(end_tick, 1)
	replay_slider.max_value = _replay_end
	_slider_updating = true
	replay_slider.value = 0
	_slider_updating = false


func update_replay(tick: int, playing: bool) -> void:
	_slider_updating = true
	replay_slider.value = tick
	_slider_updating = false
	replay_play.text = "Pause" if playing else "Play"
	replay_time.text = "%s / %s" % [clock(tick / 20.0), clock(_replay_end / 20.0)]


func set_review_available(available: bool) -> void:
	review_button.visible = available


func show_overlay(title: String, detail: String, actions: Array = RESULT_ACTIONS) -> void:
	overlay.open(title, detail, actions, ControlsReference.OBSERVATION)


func show_pause() -> void:
	review_button.visible = false
	show_overlay("Paused", "The exercise clock is stopped while paused.", PAUSE_ACTIONS)


func hide_overlay() -> void:
	overlay.close()


func set_sensor_view(enabled: bool, thermal: bool) -> void:
	sensor_shade.visible = enabled
	var material: ShaderMaterial = sensor_shade.material
	material.set_shader_parameter("thermal", 1.0 if thermal else 0.0)


# --- Refresh -----------------------------------------------------------------------

## Refreshes text panels (4 times per second) from the session's trainee-visible state.
func refresh(session: RefCounted, selected_id: String, view_text: String, delta: float) -> void:
	_session = session
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.25
	var c: Dictionary = session.config
	info_label.text = "%s · %s · %s · %s" % [c["title"].to_upper(), c["environment"], c["time_of_day"], c["visibility"]]
	clock_label.text = clock(session.remaining_s())
	sensor_label.text = sensor_text(session, view_text)
	_refresh_alerts(session)
	_refresh_tracks(session, selected_id)
	details_label.text = track_details(session, selected_id)
	trainee_label.text = trainee_text(session, selected_id)
	support_label.text = decision_support_text(session, selected_id)
	if not card_track.is_empty():
		card_header.text = _header_text()
	if sensor_shade.visible:
		(sensor_shade.material as ShaderMaterial).set_shader_parameter("seed", randf() * 100.0)


## Radar picture from tracker output only (never ground truth).
func update_radar(session: RefCounted, observer_position: Vector3, observer_yaw_deg: float, fov_deg: float, selected_id: String) -> void:
	radar.range_m = float(session.config["sensor"]["radar"]["range_m"])
	radar.own_position = observer_position
	radar.own_yaw = deg_to_rad(observer_yaw_deg)
	radar.view_fov_deg = fov_deg
	radar.selected_id = selected_id
	var now: float = session.time_s()
	var contacts := []
	for track in session.tracker.confirmed_tracks():
		contacts.append({"id": track["id"], "kind": "track", "position": session.tracker.estimated_position(track, now),
			"stale": track["status"] == "coasting", "velocity": track["velocity"], "label": track["id"]})
	for gid in session.tracker.groups:
		var group: Dictionary = session.tracker.groups[gid]
		contacts.append({"id": "group:" + gid, "kind": "group", "position": group["centroid"], "label": "%s (%d)" % [gid, group["members"].size()]})
	radar.contacts = contacts
	radar.marks = [{"kind": "zone", "position": Vector3.ZERO, "radius": float(session.definition["protected_zone"]["radius_m"])}]
	radar.status_text = "%d track%s" % [session.tracker.confirmed_tracks().size(), "" if session.tracker.confirmed_tracks().size() == 1 else "s"]


func _refresh_alerts(session: RefCounted) -> void:
	for child in alerts_box.get_children():
		child.queue_free()
	var severity: float = session.sensor.degradation_at(session.time_s())
	if severity > 0.0:
		alerts_box.add_child(_alert("! SENSOR DEGRADED", "%d%%: missed updates, delay, noise" % int(severity * 100), UiKit.WARN))
	var unseen := 0
	for track in session.tracker.confirmed_tracks():
		if session.trainee_state(track["id"]).is_empty():
			unseen += 1
	if unseen > 0:
		alerts_box.add_child(_alert("● NEW", "%d contact%s not yet inspected" % [unseen, "" if unseen == 1 else "s"], UiKit.INFO))


func _alert(word: String, detail: String, color: Color) -> HBoxContainer:
	var row := UiKit.hbox(8)
	row.add_child(UiKit.label(word, 15, color))
	row.add_child(UiKit.label(detail, 14, UiKit.TEXT))
	return row


static func sensor_text(session: RefCounted, view_text: String) -> String:
	var t: float = session.time_s()
	var severity: float = session.sensor.degradation_at(t)
	var radar_state := "[color=#ff9a40]DEGRADED (%d%%): missed updates, extra delay and noise[/color]" % int(severity * 100) if severity > 0.0 else "[color=#6fdc80]nominal[/color]"
	var confirmed := 0
	var coasting := 0
	for id in session.tracker.tracks:
		var status: String = session.tracker.tracks[id]["status"]
		confirmed += int(status == "confirmed")
		coasting += int(status == "coasting")
	var recent := 0.0
	var count := 0
	for i in range(session.observations.size() - 1, maxi(session.observations.size() - 40, -1), -1):
		var o: Dictionary = session.observations[i]
		recent += float(o["t_delivered"]) - float(o["t"])
		count += 1
	return "\n".join(PackedStringArray([
		"[b]Radar:[/b] " + radar_state,
		"[b]Camera range now:[/b] %.0f m (identification ≤ %.0f m)" % [session.sensor.eo_range_m(), session.sensor.eo_id_range_m()],
		"[b]Tracks:[/b] %d confirmed · %d coasting (no recent update) · %d swarm group(s)" % [confirmed, coasting, session.tracker.groups.size()],
		"[b]Delivery delay (recent):[/b] %s" % ("%.1f s" % (recent / count) if count else "—"),
		"[b]View:[/b] " + view_text,
	]))


## Contacts list: one row per confirmed track; tracks in a swarm group are nested
## under a group row (collapsed), so a large swarm takes one line.
func _refresh_tracks(session: RefCounted, selected_id: String) -> void:
	var now: float = session.time_s()
	var root := track_tree.get_root()
	var live := {}
	for gid in session.tracker.groups:
		var key: String = "group:" + gid
		live[key] = true
		var group_item: TreeItem = _rows.get(key)
		if group_item == null:
			group_item = root.create_child()
			group_item.set_metadata(0, key)
			group_item.collapsed = true
			_rows[key] = group_item
		var group: Dictionary = session.tracker.groups[gid]
		var offset: Vector3 = group["centroid"] - session.definition["observer_position"]
		group_item.set_text(0, "⬡ %s swarm (%d)" % [gid, group["members"].size()])
		group_item.set_text(1, "group")
		group_item.set_text(2, "%.0f m" % offset.length())
		group_item.set_text(3, _call_text(session, group["members"][0]))
		for i in 4:
			group_item.set_custom_color(i, Color(1.0, 0.6, 0.88))
	for track in session.tracker.confirmed_tracks():
		var id: String = track["id"]
		live[id] = true
		var group_id: String = track["swarm_group"]
		var parent: TreeItem = _rows.get("group:" + group_id, root) if not group_id.is_empty() else root
		var item: TreeItem = _rows.get(id)
		if item != null and item.get_parent() != parent:
			item.free()
			item = null
		if item == null:
			item = parent.create_child()
			item.set_metadata(0, id)
			_rows[id] = item
		var p: Vector3 = session.tracker.estimated_position(track, now)
		var offset: Vector3 = p - session.definition["observer_position"]
		var coasting: bool = track["status"] == "coasting"
		var values := ["□ " + id, "coasting ?" if coasting else "confirmed", "%.0f m" % offset.length(), _call_text(session, id)]
		for i in values.size():
			item.set_text(i, values[i])
			item.set_custom_color(i, Color(1.0, 0.65, 0.2) if coasting else Color.WHITE)
		if id == selected_id and not item.is_selected(0):
			# The row was re-created (e.g. the contact joined a swarm group): keep the
			# card's step and highlight, only refresh what it shows.
			if item.get_parent() != root:
				item.get_parent().collapsed = false
			_syncing_selection = true
			item.select(0)
			_syncing_selection = false
			_render_card()
	for key in _rows.keys():
		if not live.has(key):
			var row: TreeItem = _rows[key]
			_rows.erase(key)
			if is_instance_valid(row) and row.get_parent() != null:
				for child in row.get_children():
					_rows.erase(String(child.get_metadata(0)))
				row.free()


static func _call_text(session: RefCounted, track_id: String) -> String:
	var state: Dictionary = session.trainee_state(track_id)
	if state.is_empty():
		return "● new"
	if not String(state["response"]).is_empty():
		return "✓ " + Vocabulary.RESPONSE_LABELS[state["response"]].split(" ")[0].to_lower()
	if not String(state["category"]).is_empty():
		return "classified"
	return "seen"


## Trainee-visible facts about one track (tracker output only).
static func track_details(session: RefCounted, track_id: String) -> String:
	if track_id.is_empty():
		return "Select a contact: click its marker, its radar symbol or its row, or press Tab."
	var track: Dictionary = session.tracker.tracks.get(track_id, {})
	if track.is_empty():
		for retired in session.tracker.retired:
			if retired["id"] == track_id:
				return "[b]%s[/b] — %s at %s. No further observations." % [track_id, retired["status"], clock(float(retired["retired_t"]))]
		return "[b]%s[/b] — not available." % track_id
	var now: float = session.time_s()
	var lines := PackedStringArray()
	lines.append("[b]%s[/b] · %s · first seen %s%s" % [track_id, track["status"], clock(float(track["created_t"])),
		"  · swarm group %s" % track["swarm_group"] if not String(track["swarm_group"]).is_empty() else ""])
	var age := now - float(track["last_update_t"])
	if track["status"] == "coasting":
		lines.append("[color=#ffa640]No observation for %.1f s — position is extrapolated, not observed.[/color]" % age)
	var speed := Vector2(track["velocity"].x, track["velocity"].z).length()
	lines.append("Speed %.1f m/s · climb %+.1f m/s · altitude %.0f m" % [speed, track["velocity"].y, session.tracker.estimated_position(track, now).y])
	lines.append("Observations: %d radar · %d camera (%d at identification quality)" % [track["radar_hits"], track["eo_hits"], track["eo_id_hits"]])
	var reply := float(track["id_replies"]) / maxf(float(track["radar_hits"]), 1.0)
	lines.append("Cooperative ID reply: %s" % ("%d%% of radar returns" % int(reply * 100) if track["radar_hits"] > 0 else "no radar returns"))
	if track["sizes"].is_empty():
		lines.append("Apparent size / wing beat: not yet observed at identification quality")
	else:
		var total := 0.0
		for s in track["sizes"]:
			total += float(s)
		lines.append("Apparent size ≈ %.2f m · wing beat seen %d of %d" % [total / track["sizes"].size(), track["flaps"], track["eo_id_hits"]])
	lines.append("Mean signal quality %.2f · %d observation(s) during degradation" % [float(track["quality_sum"]) / maxf(float(track["hits"]), 1.0), track["degraded_hits"]])
	return "\n".join(lines)


static func trainee_text(session: RefCounted, track_id: String) -> String:
	if track_id.is_empty():
		return ""
	var state: Dictionary = session.trainee_state(track_id)
	if state.is_empty():
		return "%s: not yet inspected." % track_id
	var parts := PackedStringArray(["%s: seen %s" % [track_id, clock(float(state["acknowledged_t"]))]])
	if not String(state["category"]).is_empty():
		parts.append("classified %s (%d%%)" % [Vocabulary.CATEGORY_LABELS[state["category"]], state["confidence"]])
	if not String(state["response"]).is_empty():
		parts.append("response: %s (final)" % Vocabulary.RESPONSE_LABELS[state["response"]])
	return " · ".join(parts)


## Decision-support outputs for the selected track, labelled by method.
static func decision_support_text(session: RefCounted, track_id: String) -> String:
	if track_id.is_empty():
		return "Select a contact to see the training aid's assessment."
	var entry: Dictionary = session.decisions.recommendation_for(track_id)
	if entry.is_empty():
		return "[i]Waiting for the first assessment (once per second).[/i]"
	var rules: Dictionary = entry["rules"]
	var lines := PackedStringArray(["[i]Synthetic training aid; scores are not probabilities.[/i]"])
	lines.append("Rule-based baseline (not ML): %s · score %.2f · evidence %s" % [Vocabulary.CATEGORY_LABELS[rules["category"]], rules["confidence"], rules["evidence"]])
	lines.append("  %s" % rules["explanation"])
	var ml: Dictionary = entry["ml"]
	if not ml.is_empty():
		if ml.get("ok", false):
			lines.append("ML classifier %s: %s · score %.2f" % [ml["model"], Vocabulary.CATEGORY_LABELS[ml["category"]], ml["confidence"]])
		else:
			lines.append("ML classifier unavailable (%s); using the rule-based baseline." % ml.get("error", "error"))
	var policy: Dictionary = entry["policy"]
	lines.append("Recommended: [b]%s[/b] (%s, from %s)" % [Vocabulary.RESPONSE_LABELS[policy["response"]], policy["reason_code"], policy["based_on"]])
	lines.append("  %s" % policy["explanation"])
	return "\n".join(lines)


func select_row(track_id: String) -> void:
	var item: TreeItem = _rows.get(track_id)
	if item:
		if item.get_parent() != track_tree.get_root():
			item.get_parent().collapsed = false
		_syncing_selection = true
		item.select(0)
		_syncing_selection = false
		track_tree.scroll_to_item(item)


func _on_tree_selected() -> void:
	if _syncing_selection:
		return
	var item := track_tree.get_selected()
	if item == null:
		return
	var key := String(item.get_metadata(0))
	if key.begins_with("group:"):
		# A group row selects its first member; the card then shows the group scope.
		item.collapsed = false
		var first := item.get_first_child()
		if first:
			track_selected.emit(String(first.get_metadata(0)))
		return
	track_selected.emit(key)


static func clock(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
