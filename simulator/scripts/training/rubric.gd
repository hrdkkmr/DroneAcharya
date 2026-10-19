extends RefCounted
## da-rubric-1: training assessment of one session record. A pure function of the
## record (no scene, no UI). Adapted from VIGIL rubric-1 (detection window credit,
## classification and uncertainty credit, evidence-based decision expectations,
## explicit penalties, event-anchored findings) for a continuous 3D simulation.
## See docs/DRONEACHARYA_DECISION_MODELS.md §Assessment for every rule.

const VERSION := "da-rubric-1"
const Vocabulary := preload("res://scripts/ai/vocabulary.gd")

const DETECTION_GRACE_S := 5.0
const DETECTION_WINDOW_S := 30.0
const RESPONSE_GRACE_S := 15.0
const RESPONSE_WINDOW_S := 60.0
const STRONG_EVIDENCE_S := 3.0 ## seconds genuinely available at identification quality
const OVERCONFIDENCE_THRESHOLD := 70
const DEGRADED_LOOKAHEAD_S := 30.0
const PENALTY_OVERCONFIDENCE := 4.0 ## P1
const PENALTY_FALSE_ALARM := 8.0 ## P2
const PENALTY_MISSED_THREAT := 5.0 ## P3
const SPAM_ALLOWANCE := 3 ## P4: free invalid/repeated actions
const PENALTY_SPAM_EACH := 1.0
const PENALTY_SPAM_CAP := 5.0
const COMPONENTS := ["detection", "classification", "evidence", "response", "response_time", "degraded"]

## Response credit by expected category: [credit with strong evidence, credit with weak evidence]
const RESPONSE_CREDIT := {
	"background": {"log_observation": [1.0, 1.0], "continue_observing": [0.75, 1.0], "request_identification": [0.75, 1.0], "notify_supervisor": [0.0, 0.0], "training_area_alert": [0.0, 0.0]},
	"unidentified_uav": {"notify_supervisor": [1.0, 1.0], "training_area_alert": [0.75, 0.75], "request_identification": [0.5, 0.75], "continue_observing": [0.5, 0.75], "log_observation": [0.0, 0.0]},
	"swarm": {"training_area_alert": [1.0, 1.0], "notify_supervisor": [0.75, 0.75], "request_identification": [0.5, 0.75], "continue_observing": [0.5, 0.75], "log_observation": [0.0, 0.0]},
}


static func window_credit(latency: float, grace: float, window: float) -> float:
	return clampf((window - latency) / (window - grace), 0.0, 1.0)


static func evaluate(record: Dictionary) -> Dictionary:
	var config: Dictionary = record["scenario"]
	var truth: Dictionary = record["truth"]
	var weights: Dictionary = config["weights"]
	var entities := _entities(record)
	var track_entity := _map_tracks(record, entities)
	var confirmed_t := {}
	for track in record["tracks"]:
		if float(track["confirmed_t"]) >= 0.0:
			confirmed_t[track["id"]] = float(track["confirmed_t"])
	for track_id in track_entity:
		var entity: Dictionary = entities[track_entity[track_id]]
		entity["tracks"].append(track_id)
		if confirmed_t.has(track_id):
			entity["available_t"] = minf(entity["available_t"], confirmed_t[track_id])
	_apply_actions(record, entities, track_entity)

	var findings := []
	var credits := {}
	for key in COMPONENTS:
		credits[key] = []
	var entity_results := []
	var penalties := 0.0
	for entity_id in _sorted_keys(entities):
		var e: Dictionary = entities[entity_id]
		if e["available_t"] == INF:
			if e["significant"] and not e["false_track"]:
				findings.append(_finding("N0", entity_id, 0.0, false, "Never confirmed by the sensors; not scored (no opportunity).", []))
			continue
		if e["false_track"]:
			if e["response"] in Vocabulary.ALARM_RESPONSES:
				penalties += PENALTY_FALSE_ALARM
				findings.append(_finding("P2", entity_id, PENALTY_FALSE_ALARM, true, "Alarm raised for a false (clutter) track.", [e["response_seq"]]))
			continue
		var result := _score_entity(e, record, truth)
		entity_results.append(result)
		for key in ["detection", "classification", "evidence", "response", "response_time"]:
			credits[key].append(result["credits"][key])
		if result["degraded"]:
			credits["degraded"].append((result["credits"]["detection"] + result["credits"]["classification"] + result["credits"]["response"]) / 3.0)
		for f in result["findings"]:
			findings.append(f)
			if f["penalty"]:
				penalties += float(f["points"])

	var spam: int = int(record.get("spam_count", 0))
	if spam > SPAM_ALLOWANCE:
		var points := minf((spam - SPAM_ALLOWANCE) * PENALTY_SPAM_EACH, PENALTY_SPAM_CAP)
		penalties += points
		findings.append(_finding("P4", "", points, true, "%d invalid or repeated actions (%d allowed)." % [spam, SPAM_ALLOWANCE], []))

	var n: int = entity_results.size()
	var active_weight := 0.0
	for key in COMPONENTS:
		if not credits[key].is_empty():
			active_weight += float(weights[key])
	var components := {}
	var weighted := 0.0
	for key in COMPONENTS:
		var values: Array = credits[key]
		var mean := _mean(values) if not values.is_empty() else 0.0
		var effective := float(weights[key]) / active_weight * 100.0 if active_weight > 0.0 and not values.is_empty() else 0.0
		weighted += mean * effective
		components[key] = {"score": snappedf(mean * 100.0, 0.1), "weight": float(weights[key]), "effective_weight": snappedf(effective, 0.01),
			"earned": snappedf(mean * effective, 0.01), "n": values.size()}
	if credits["degraded"].is_empty():
		findings.append(_finding("W1", "", 0.0, false, "No object first appeared during sensor degradation; its weight was shared across the other components.", []))
	if n == 0:
		findings.append(_finding("E0", "", 0.0, false, "No object was confirmed by the sensors; the result is not comparable.", []))
	var score := clampf(weighted - penalties, 0.0, 100.0)
	return {
		"rubric": VERSION, "score": snappedf(score, 0.1), "weighted_score": snappedf(weighted, 0.1),
		"penalty_points": snappedf(penalties, 0.1), "components": components, "entities": entity_results,
		"findings": findings, "comparable": record["status"] == "completed" and n > 0,
		"eligible_entities": n,
	}


## One scoring entity per actor, or per truth swarm group when grouping is enabled,
## plus one per false (clutter) track added during mapping.
static func _entities(record: Dictionary) -> Dictionary:
	var grouping: bool = record["scenario"].get("group_swarms", true)
	var entities := {}
	for actor in record["truth"]["actors"]:
		var id: String = actor["group_id"] if grouping and not String(actor["group_id"]).is_empty() else actor["id"]
		if not entities.has(id):
			entities[id] = _new_entity(id, Vocabulary.TRUTH_CATEGORY_FOR_PROFILE[actor["profile"]], actor["significant"], false)
		entities[id]["actors"].append(actor["id"])
	return entities


static func _new_entity(id: String, category: String, significant: bool, false_track: bool) -> Dictionary:
	return {"id": id, "expected_category": category, "significant": significant, "false_track": false_track,
		"actors": [], "tracks": [], "available_t": INF,
		"ack_t": -1.0, "ack_seq": 0, "category": "", "confidence": 0, "classified_t": -1.0, "classify_seq": 0,
		"response": "", "responded_t": -1.0, "response_seq": 0, "model_recommendation": {}}


## Track → entity by majority vote of its observations' truth links.
static func _map_tracks(record: Dictionary, entities: Dictionary) -> Dictionary:
	var links: Dictionary = record["truth"]["links"]
	var actor_entity := {}
	for id in entities:
		for actor in entities[id]["actors"]:
			actor_entity[actor] = id
	var mapping := {}
	for track in record["tracks"]:
		var votes := {}
		for obs_id in track["obs_ids"]:
			var source: String = links.get(obs_id, "clutter")
			votes[source] = votes.get(source, 0) + 1
		var best := "clutter"
		var best_votes := -1
		for source in _sorted_keys(votes):
			if votes[source] > best_votes:
				best = source
				best_votes = votes[source]
		if best == "clutter":
			var false_id: String = "false:" + String(track["id"])
			entities[false_id] = _new_entity(false_id, "unknown", false, true)
			mapping[track["id"]] = false_id
		else:
			mapping[track["id"]] = actor_entity[best]
	return mapping


## First acknowledgement, final classification (last before the first response)
## and first response of each entity, from valid trainee actions in log order.
static func _apply_actions(record: Dictionary, entities: Dictionary, track_entity: Dictionary) -> void:
	for event in record["events"]:
		if event["type"] != "action" or not event["data"].get("valid", false):
			continue
		var data: Dictionary = event["data"]
		var touched := {}
		for track_id in data.get("members", [data["track_id"]]):
			if track_entity.has(track_id):
				touched[track_entity[track_id]] = true
		for entity_id in touched:
			var e: Dictionary = entities[entity_id]
			match data["kind"]:
				"acknowledge":
					if e["ack_t"] < 0.0:
						e["ack_t"] = float(event["t"])
						e["ack_seq"] = event["seq"]
				"classify":
					if String(e["response"]).is_empty():
						if e["ack_t"] < 0.0:
							e["ack_t"] = float(event["t"])
							e["ack_seq"] = event["seq"]
						e["category"] = data["category"]
						e["confidence"] = int(data["confidence"])
						e["classified_t"] = float(event["t"])
						e["classify_seq"] = event["seq"]
				"respond":
					if String(e["response"]).is_empty():
						e["response"] = data["response"]
						e["responded_t"] = float(event["t"])
						e["response_seq"] = event["seq"]
						e["model_recommendation"] = data.get("model_recommendation", {})


static func _score_entity(e: Dictionary, record: Dictionary, truth: Dictionary) -> Dictionary:
	var findings := []
	var available: float = e["available_t"]
	var expected: String = e["expected_category"]
	var detection := 0.0
	if e["ack_t"] >= 0.0:
		detection = window_credit(maxf(e["ack_t"] - available, 0.0), DETECTION_GRACE_S, DETECTION_WINDOW_S)
	var evidence_at_classification := _evidence_seconds(truth, e["actors"], available, e["classified_t"])
	var strong := evidence_at_classification >= STRONG_EVIDENCE_S
	var category: String = e["category"]
	var classification := 0.0
	var evidence := 0.0
	if category == "unknown":
		classification = 0.5 if strong else 0.75
		evidence = 0.75 if strong else 1.0
	elif not category.is_empty():
		var correct := category == expected
		classification = 1.0 if correct else 0.0
		evidence = (1.0 if correct else 0.0) if strong else 0.25
		if int(e["confidence"]) > OVERCONFIDENCE_THRESHOLD and not strong:
			findings.append(_finding("P1", e["id"], PENALTY_OVERCONFIDENCE, true,
				"Specific classification at %d%% confidence with only %.0f s of identification-quality availability (need %.0f s)." % [e["confidence"], evidence_at_classification, STRONG_EVIDENCE_S], [e["classify_seq"]]))
	var response_key := _response_key(expected)
	var entered_zone := _entered_zone(truth, e["actors"])
	var evidence_at_response := _evidence_seconds(truth, e["actors"], available, e["responded_t"])
	var response := 0.0
	var response_time := 0.0
	if not String(e["response"]).is_empty():
		var pair: Array = RESPONSE_CREDIT[response_key][e["response"]]
		response = pair[0] if evidence_at_response >= STRONG_EVIDENCE_S else pair[1]
		if expected == "unidentified_uav" and e["response"] == "training_area_alert" and entered_zone:
			response = 1.0
		response_time = 0.4 + 0.6 * window_credit(maxf(e["responded_t"] - available, 0.0), RESPONSE_GRACE_S, RESPONSE_WINDOW_S)
		if e["response"] in Vocabulary.ALARM_RESPONSES and not e["significant"]:
			findings.append(_finding("P2", e["id"], PENALTY_FALSE_ALARM, true, "%s for a non-threat (%s)." % [Vocabulary.RESPONSE_LABELS[e["response"]], Vocabulary.CATEGORY_LABELS[expected]], [e["response_seq"]]))
	elif e["significant"]:
		findings.append(_finding("P3", e["id"], PENALTY_MISSED_THREAT, true, "Threat was confirmed by the sensors at %s but received no response." % _clock(available), []))
	var credits := {"detection": detection, "classification": classification, "evidence": evidence, "response": response, "response_time": response_time}
	for key in credits:
		if credits[key] < 1.0:
			findings.append(_finding(key.to_upper(), e["id"], 0.0, false, _explain(key, e, credits[key], evidence_at_classification, available), [e["ack_seq"], e["classify_seq"], e["response_seq"]]))
	return {
		"entity": e["id"], "expected_category": expected, "significant": e["significant"], "tracks": e["tracks"],
		"available_t": available, "ack_t": e["ack_t"], "category": category, "confidence": e["confidence"],
		"correct": category == expected, "evidence_s": evidence_at_classification, "response": e["response"],
		"responded_t": e["responded_t"], "best_response": _best_response(response_key, entered_zone),
		"model_recommendation": e["model_recommendation"], "degraded": _degraded(record["scenario"], available),
		"credits": credits, "findings": findings,
	}


static func _response_key(expected: String) -> String:
	if expected in ["bird", "balloon", "authorised_uav"]:
		return "background"
	return expected


static func _best_response(key: String, entered_zone: bool) -> String:
	if key == "unidentified_uav":
		return "notify_supervisor (or training_area_alert)" if entered_zone else "notify_supervisor"
	return {"background": "log_observation", "swarm": "training_area_alert"}[key]


## Seconds (1 s samples) in which any of `actors` was genuinely available at
## identification quality, from `from_t` up to `until_t` (end of record if < 0).
static func _evidence_seconds(truth: Dictionary, actors: Array, from_t: float, until_t: float) -> float:
	var seconds := 0.0
	for sample in truth["availability"]:
		var t := float(sample["t"])
		if t < from_t or (until_t >= 0.0 and t > until_t):
			continue
		for actor in actors:
			if actor in sample["id"]:
				seconds += 1.0
				break
	return seconds


static func _entered_zone(truth: Dictionary, actors: Array) -> bool:
	for sample in truth["availability"]:
		for actor in actors:
			if actor in sample["zone"]:
				return true
	return false


static func _degraded(config: Dictionary, available: float) -> bool:
	for window in config["sensor"]["degradation"]:
		if available < float(window["end_s"]) and available + DEGRADED_LOOKAHEAD_S > float(window["start_s"]):
			return true
	return false


static func _explain(key: String, e: Dictionary, credit: float, evidence_s: float, available: float) -> String:
	match key:
		"detection":
			if e["ack_t"] < 0.0:
				return "Never acknowledged after the sensors confirmed it at %s." % _clock(available)
			return "Acknowledged %.0f s after confirmation (full credit within %.0f s, none after %.0f s)." % [e["ack_t"] - available, DETECTION_GRACE_S, DETECTION_WINDOW_S]
		"classification":
			if String(e["category"]).is_empty():
				return "Not classified."
			if e["category"] == "unknown":
				return "Classified as unknown (%.0f%% credit) with %.0f s of identification-quality availability." % [credit * 100.0, evidence_s]
			return "Classified as %s; the object was %s." % [Vocabulary.CATEGORY_LABELS[e["category"]], Vocabulary.CATEGORY_LABELS[e["expected_category"]]]
		"evidence":
			return "Confidence handling: %.0f s of identification-quality availability before classifying (%.0f s needed for a specific call)." % [evidence_s, STRONG_EVIDENCE_S]
		"response":
			if String(e["response"]).is_empty():
				return "No procedural response."
			return "%s gave %.0f%% credit for this object." % [Vocabulary.RESPONSE_LABELS[e["response"]], credit * 100.0]
		"response_time":
			if String(e["response"]).is_empty():
				return "No response, so no timeliness credit."
			return "Responded %.0f s after confirmation (full credit within %.0f s, minimum after %.0f s)." % [e["responded_t"] - available, RESPONSE_GRACE_S, RESPONSE_WINDOW_S]
	return ""


static func _finding(rule: String, entity: String, points: float, penalty: bool, reason: String, seqs: Array) -> Dictionary:
	var anchors := []
	for s in seqs:
		if int(s) > 0:
			anchors.append(int(s))
	return {"rule": rule, "entity": entity, "points": snappedf(points, 0.01), "penalty": penalty, "reason": reason, "event_seqs": anchors}


static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


static func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total / values.size()


static func _clock(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
