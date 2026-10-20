extends Control
## Observation-mode HUD. Shows only trainee-visible information: scenario conditions,
## sensor status, tracker output and the trainee's own actions. It never reads ground
## truth. User actions are reported through signals; observation_main.gd acts on them.

signal track_selected(track_id: String)
signal centre_requested
signal resume_requested
signal restart_requested
signal exit_requested
signal acknowledge_requested
signal classify_requested(category: String, confidence: int)
signal respond_requested(response: String)
signal decision_support_toggled(visible: bool)
signal review_requested
signal replay_play_toggled
signal replay_speed_changed(speed: float)
signal replay_seek_requested(tick: int)
signal truth_labels_toggled(visible: bool)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const ControlsReference := preload("res://scripts/ui/controls_reference.gd")
const PAUSE_ACTIONS := [["resume", "Resume"], ["restart", "Restart exercise"], ["controls", "Controls"], ["settings", "Settings"], ["menu", "Exit to menu"]]
const RESULT_ACTIONS := [["restart", "Run again"], ["menu", "Exit to menu"]]
const Vocabulary := preload("res://scripts/ai/vocabulary.gd")
const RIGHT_WIDTH := 480.0
const LEFT_WIDTH := 430.0

var info_label: Label
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
var category_option: OptionButton
var confidence_slider: HSlider
var confidence_label: Label
var response_option: OptionButton
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
var _replay_end := 1
var _slider_updating := false

var _rows := {} ## track id -> TreeItem
var _refresh_left := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	var left := UiKit.vbox(8)
	left.position = Vector2(16, 48)
	left.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	left.size = Vector2(LEFT_WIDTH, 0)
	left_column = left
	add_child(left)
	var info_panel := UiKit.panel()
	info_label = UiKit.label("", 17)
	info_panel.add_child(info_label)
	left.add_child(info_panel)
	var sensor_panel := UiKit.panel()
	sensor_label = _rich(15)
	sensor_label.fit_content = true
	sensor_panel.add_child(sensor_label)
	left.add_child(sensor_panel)

	right_column = UiKit.vbox(8)
	right_column.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE, Control.PRESET_MODE_KEEP_SIZE)
	right_column.offset_left = -RIGHT_WIDTH - 16
	right_column.offset_right = -16
	right_column.offset_top = 16
	right_column.offset_bottom = -16
	add_child(right_column)
	right_column.add_child(UiKit.heading("Sensor tracks"))
	track_tree = Tree.new()
	track_tree.columns = 7
	track_tree.hide_root = true
	track_tree.select_mode = Tree.SELECT_ROW
	track_tree.column_titles_visible = true
	for i in 7:
		track_tree.set_column_title(i, ["Track", "Status", "Range", "Brg", "Alt", "Speed", "Upd"][i])
		track_tree.set_column_expand(i, i < 2)
		track_tree.set_column_custom_minimum_width(i, [62, 90, 66, 46, 50, 60, 46][i])
	track_tree.custom_minimum_size = Vector2(RIGHT_WIDTH, 230)
	track_tree.add_theme_font_size_override("font_size", 14)
	track_tree.item_selected.connect(_on_tree_selected)
	track_tree.create_item()
	right_column.add_child(track_tree)
	var details_panel := UiKit.panel()
	details_label = _rich(15)
	details_label.fit_content = true
	details_label.custom_minimum_size = Vector2(RIGHT_WIDTH - 24, 150)
	details_panel.add_child(details_label)
	right_column.add_child(details_panel)
	right_column.add_child(UiKit.button("Centre view on selected track", func(): centre_requested.emit()))
	_build_decision_panel()

	var help := UiKit.label("Right-drag / W A S D: look · Wheel: zoom · V: eye/sensor · Tab / click: select track · F acknowledge · K classify · Enter respond · Esc pause · R restart", 14, UiKit.MUTED)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(help)
	_build_overlay()


func _build_decision_panel() -> void:
	var panel := UiKit.panel()
	panel.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	decision_panel = panel
	var rows := UiKit.vbox(6)
	panel.add_child(rows)
	left_column.add_child(panel)
	rows.add_child(UiKit.heading("Your assessment"))
	trainee_label = UiKit.label("", 15, Color.WHITE, true)
	rows.add_child(trainee_label)
	rows.add_child(UiKit.button("Acknowledge track (F)", func(): acknowledge_requested.emit()))
	rows.add_child(UiKit.label("Classify: K · Submit response: Enter", 13, UiKit.MUTED))
	var classify_row := UiKit.hbox(6)
	category_option = OptionButton.new()
	for category in Vocabulary.CATEGORIES:
		category_option.add_item(Vocabulary.CATEGORY_LABELS[category])
	category_option.select(Vocabulary.CATEGORIES.find("unknown"))
	category_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_option.custom_minimum_size = Vector2(150, 0)
	category_option.clip_text = true
	classify_row.add_child(category_option)
	confidence_slider = HSlider.new()
	confidence_slider.min_value = 0
	confidence_slider.max_value = 100
	confidence_slider.step = 5
	confidence_slider.value = 50
	confidence_slider.custom_minimum_size = Vector2(70, 0)
	confidence_label = UiKit.label("50%", 15)
	confidence_slider.value_changed.connect(func(v): confidence_label.text = "%d%%" % int(v))
	classify_row.add_child(confidence_slider)
	classify_row.add_child(confidence_label)
	classify_row.add_child(UiKit.button("Classify", func(): classify_requested.emit(Vocabulary.CATEGORIES[category_option.selected], int(confidence_slider.value))))
	rows.add_child(classify_row)
	var respond_row := UiKit.hbox(6)
	response_option = OptionButton.new()
	for response in Vocabulary.RESPONSES:
		response_option.add_item(Vocabulary.RESPONSE_LABELS[response])
	response_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	response_option.custom_minimum_size = Vector2(150, 0)
	response_option.clip_text = true
	respond_row.add_child(response_option)
	respond_row.add_child(UiKit.button("Submit", func(): respond_requested.emit(Vocabulary.RESPONSES[response_option.selected])))
	rows.add_child(respond_row)
	feedback_label = UiKit.label("", 15, UiKit.ACCENT, true)
	rows.add_child(feedback_label)
	support_toggle = CheckBox.new()
	support_toggle.text = "Show decision support"
	support_toggle.button_pressed = true
	support_toggle.toggled.connect(_on_support_toggled)
	rows.add_child(support_toggle)
	support_label = _rich(14)
	support_label.fit_content = true
	rows.add_child(support_label)


func _on_support_toggled(on: bool) -> void:
	support_label.visible = on
	decision_support_toggled.emit(on)


## Keyboard shortcuts (K / Enter) submit what the panel currently shows.
func submit_classification() -> void:
	classify_requested.emit(Vocabulary.CATEGORIES[category_option.selected], int(confidence_slider.value))


func submit_response() -> void:
	respond_requested.emit(Vocabulary.RESPONSES[response_option.selected])


func show_feedback(text: String, ok: bool) -> void:
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", UiKit.GOOD if ok else UiKit.WARN)


func _rich(size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	label.add_theme_font_size_override("normal_font_size", size)
	label.add_theme_font_size_override("bold_font_size", size)
	return label


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


func _build_replay_bar() -> void:
	replay_bar = UiKit.panel(0.85)
	replay_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	replay_bar.custom_minimum_size = Vector2(620, 0)
	replay_bar.position += Vector2(-310 - RIGHT_WIDTH / 2.0 + LEFT_WIDTH / 2.0, -70)
	var row := UiKit.hbox(8)
	replay_bar.add_child(row)
	row.add_child(UiKit.label("REPLAY", 15, UiKit.ACCENT))
	replay_play = UiKit.button("Pause", func(): replay_play_toggled.emit(), 80)
	row.add_child(replay_play)
	var speed := OptionButton.new()
	for s in ["1×", "2×", "4×", "8×"]:
		speed.add_item(s)
	speed.item_selected.connect(func(i): replay_speed_changed.emit([1.0, 2.0, 4.0, 8.0][i]))
	row.add_child(speed)
	replay_slider = HSlider.new()
	replay_slider.custom_minimum_size = Vector2(200, 0)
	replay_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replay_slider.value_changed.connect(_on_slider)
	row.add_child(replay_slider)
	replay_time = UiKit.label("00:00", 15)
	row.add_child(replay_time)
	truth_toggle = CheckBox.new()
	truth_toggle.text = "Truth labels"
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


## Refreshes text panels (4 times per second) from the session's trainee-visible state.
func refresh(session: RefCounted, selected_id: String, view_text: String, delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.25
	var c: Dictionary = session.config
	info_label.text = "%s\nTime remaining %s · %s · %s · visibility %s" % [
		c["title"], clock(session.remaining_s()), c["environment"], c["time_of_day"], c["visibility"]]
	sensor_label.text = sensor_text(session, view_text)
	_refresh_tracks(session, selected_id)
	details_label.text = track_details(session, selected_id)
	trainee_label.text = trainee_text(session, selected_id)
	support_label.text = decision_support_text(session, selected_id)
	if sensor_shade.visible:
		(sensor_shade.material as ShaderMaterial).set_shader_parameter("seed", randf() * 100.0)


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


func _refresh_tracks(session: RefCounted, selected_id: String) -> void:
	var now: float = session.time_s()
	var root := track_tree.get_root()
	var live := {}
	for track in session.tracker.confirmed_tracks():
		var id: String = track["id"]
		live[id] = true
		var item: TreeItem = _rows.get(id)
		if item == null:
			item = root.create_child()
			item.set_metadata(0, id)
			_rows[id] = item
		var p: Vector3 = session.tracker.estimated_position(track, now)
		var offset: Vector3 = p - session.definition["observer_position"]
		var values := [
			id + ("*" if not String(track["swarm_group"]).is_empty() else ""),
			track["status"],
			"%.0f m" % offset.length(),
			"%03d" % int(fposmod(rad_to_deg(atan2(offset.x, -offset.z)), 360.0)),
			"%.0f" % p.y,
			"%.1f" % Vector2(track["velocity"].x, track["velocity"].z).length(),
			"%.1fs" % (now - float(track["last_update_t"])),
		]
		for i in values.size():
			item.set_text(i, values[i])
		var color := Color(1.0, 0.65, 0.2) if track["status"] == "coasting" else Color.WHITE
		for i in values.size():
			item.set_custom_color(i, color)
		if id == selected_id and not item.is_selected(0):
			item.select(0)
	for id in _rows.keys():
		if not live.has(id):
			(_rows[id] as TreeItem).free()
			_rows.erase(id)


## Trainee-visible facts about one track (tracker output only).
static func track_details(session: RefCounted, track_id: String) -> String:
	if track_id.is_empty():
		return "Select a track: click its marker, a row above, or press Tab."
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
		return "No track selected."
	var state: Dictionary = session.trainee_state(track_id)
	if state.is_empty():
		return "%s: not yet acknowledged." % track_id
	var parts := PackedStringArray(["%s: acknowledged %s" % [track_id, clock(float(state["acknowledged_t"]))]])
	if not String(state["category"]).is_empty():
		parts.append("classified %s (%d%%)" % [Vocabulary.CATEGORY_LABELS[state["category"]], state["confidence"]])
	if not String(state["response"]).is_empty():
		parts.append("response: %s (final)" % Vocabulary.RESPONSE_LABELS[state["response"]])
	return " · ".join(parts)


## Decision-support outputs for the selected track, labelled by method.
static func decision_support_text(session: RefCounted, track_id: String) -> String:
	if track_id.is_empty():
		return ""
	var entry: Dictionary = session.decisions.recommendation_for(track_id)
	if entry.is_empty():
		return "[i]Decision support: waiting for the first assessment (once per second).[/i]"
	var rules: Dictionary = entry["rules"]
	var lines := PackedStringArray(["[b]Decision support[/b] [i](synthetic training aid; confidence is a score, not a probability)[/i]"])
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
		item.select(0)
		track_tree.scroll_to_item(item)


func _on_tree_selected() -> void:
	var item := track_tree.get_selected()
	if item:
		track_selected.emit(String(item.get_metadata(0)))


static func clock(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
