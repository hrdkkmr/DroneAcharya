extends RefCounted
## Plain-language after-action report built only from a saved record:
##  * threat detection: a droneacharya-session record with its da-rubric-1 evaluation;
##  * flight training: a droneacharya-flight-session record.
## Every statement is computed from recorded events, decisions, times and scores; a
## statement is left out when the record does not support it. No praise without a
## number behind it, no filler. The detailed rubric output stays in `details`.
## Reads every known format version; an unknown version gives a short notice instead
## of a guess.
##
## Report: {kind, result: [[label, value]], went_well: [≤3], improve: [≤3],
##          timeline: [{t, subject, decision, result, reason}], next: [1..3],
##          categories: [[label, value]], details: String (BBCode)}

const Vocabulary := preload("res://scripts/ai/vocabulary.gd")
const Rubric := preload("res://scripts/training/rubric.gd")
const Aar := preload("res://scripts/training/aar.gd")

const MAX_POINTS := 3
const MAX_TIMELINE := 14
const THREAT_FORMATS := {"droneacharya-session": [1]}
const FLIGHT_FORMATS := {"droneacharya-flight-session": [1]}
const ENVIRONMENT_NAMES := {"course": "Training course", "city": "City", "village": "Village", "urban": "Urban", "rural": "Rural"}
## Phrases a report must never contain (checked by tests).
const BANNED := ["as an ai", "language model", "leverag", "comprehensive understanding", "performed well", "overall,", "great job",
	"excellent", "impressive", "outstanding", "demonstrates"]


static func build(record: Dictionary) -> Dictionary:
	var format: String = record.get("format", "")
	var version := int(record.get("format_version", 0))
	if THREAT_FORMATS.has(format):
		if version in THREAT_FORMATS[format]:
			return threat_report(record)
	elif FLIGHT_FORMATS.has(format):
		if version in FLIGHT_FORMATS[format]:
			return flight_report(record)
	return {"kind": "unsupported", "result": [["Record", "%s version %d" % [format, version]]], "went_well": [], "improve": [],
		"timeline": [], "next": ["This record was made by a different version of DroneAcharya and cannot be summarised here."],
		"categories": [], "details": ""}


# --- Threat detection ---------------------------------------------------------------

static func threat_report(record: Dictionary) -> Dictionary:
	var e: Dictionary = record["evaluation"]
	var c: Dictionary = record["scenario"]
	var entities: Array = e["entities"]
	var findings: Array = e["findings"]
	var n := entities.size()
	var correct := entities.filter(func(x): return x["correct"] and not String(x["category"]).is_empty())
	var wrong := entities.filter(func(x): return not String(x["category"]).is_empty() and x["category"] != "unknown" and not x["correct"])
	var unknown := entities.filter(func(x): return x["category"] == "unknown")
	var unclassified := entities.filter(func(x): return String(x["category"]).is_empty())
	var never_seen := entities.filter(func(x): return float(x["ack_t"]) < 0.0)
	var quick := entities.filter(func(x): return float(x["ack_t"]) >= 0.0 and float(x["ack_t"]) - float(x["available_t"]) <= Rubric.DETECTION_GRACE_S)
	var responded := entities.filter(func(x): return not String(x["response"]).is_empty())
	var delayed := responded.filter(func(x): return float(x["responded_t"]) - float(x["available_t"]) > Rubric.RESPONSE_GRACE_S)
	var threats := entities.filter(func(x): return x["significant"])
	var false_alarms := findings.filter(func(f): return f["rule"] == "P2")
	var missed_threats := findings.filter(func(f): return f["rule"] == "P3")
	var overconfident := findings.filter(func(f): return f["rule"] == "P1")
	var repeated := int(record.get("spam_count", 0))
	var good_responses := responded.filter(func(x): return float(x["credits"]["response"]) >= 1.0)

	var went_well := []
	if n > 0 and correct.size() > 0 and correct.size() * 2 >= n:
		went_well.append("You identified %d of %d contacts correctly." % [correct.size(), n])
	if n > 0 and quick.size() == n:
		went_well.append("You selected every contact within %d s of it appearing." % int(Rubric.DETECTION_GRACE_S))
	elif quick.size() > 0 and quick.size() * 2 >= n:
		went_well.append("You selected %d of %d contacts within %d s of them appearing." % [quick.size(), n, int(Rubric.DETECTION_GRACE_S)])
	if not threats.is_empty() and missed_threats.is_empty():
		went_well.append("Every threat (%d) received a response." % threats.size())
	if not responded.is_empty() and false_alarms.is_empty():
		went_well.append("You raised no unnecessary alarms in %d response%s." % [responded.size(), "" if responded.size() == 1 else "s"])
	if not unknown.is_empty() and overconfident.is_empty():
		went_well.append("You marked %d contact%s as unknown instead of guessing while evidence was thin." % [unknown.size(), "" if unknown.size() == 1 else "s"])
	if good_responses.size() >= 2:
		went_well.append("Your response matched the expected procedure for %d contacts." % good_responses.size())
	went_well = went_well.slice(0, MAX_POINTS)

	var improve := []
	var next := []
	if not missed_threats.is_empty():
		var x := _entity(entities, missed_threats[0]["entity"])
		improve.append("%s (%s) had no response before the exercise ended%s." % [_upper_first(_contacts(x)), _truth(x), _more(missed_threats.size())])
		next.append("Give every unidentified UAV and swarm a response before time runs out; look for \"● new\" and \"classified\" in the Contacts list.")
	if not false_alarms.is_empty():
		var x := _entity(entities, false_alarms[0]["entity"])
		improve.append("You raised an alarm for %s, which was %s%s." % [_contacts(x), _article(_truth(x)) if not x.is_empty() else "a false sensor track", _more(false_alarms.size())])
		next.append("Before raising an alarm, open Contact details and check the ID reply and the wing beat.")
	if not wrong.is_empty():
		var x: Dictionary = wrong[0]
		improve.append("You classified %s as %s; it was %s%s." % [_contacts(x), Vocabulary.CATEGORY_LABELS[x["category"]], _article(_truth(x)), _more(wrong.size())])
		next.append("Inspect uncertain contacts before submitting a classification; use the sensor camera (V) to see size and wing beat.")
	if not never_seen.is_empty():
		var x: Dictionary = never_seen[0]
		improve.append("You missed a contact that appeared at %s (%s)%s." % [_clock(float(x["available_t"])), _contacts(x),
			" and %d other%s" % [never_seen.size() - 1, "" if never_seen.size() == 2 else "s"] if never_seen.size() > 1 else ""])
		next.append("Scan the radar and the Contacts list every few seconds and select new contacts as soon as they appear.")
	elif not unclassified.is_empty():
		improve.append("%d contact%s %s selected but never classified." % [unclassified.size(), "" if unclassified.size() == 1 else "s", "was" if unclassified.size() == 1 else "were"])
		next.append("After selecting a contact, finish the decision: classify it, then choose a response.")
	if not overconfident.is_empty():
		var x := _entity(entities, overconfident[0]["entity"])
		var seen := float(x.get("evidence_s", 0.0))
		improve.append("You classified %s at %d%% confidence %s (about %.0f s is needed)." % [
			_contacts(x), int(x.get("confidence", 0)), "after only %.0f s of clear view" % seen if seen >= 1.0 else "without a clear view", Rubric.STRONG_EVIDENCE_S])
		next.append("Keep confidence Low until a contact has been in clear camera view for about %.0f s." % Rubric.STRONG_EVIDENCE_S)
	if not delayed.is_empty():
		var x: Dictionary = delayed[0]
		improve.append("Your response to %s came %.0f s after it appeared (aim for %.0f s or less)." % [_contacts(x),
			float(x["responded_t"]) - float(x["available_t"]), Rubric.RESPONSE_GRACE_S])
		next.append("Respond within %.0f s of a contact appearing; a routine response needs only one right-click." % Rubric.RESPONSE_GRACE_S)
	if repeated > Rubric.SPAM_ALLOWANCE:
		improve.append("You repeated or made invalid actions %d times." % repeated)
		next.append("Check the contact's state in the decision card before acting on it again.")
	improve = improve.slice(0, MAX_POINTS)
	next = _unique(next).slice(0, MAX_POINTS)
	if next.is_empty() and n > 0:
		next.append("Try a harder seed or a night or fog scenario next.")
	elif next.is_empty():
		next.append("No contact was confirmed by the sensors in this run; try another scenario.")

	var result := [
		["Mission", c["title"]],
		["Environment", "%s · %s · visibility %s" % [ENVIRONMENT_NAMES.get(c["environment"], c["environment"]), c["time_of_day"], c["visibility"]]],
		["Training mode", "Threat detection · difficulty %d · seed %d" % [int(c["difficulty"]), int(c["seed"])]],
		["Result", "Completed" if record["status"] == "completed" else "Stopped before the end"],
		["Duration", _clock(float(record["end_t"]))],
		["Final score", "%.1f / 100%s" % [e["score"], "" if e["comparable"] else " (not comparable with other runs)"]],
		["Contacts", "%d correct · %d incorrect · %d unknown · %d unresolved · %d missed · %d unnecessary alert%s · %d delayed" % [
			correct.size(), wrong.size(), unknown.size(), unclassified.size(), never_seen.size(), false_alarms.size(),
			"" if false_alarms.size() == 1 else "s", delayed.size()]],
	]
	var categories := []
	var names := {"detection": "Noticing contacts quickly", "classification": "Identifying them", "evidence": "Matching confidence to evidence",
		"response": "Choosing the right response", "response_time": "Responding in time", "degraded": "Coping with sensor degradation"}
	for key in Rubric.COMPONENTS:
		var comp: Dictionary = e["components"][key]
		categories.append([names[key], "%d%%" % roundi(comp["score"]) if comp["n"] > 0 else "not part of this exercise"])
	if float(e["penalty_points"]) > 0.0:
		categories.append(["Deductions", "−%.0f points (%s)" % [e["penalty_points"], _deductions(findings)]])
	return {"kind": "threat", "result": result, "went_well": went_well, "improve": improve, "timeline": _threat_timeline(record, entities),
		"next": next, "categories": categories, "details": Aar.report(record)}


static func _threat_timeline(record: Dictionary, entities: Array) -> Array:
	var by_track := {}
	for x in entities:
		for track in x["tracks"]:
			by_track[track] = x
	var rows := []
	for event in record["events"]:
		if event["type"] != "action" or not event["data"].get("valid", false):
			continue
		var d: Dictionary = event["data"]
		var x: Dictionary = by_track.get(d["track_id"], {})
		match d["kind"]:
			"classify":
				var outcome := "—"
				var reason := ""
				if not x.is_empty():
					if d["category"] == "unknown":
						outcome = "unknown (partial credit)"
						reason = "It was %s." % _article(_truth(x))
					elif d["category"] == x["expected_category"]:
						outcome = "correct"
						reason = "%.0f s of clear view before deciding." % float(x["evidence_s"])
					else:
						outcome = "incorrect"
						reason = "It was %s." % _article(_truth(x))
				else:
					outcome = "false sensor track"
				rows.append({"t": float(event["t"]), "subject": d["track_id"], "decision": "Classified as %s (%d%%)" % [Vocabulary.CATEGORY_LABELS.get(d["category"], d["category"]), int(d["confidence"])],
					"result": outcome, "reason": reason})
			"respond":
				var outcome := "—"
				var reason := ""
				if not x.is_empty():
					var credit: float = x["credits"]["response"]
					outcome = "appropriate" if credit >= 1.0 else ("acceptable" if credit >= 0.5 else "inappropriate")
					reason = "Expected: %s." % String(x["best_response"]).replace("_", " ")
				elif d["response"] in Vocabulary.ALARM_RESPONSES:
					outcome = "unnecessary alert"
					reason = "The contact was sensor clutter."
				rows.append({"t": float(event["t"]), "subject": d["track_id"], "decision": Vocabulary.RESPONSE_LABELS.get(d["response"], d["response"]),
					"result": outcome, "reason": reason})
	for x in entities:
		if float(x["ack_t"]) < 0.0:
			rows.append({"t": float(x["available_t"]), "subject": _contacts(x), "decision": "No decision", "result": "missed",
				"reason": "%s appeared and was never selected." % _upper_first(_article(_truth(x)))})
	rows.sort_custom(func(a, b): return a["t"] < b["t"])
	return rows.slice(0, MAX_TIMELINE)


static func _entity(entities: Array, id: String) -> Dictionary:
	for x in entities:
		if x["entity"] == id:
			return x
	return {}


## Contact names as the trainee saw them (tracker ids). One object tracked more than
## once reads "T02/T06"; a swarm reads "the swarm (T03 and 4 more)".
static func _contacts(x: Dictionary) -> String:
	if x.is_empty():
		return "a contact"
	var tracks: Array = x.get("tracks", [])
	if tracks.is_empty():
		return "a contact"
	tracks = tracks.duplicate()
	tracks.sort()
	if x.get("expected_category", "") == "swarm" and tracks.size() > 1:
		return "the swarm (%s and %d more)" % [tracks[0], tracks.size() - 1]
	if tracks.size() > 3:
		return "%s and %d more" % ["/".join(PackedStringArray(tracks.slice(0, 2))), tracks.size() - 2]
	return "/".join(PackedStringArray(tracks))


static func _truth(x: Dictionary) -> String:
	return Vocabulary.CATEGORY_LABELS.get(x.get("expected_category", ""), "Unknown object")


## " (and N more like it)" when a finding repeats.
static func _more(count: int) -> String:
	return " (and %d more like it)" % (count - 1) if count > 1 else ""


static func _upper_first(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


static func _article(text: String) -> String:
	return ("an " if text.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + text


static func _deductions(findings: Array) -> String:
	var counts := {}
	for f in findings:
		if f["penalty"]:
			counts[f["rule"]] = counts.get(f["rule"], 0) + 1
	var names := {"P1": "over-confident call", "P2": "unnecessary alarm", "P3": "missed threat", "P4": "repeated actions"}
	var parts := PackedStringArray()
	for rule in ["P3", "P2", "P1", "P4"]:
		if counts.has(rule):
			parts.append("%d %s%s" % [counts[rule], names[rule], "" if counts[rule] == 1 or rule == "P4" else "s"])
	return ", ".join(parts)


# --- Flight training ----------------------------------------------------------------

static func flight_report(record: Dictionary) -> Dictionary:
	var r: Dictionary = record["result"]
	var m: Dictionary = record["mission"]
	var events: Array = record["events"]
	var completed: bool = r["status"] == "completed"
	var passed := int(r["checkpoints_passed"])
	var total := int(r["checkpoint_count"])
	var limit := float(r.get("time_limit_s", 0.0))
	var elapsed := float(r["elapsed_s"])
	var bumps := events.filter(func(ev): return ev["type"] == "bump")
	var hits := events.filter(func(ev): return ev["type"] == "hit")
	var wrong := events.filter(func(ev): return ev["type"] == "wrong_checkpoint")
	var threats: Dictionary = r.get("threats", {})

	var went_well := []
	if completed:
		went_well.append("You reached the landing zone in %s." % _clock(elapsed))
	if total > 0 and passed == total and wrong.is_empty():
		went_well.append("You flew through all %d checkpoints in order." % total)
	elif passed > 0 and not completed:
		went_well.append("You passed %d of %d checkpoints." % [passed, total])
	if completed and limit > 0.0 and limit - elapsed >= 30.0:
		went_well.append("You finished with %s to spare." % _clock(limit - elapsed))
	if completed and bumps.is_empty():
		went_well.append("You flew the whole route without touching an obstacle.")
	if record["mission"].get("hostile", false) and hits.is_empty() and passed > 0:
		went_well.append("You took no simulated hits while %d projectile%s %s launched." % [int(threats.get("projectiles_launched", 0)),
			"" if int(threats.get("projectiles_launched", 0)) == 1 else "s", "was" if int(threats.get("projectiles_launched", 0)) == 1 else "were"])
	went_well = went_well.slice(0, MAX_POINTS)

	var improve := []
	var next := []
	var reason: String = r.get("failure_reason", "")
	if not completed and not reason.is_empty():
		var fail_t := _event_time(events, "failed", elapsed)
		improve.append("The mission failed at %s: %s." % [_clock(fail_t), reason])
		if reason.begins_with("collided"):
			next.append("Slow down near buildings and poles; switch to the onboard camera (V) for tight gaps.")
		elif reason.begins_with("time limit"):
			next.append("Fly straight between rings and climb while moving forward to save time.")
		elif reason.begins_with("battery"):
			next.append("Avoid long climbs or choose a drone profile with more endurance.")
		elif reason.begins_with("left the training"):
			next.append("Watch the radar: the next ring and the landing zone are always marked on it.")
		elif reason.begins_with("airframe"):
			next.append("Keep moving in hostile areas; when INCOMING appears, change direction sideways.")
	if not bumps.is_empty():
		var names := PackedStringArray()
		for ev in bumps:
			if not String(ev["data"]["obstacle"]) in names:
				names.append(ev["data"]["obstacle"])
		improve.append("You touched obstacles %d time%s (%s)." % [bumps.size(), "" if bumps.size() == 1 else "s", ", ".join(names.slice(0, 3))])
		next.append("Give obstacles more room and brake earlier before turns.")
	if not wrong.is_empty():
		improve.append("You flew through a ring out of order %d time%s." % [wrong.size(), "" if wrong.size() == 1 else "s"])
		next.append("Follow the numbered rings; the radar marks the next ring with its number.")
	if not hits.is_empty():
		improve.append("You took %d simulated hit%s; integrity ended at %d%%." % [hits.size(), "" if hits.size() == 1 else "s", roundi(float(r["integrity_end"]))])
		next.append("Keep moving in hostile areas; when INCOMING appears, change direction sideways.")
	if events.any(func(ev): return ev["type"] == "battery_warning") and completed:
		improve.append("The battery fell to 20%% at %s." % _clock(_event_time(events, "battery_warning", elapsed)))
	improve = _unique(improve).slice(0, MAX_POINTS)
	next = _unique(next).slice(0, MAX_POINTS)
	if next.is_empty():
		next.append("Try the same mission with a faster drone profile, or the hostile-area version." if completed else "Fly the mission again.")

	var result := [
		["Mission", m["title"]],
		["Environment", ENVIRONMENT_NAMES.get(m["environment"], m["environment"])],
		["Drone profile", record["profile"]["title"]],
		["Result", "Completed" if completed else "Failed: " + reason],
		["Mission time", _clock(elapsed) + (" of %s allowed" % _clock(limit) if limit > 0.0 else "")],
	]
	var categories := [
		["Checkpoints", "%d of %d%s" % [passed, total, " (%d out of order)" % wrong.size() if not wrong.is_empty() else ""]],
		["Landing", "landed in the zone" if r.get("landed_in_zone", false) else "not landed in the zone"],
		["Collisions", "%d minor%s" % [bumps.size(), "" if not reason.begins_with("collided") else " + 1 crash"]],
		["Battery left", "%d%%" % roundi(float(r.get("battery_end", 1.0)) * 100.0)],
	]
	if m.get("hostile", false):
		categories.append(["Simulated threats", "%d launched · %d warning%s · %d hit%s" % [int(threats.get("projectiles_launched", 0)),
			int(threats.get("incoming_warnings", 0)), "" if int(threats.get("incoming_warnings", 0)) == 1 else "s", hits.size(), "" if hits.size() == 1 else "s"]])
	return {"kind": "flight", "result": result, "went_well": went_well, "improve": improve, "timeline": _flight_timeline(events),
		"next": next, "categories": categories, "details": _flight_details(record)}


static func _flight_timeline(events: Array) -> Array:
	var rows := []
	for ev in events:
		var d: Dictionary = ev["data"]
		var row := {}
		match ev["type"]:
			"takeoff":
				row = {"subject": "Launch pad", "decision": "Took off", "result": "", "reason": ""}
			"checkpoint":
				row = {"subject": "Ring %d of %d" % [d["number"], d["of"]], "decision": "Flew through", "result": "passed", "reason": ""}
			"wrong_checkpoint":
				row = {"subject": "Ring %d" % d["entered"], "decision": "Flew through", "result": "out of order", "reason": "Ring %d was next." % d["expected"]}
			"bump":
				row = {"subject": d["obstacle"], "decision": "Touched at %.1f m/s" % d["speed"], "result": "minor collision", "reason": ""}
			"hit":
				row = {"subject": d["source"], "decision": "Simulated hit", "result": "integrity %d%%" % roundi(d["integrity"]), "reason": ""}
			"incoming_warning":
				row = {"subject": "Simulated projectile", "decision": "INCOMING warning", "result": "%.1f s to impact" % d["eta_s"], "reason": ""}
			"time_warning":
				row = {"subject": "Mission clock", "decision": "Time warning", "result": "%d s left" % roundi(d["remaining_s"]), "reason": ""}
			"battery_warning":
				row = {"subject": "Battery", "decision": "Low-battery warning", "result": "%d%%" % roundi(float(d["battery"]) * 100.0), "reason": ""}
			"early_landing":
				row = {"subject": "Landing zone", "decision": "Landed early", "result": "%d ring(s) left" % d["remaining_checkpoints"], "reason": ""}
			"completed":
				row = {"subject": "Landing zone", "decision": "Landed and held", "result": "mission complete", "reason": ""}
			"failed":
				row = {"subject": "Mission", "decision": "Ended", "result": "failed", "reason": _upper_first(String(d["reason"])) + "."}
		if not row.is_empty():
			row["t"] = float(ev["t"])
			rows.append(row)
	# Keep the timeline short: drop repeated warnings first.
	if rows.size() > MAX_TIMELINE:
		rows = rows.filter(func(row): return row["decision"] != "INCOMING warning")
	return rows.slice(0, MAX_TIMELINE)


static func _flight_details(record: Dictionary) -> String:
	var r: Dictionary = record["result"]
	var lines := PackedStringArray(["[b]Record[/b] %s · %s v%d · created %s" % [record["session_id"], record["format"], record["format_version"], record["created_at"]]])
	var times := PackedStringArray()
	for i in r["checkpoint_times"].size():
		times.append("%d: %s" % [i + 1, _clock(float(r["checkpoint_times"][i]))])
	lines.append("[b]Checkpoint times[/b] %s" % (", ".join(times) if not times.is_empty() else "none"))
	lines.append("[b]Integrity[/b] %d%% · [b]Battery[/b] %d%% of %d s endurance" % [roundi(float(r["integrity_end"])), roundi(float(r["battery_end"]) * 100.0), int(r.get("endurance_s", 0))])
	if r.has("radar_contacts_seen"):
		lines.append("[b]Radar contacts reported[/b] %d" % int(r["radar_contacts_seen"]))
	lines.append("[b]Event log[/b]")
	for ev in record["events"]:
		lines.append("%s  %s %s" % [_clock(float(ev["t"])), ev["type"], JSON.stringify(ev["data"]) if not ev["data"].is_empty() else ""])
	return "\n".join(lines)


static func _event_time(events: Array, type: String, fallback: float) -> float:
	for ev in events:
		if ev["type"] == type:
			return float(ev["t"])
	return fallback


# --- Rendering -------------------------------------------------------------------------

## BBCode for the history screen (Details are shown separately on request).
static func to_bbcode(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("[font_size=22][b]1  Mission result[/b][/font_size]")
	for row in report["result"]:
		lines.append("[color=#a0a8b0]%s[/color]   %s" % [row[0], row[1]])
	lines.append("")
	lines.append("[font_size=22][b]2  What went well[/b][/font_size]")
	lines.append(_bullets(report["went_well"], "Nothing stood out in the recorded data."))
	lines.append("")
	lines.append("[font_size=22][b]3  What needs improvement[/b][/font_size]")
	lines.append(_bullets(report["improve"], "No errors were recorded."))
	lines.append("")
	lines.append("[font_size=22][b]4  Important decisions[/b][/font_size]")
	if report["timeline"].is_empty():
		lines.append("No decisions were recorded.")
	for row in report["timeline"]:
		var outcome: String = row["result"]
		var color := "#6fdc80" if outcome in ["correct", "appropriate", "passed", "mission complete"] else ("#ff9a40" if outcome in ["incorrect", "inappropriate", "missed", "unnecessary alert", "failed", "out of order", "minor collision"] else "#c8d0d8")
		lines.append("%s  [b]%s[/b] — %s%s%s" % [_clock(float(row["t"])), row["subject"], row["decision"],
			" → [color=%s]%s[/color]" % [color, outcome] if not outcome.is_empty() else "", ("  [i]%s[/i]" % row["reason"]) if not String(row["reason"]).is_empty() else ""])
	lines.append("")
	lines.append("[font_size=22][b]5  Next practice[/b][/font_size]")
	lines.append(_bullets(report["next"], ""))
	if not report["categories"].is_empty():
		lines.append("")
		lines.append("[font_size=18][b]How the result is made up[/b][/font_size]")
		for row in report["categories"]:
			lines.append("[color=#a0a8b0]%s[/color]   %s" % [row[0], row[1]])
	return "\n".join(lines)


## Plain text of the main sections (used for tests and exports; no markup).
static func to_text(report: Dictionary) -> String:
	var plain := to_bbcode(report)
	var regex := RegEx.new()
	regex.compile("\\[[^\\]]*\\]")
	return regex.sub(plain, "", true)


static func _bullets(items: Array, empty_text: String) -> String:
	if items.is_empty():
		return empty_text
	return "• " + "\n• ".join(PackedStringArray(items))


static func _unique(items: Array) -> Array:
	var out := []
	for item in items:
		if not item in out:
			out.append(item)
	return out


static func _clock(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
