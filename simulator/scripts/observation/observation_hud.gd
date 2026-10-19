extends Control
## Observation-mode HUD. Shows only trainee-visible information: scenario conditions,
## sensor status, tracker output and the trainee's own actions. It never reads ground
## truth. User actions are reported through signals; observation_main.gd acts on them.

signal track_selected(track_id: String)
signal centre_requested
signal resume_requested
signal restart_requested
signal exit_requested

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const RIGHT_WIDTH := 480.0

var info_label: Label
var sensor_label: RichTextLabel
var track_tree: Tree
var details_label: RichTextLabel
var overlay: PanelContainer
var overlay_title: Label
var overlay_detail: Label
var right_column: VBoxContainer
var sensor_shade: ColorRect

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
	left.custom_minimum_size = Vector2(420, 0)
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

	var help := UiKit.label("Right-drag / W A S D: look · Wheel: zoom · V: eye/sensor · Tab: next track · Click marker: select · Esc: pause · R: restart", 14, UiKit.MUTED)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(help)
	_build_overlay()


func _rich(size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	label.add_theme_font_size_override("normal_font_size", size)
	label.add_theme_font_size_override("bold_font_size", size)
	return label


func _build_overlay() -> void:
	overlay = UiKit.panel(0.92)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	overlay.custom_minimum_size = Vector2(540, 0)
	overlay.position -= Vector2(270 + RIGHT_WIDTH / 2.0, 90)
	var rows := UiKit.vbox(10)
	overlay_title = UiKit.label("", 32)
	overlay_detail = UiKit.label("", 17, UiKit.MUTED, true)
	rows.add_child(overlay_title)
	rows.add_child(overlay_detail)
	var buttons := UiKit.hbox(10)
	buttons.name = "Buttons"
	buttons.add_child(UiKit.button("Resume", func(): resume_requested.emit(), 140))
	buttons.add_child(UiKit.button("Restart", func(): restart_requested.emit(), 140))
	buttons.add_child(UiKit.button("Exit to menu", func(): exit_requested.emit(), 160))
	rows.add_child(buttons)
	overlay.add_child(rows)
	overlay.visible = false
	add_child(overlay)


func show_overlay(title: String, detail: String) -> void:
	overlay_title.text = title
	overlay_detail.text = detail
	overlay.visible = true


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
