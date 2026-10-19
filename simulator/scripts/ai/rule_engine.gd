extends RefCounted
## Model 1 — transparent rule-based baseline classifier. Rule-based, NOT machine
## learning. Input: features-1 of one track (observation-derived only). Output:
## category, confidence (a rule-assigned score, not a calibrated probability),
## evidence quality, the rule that fired and a plain-language explanation.
## Rules are checked in the order listed; the first match wins.

const VERSION := "rules-da-1"

## Evidence quality from the amount and kind of observation.
const MIN_DURATION_S := 6.0
const MIN_HITS := 5
const GOOD_EO_ID_HITS := 5
const GOOD_RADAR_HITS := 15
const GOOD_DURATION_S := 15.0

## [code, category, base confidence, description]
const RULES := [
	["R1_ID_REPLY", "authorised_uav", 0.85, "cooperative ID reply on at least half of radar returns"],
	["R2_SWARM", "swarm", 0.8, "two or more neighbouring tracks moving together (swarm group)"],
	["R3_WIND_DRIFT", "balloon", 0.8, "moves with the reported wind at almost zero air speed"],
	["R4_WING_BEAT", "bird", 0.85, "wing beat seen on at least half of identification-quality camera looks"],
	["R5_ERRATIC", "bird", 0.6, "erratic turning at bird-like speed without a large apparent size"],
	["R6_LARGE_SLOW", "balloon", 0.7, "large apparent size and very slow"],
	["R7_UAV_KINEMATICS", "unidentified_uav", 0.65, "powered-flight kinematics with no cooperative ID reply"],
]


static func evidence_quality(f: Dictionary) -> String:
	if f["duration_s"] < MIN_DURATION_S or f["hits"] < MIN_HITS:
		return "insufficient"
	if f["eo_id_hits"] >= GOOD_EO_ID_HITS or (f["radar_hits"] >= GOOD_RADAR_HITS and f["duration_s"] >= GOOD_DURATION_S):
		return "good"
	return "fair"


## Returns {model, category, confidence, evidence, rule, reason_codes, explanation}.
static func assess(f: Dictionary) -> Dictionary:
	var evidence := evidence_quality(f)
	if evidence == "insufficient":
		return _result("unknown", 0.3, evidence, "R0_INSUFFICIENT",
			"Not enough observation yet (%.0f s, %d observations; need %.0f s and %d)." % [f["duration_s"], int(f["hits"]), MIN_DURATION_S, MIN_HITS])
	for rule in RULES:
		if _matches(rule[0], f):
			var confidence: float = rule[2] * (1.0 if evidence == "good" else 0.85)
			return _result(rule[1], confidence, evidence, rule[0], "%s: %s." % [rule[0], rule[3]])
	return _result("unknown", 0.35, evidence, "R8_NO_MATCH", "No rule matched the observed behaviour; treat as unknown.")


static func _matches(code: String, f: Dictionary) -> bool:
	match code:
		"R1_ID_REPLY":
			return f["radar_hits"] >= 3 and f["id_reply_fraction"] >= 0.5
		"R2_SWARM":
			return f["neighbor_count"] >= 2 or f["in_swarm_group"] > 0.5
		"R3_WIND_DRIFT":
			return f["air_speed_mean"] < 2.0 and f["wind_alignment"] > 0.7
		"R4_WING_BEAT":
			return f["eo_id_hits"] >= 3 and f["flap_fraction"] >= 0.5
		"R5_ERRATIC":
			return f["turn_rate_mean_dps"] > 25.0 and f["speed_mean"] >= 4.0 and f["speed_mean"] <= 16.0 and (f["has_size"] < 0.5 or f["size_mean"] < 0.9)
		"R6_LARGE_SLOW":
			return f["has_size"] > 0.5 and f["size_mean"] >= 1.4 and f["speed_mean"] < 4.0
		"R7_UAV_KINEMATICS":
			return f["radar_hits"] >= 5 and f["id_reply_fraction"] < 0.2 and f["speed_mean"] <= 16.0 and f["turn_rate_mean_dps"] <= 25.0
	return false


static func _result(category: String, confidence: float, evidence: String, rule: String, explanation: String) -> Dictionary:
	return {"model": VERSION, "method": "rule-based", "category": category, "confidence": snappedf(confidence, 0.01),
		"evidence": evidence, "rule": rule, "reason_codes": [rule], "explanation": explanation}
