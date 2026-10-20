extends RefCounted
## The one list of controls shown on briefings, pause screens and in docs/CONTROLS.md.
## Keep it in step with project.godot; test_input_map.gd checks the key bindings.

const FLIGHT := [
	["W / S", "Forward / back"],
	["A / D", "Sideways left / right"],
	["Q / E", "Turn left / right"],
	["Space / C", "Climb / descend"],
	["V", "Chase camera / onboard camera"],
	["R", "Restart the mission"],
	["Esc", "Pause menu (controls, settings, back to menu)"],
]

const OBSERVATION := [
	["Left click", "Select a contact (marker, radar or list)"],
	["Mouse wheel", "Change the highlighted option for the selected contact"],
	["Right click", "Confirm the highlighted option"],
	["Right drag / W A S D", "Look around"],
	["Shift + wheel / = and -", "Zoom in / out"],
	["Tab", "Next contact"],
	["↑ / ↓", "Change the highlighted option (keyboard)"],
	["Enter", "Confirm the highlighted option (keyboard)"],
	["Backspace", "Back / cancel the current decision step"],
	["1 / 2 / 3", "Confidence low / medium / high"],
	["F", "Mark the selected contact as seen"],
	["V", "Eye view / simulated sensor camera"],
	["R", "Restart the exercise"],
	["Esc", "Pause menu"],
]


static func as_text(rows: Array) -> String:
	var lines := PackedStringArray()
	for row in rows:
		lines.append("%s — %s" % [row[0], row[1]])
	return "\n".join(lines)
