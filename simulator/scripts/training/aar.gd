extends RefCounted
## After-action review content built from a validated session record (pure; the
## history screen only displays it). Ground truth is shown here by design: the
## exercise is over and the review explains what each object really was.

const Vocabulary := preload("res://scripts/ai/vocabulary.gd")
const Rubric := preload("res://scripts/training/rubric.gd")

const COMPONENT_LABELS := {
	"detection": "Detection timeliness", "classification": "Classification", "evidence": "Evidence-based confidence",
	"response": "Response appropriateness", "response_time": "Response time", "degraded": "Degraded conditions",
}


static func report(record: Dictionary) -> String:
	var e: Dictionary = record["evaluation"]
	var sections := PackedStringArray([summary(record), entities_section(e), alarms_section(e), timeline_section(record),
		comparison_section(e), deductions_section(e), "[b]Suggested areas for improvement[/b]\n• " + "\n• ".join(suggestions(record))])
	return "\n\n".join(sections)


static func summary(record: Dictionary) -> String:
	var e: Dictionary = record["evaluation"]
	var c: Dictionary = record["scenario"]
	var lines := PackedStringArray()
	lines.append("[font_size=26][b]%.1f / 100[/b][/font_size]  %s" % [e["score"], "" if e["comparable"] else "[color=#ffa640](not comparable: %s)[/color]" % ("aborted" if record["status"] == "aborted" else "no confirmed objects")])
	lines.append("%s · seed %d · %s %s, visibility %s · difficulty %d · %s" % [c["title"], c["seed"], c["environment"], c["time_of_day"], c["visibility"], c["difficulty"], record["status"]])
	lines.append("%.1f weighted credit − %.1f penalty points (rubric %s). Decision models: %s, %s, ML %s." % [
		e["weighted_score"], e["penalty_points"], e["rubric"], record["models"]["rules"], record["models"]["policy"],
		record["models"]["ml"].get("version", "not used") if record["models"]["ml"].get("loaded", false) else "not used"])
	var parts := PackedStringArray()
	for key in Rubric.COMPONENTS:
		var comp: Dictionary = e["components"][key]
		parts.append("%s %s" % [COMPONENT_LABELS[key], "%.0f%% (weight %.0f)" % [comp["score"], comp["effective_weight"]] if comp["n"] > 0 else "n/a"])
	lines.append(" · ".join(parts))
	return "\n".join(lines)


static func entities_section(e: Dictionary) -> String:
	var lines := PackedStringArray(["[b]Objects (ground truth revealed)[/b]"])
	if e["entities"].is_empty():
		lines.append("No object was confirmed by the sensors.")
	for r in e["entities"]:
		var classified := "not classified"
		if not String(r["category"]).is_empty():
			classified = "%s %d%% %s" % [Vocabulary.CATEGORY_LABELS[r["category"]], r["confidence"], "✓" if r["correct"] else ("(unknown)" if r["category"] == "unknown" else "✗")]
		var response: String = Vocabulary.RESPONSE_LABELS.get(r["response"], "no response")
		var ack := "%.0f s" % (float(r["ack_t"]) - float(r["available_t"])) if float(r["ack_t"]) >= 0.0 else "never"
		var resp_time := "%.0f s" % (float(r["responded_t"]) - float(r["available_t"])) if float(r["responded_t"]) >= 0.0 else "—"
		lines.append("• [b]%s[/b] %s%s — confirmed %s, acknowledged after %s · %s · evidence %.0f s · response: %s after %s (best: %s)" % [
			r["entity"], Vocabulary.CATEGORY_LABELS[r["expected_category"]], " [color=#ff8060](threat)[/color]" if r["significant"] else "",
			_clock(float(r["available_t"])), ack, classified, r["evidence_s"], response, resp_time, r["best_response"]])
	return "\n".join(lines)


static func alarms_section(e: Dictionary) -> String:
	var missed := PackedStringArray()
	var false_alarms := PackedStringArray()
	for f in e["findings"]:
		if f["rule"] == "P3":
			missed.append("%s — %s" % [f["entity"], f["reason"]])
		elif f["rule"] == "P2":
			false_alarms.append("%s — %s" % [f["entity"], f["reason"]])
	return "[b]Missed threats:[/b] %s\n[b]False alarms:[/b] %s" % [
		"none" if missed.is_empty() else "\n• " + "\n• ".join(missed),
		"none" if false_alarms.is_empty() else "\n• " + "\n• ".join(false_alarms)]


## Trainee actions and sensor status changes, in order.
static func timeline_section(record: Dictionary) -> String:
	var lines := PackedStringArray(["[b]Decision timeline[/b]"])
	for event in record["events"]:
		var d: Dictionary = event["data"]
		var text := ""
		match event["type"]:
			"sensor_degraded":
				text = "[color=#ffa640]Sensor degraded[/color]"
			"sensor_restored":
				text = "Sensor restored"
			"paused", "resumed":
				text = event["type"].capitalize()
			"action":
				match d["kind"]:
					"acknowledge":
						text = "Acknowledged %s" % d["track_id"]
					"classify":
						text = "Classified %s as %s (%d%%)" % [d["track_id"], Vocabulary.CATEGORY_LABELS.get(d.get("category", ""), str(d.get("category", ""))), int(d.get("confidence", 0))]
					"respond":
						text = "Response for %s: %s" % [d["track_id"], Vocabulary.RESPONSE_LABELS.get(d.get("response", ""), str(d.get("response", "")))]
				if not d.get("valid", true):
					text = "[color=#a0a0a0]Rejected: %s[/color]" % d.get("message", text)
		if not text.is_empty():
			lines.append("%s  #%d  %s" % [_clock(float(event["t"])), int(event["seq"]), text])
	if lines.size() == 1:
		lines.append("No trainee actions were recorded.")
	return "\n".join(lines)


static func comparison_section(e: Dictionary) -> String:
	var lines := PackedStringArray(["[b]Model recommendation vs your response[/b] (recorded at the moment you responded)"])
	var any := false
	for r in e["entities"]:
		var model: Dictionary = r["model_recommendation"]
		if String(r["response"]).is_empty() or model.is_empty():
			continue
		any = true
		var same: bool = model["response"] == r["response"]
		lines.append("• %s: you chose %s; decision support (%s, %s) recommended %s — %s" % [
			r["entity"], Vocabulary.RESPONSE_LABELS[r["response"]], model["based_on"], model["reason_code"],
			Vocabulary.RESPONSE_LABELS[model["response"]], "same" if same else "different"])
	if not any:
		lines.append("No responses with a recorded recommendation.")
	return "\n".join(lines)


static func deductions_section(e: Dictionary) -> String:
	var lines := PackedStringArray(["[b]Why points were lost[/b]"])
	for f in e["findings"]:
		if f["penalty"]:
			lines.append("• [color=#ff8060]%s −%.1f[/color] %s: %s" % [f["rule"], f["points"], f["entity"], f["reason"]])
	for f in e["findings"]:
		if not f["penalty"] and f["rule"] in ["DETECTION", "CLASSIFICATION", "EVIDENCE", "RESPONSE", "RESPONSE_TIME", "W1", "N0", "E0"]:
			lines.append("• %s %s: %s" % [f["rule"].to_lower().replace("_", " "), f["entity"], f["reason"]])
	if lines.size() == 1:
		lines.append("No points were lost.")
	return "\n".join(lines)


static func suggestions(record: Dictionary) -> PackedStringArray:
	var e: Dictionary = record["evaluation"]
	var c: Dictionary = e["components"]
	var tips := PackedStringArray()
	var rules := {}
	for f in e["findings"]:
		rules[f["rule"]] = rules.get(f["rule"], 0) + 1
	if rules.has("P3"):
		tips.append("Give every unidentified UAV and swarm a response before the exercise ends (%d missed)." % rules["P3"])
	if rules.has("P2"):
		tips.append("Raise alarms only for threats; log birds, balloons and authorised traffic (%d false alarm(s))." % rules["P2"])
	if rules.has("P1"):
		tips.append("Keep confidence low, or choose Unknown, until the object has been at identification quality for about %.0f s." % Rubric.STRONG_EVIDENCE_S)
	if rules.has("P4"):
		tips.append("Avoid repeated or invalid actions; check a track's state before acting.")
	if c["detection"]["n"] > 0 and c["detection"]["score"] < 70.0:
		tips.append("Acknowledge new tracks sooner: full credit needs acknowledgement within %.0f s of confirmation." % Rubric.DETECTION_GRACE_S)
	if c["classification"]["n"] > 0 and c["classification"]["score"] < 70.0:
		tips.append("Use the cues: cooperative ID reply (authorised), drifting with the wind (balloon), wing beat or winding path (bird), tracks moving together (swarm).")
	if c["response_time"]["n"] > 0 and c["response_time"]["score"] < 70.0:
		tips.append("Respond sooner: full timing credit needs a response within %.0f s of confirmation." % Rubric.RESPONSE_GRACE_S)
	if c["degraded"]["n"] > 0 and c["degraded"]["score"] < 70.0:
		tips.append("Under sensor degradation, prefer Continue observing or Request identification over confident guesses.")
	if tips.is_empty():
		tips.append("Good result. Try a harder seed or a night / fog scenario next.")
	return tips


static func _clock(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
