extends RefCounted
## adapt-da-1: explainable, bounded difficulty adaptation (RULE-BASED, not machine
## learning), modelled on VIGIL's rules-1. Input: saved session records. Output: the
## next recommended scenario config (a fresh seed through the procedural generator)
## with the rule that fired and plain-language reasons. Deterministic: the same
## history always gives the same recommendation.

const VERSION := "adapt-da-1"
const ScenarioConfig := preload("res://scripts/sim/scenario_config.gd")
const Rubric := preload("res://scripts/training/rubric.gd")

const WINDOW := 5 ## most recent comparable sessions considered
const MIN_RECENT := 3 ## sessions needed before difficulty may change
const MAX_SPREAD := 20.0 ## score range above which results are "inconsistent"
const STRONG_SCORE := 80.0
const WEAK_SCORE := 55.0
const SEED_STRIDE := 7919
const FOUNDATION_SEED := 26247
const COMPONENT_LABELS := {
	"detection": "detection timeliness", "classification": "classification", "evidence": "evidence-based confidence",
	"response": "response appropriateness", "response_time": "response time", "degraded": "degraded conditions",
}


static func recommend(records: Array) -> Dictionary:
	var comparable := records.filter(func(r): return r["status"] == "completed" and r["evaluation"]["comparable"])
	comparable.sort_custom(func(a, b): return String(a["created_at"]) < String(b["created_at"]) or (a["created_at"] == b["created_at"] and String(a["session_id"]) < String(b["session_id"])))
	var used_seeds := {}
	for r in records:
		used_seeds[int(r["scenario"]["seed"])] = true
	var reasons := PackedStringArray()
	if comparable.is_empty():
		reasons.append("No completed, comparable session yet: start with a level-1 foundation exercise (one threat, daylight, clear).")
		var config := _config(FOUNDATION_SEED, used_seeds, {"difficulty": 1, "single": true, "time_of_day": "day", "visibility": "clear"})
		return _result("foundation", 1, 1, "", reasons, [], config, records.size() - comparable.size())
	var window := comparable.slice(maxi(comparable.size() - WINDOW, 0))
	var recent := comparable.slice(maxi(comparable.size() - MIN_RECENT, 0))
	var latest: Dictionary = comparable[-1]
	var baseline := int(latest["scenario"]["difficulty"])
	var means := _component_means(window)
	var weakest := _weakest(means)
	var scores := recent.map(func(r): return float(r["evaluation"]["score"]))
	var spread: float = scores.max() - scores.min()
	var difficulty := baseline
	var rule := "consolidate"
	if recent.size() < MIN_RECENT:
		rule = "sparse"
		reasons.append("Hold level %d: only %d comparable session(s); %d consistent results are needed before the level changes." % [baseline, recent.size(), MIN_RECENT])
	elif spread > MAX_SPREAD:
		rule = "inconsistent"
		reasons.append("Hold level %d: the last %d scores vary by %.0f points (more than %.0f). One good or bad run is not enough evidence." % [baseline, recent.size(), spread, MAX_SPREAD])
	elif scores.min() >= STRONG_SCORE and not _has_penalties(recent, ["P2", "P3"]):
		if baseline < 5:
			difficulty = baseline + 1
			rule = "increase"
			reasons.append("Increase to level %d: the last %d scores were all at least %.0f with no missed threats or false alarms." % [difficulty, recent.size(), STRONG_SCORE])
		else:
			rule = "ceiling"
			reasons.append("Hold level 5, the highest level: results are strong.")
	elif scores.max() < WEAK_SCORE:
		if baseline > 1:
			difficulty = baseline - 1
			rule = "decrease"
			reasons.append("Reduce to level %d: the last %d scores were all below %.0f; practise with fewer objects and better sensors." % [difficulty, recent.size(), WEAK_SCORE])
		else:
			rule = "floor"
			reasons.append("Hold level 1, the lowest level: focus on the weakest skill below.")
	else:
		reasons.append("Hold level %d: results are between the increase (%.0f) and decrease (%.0f) thresholds." % [baseline, STRONG_SCORE, WEAK_SCORE])
	var options := {"difficulty": difficulty}
	if not weakest.is_empty():
		reasons.append("Focus: %s is your lowest average component (%.0f%% over %d session(s))." % [COMPONENT_LABELS[weakest], means[weakest], window.size()])
		match weakest:
			"classification", "evidence":
				options.merge({"time_of_day": "day", "visibility": "clear"})
				reasons.append("Next exercise uses daylight and clear visibility so identification cues are easier to practise.")
			"detection", "response_time":
				options["swarm"] = false
				reasons.append("Next exercise leaves out the swarm so you can concentrate on noticing and answering each track promptly.")
			"degraded":
				options["visibility"] = "fog"
				reasons.append("Next exercise uses fog to practise decisions under reduced sensor quality.")
			"response":
				reasons.append("Conditions are kept; review the response table in the briefing before starting.")
	var config := _config(int(latest["scenario"]["seed"]) + SEED_STRIDE, used_seeds, options)
	reasons.append("Fresh seed %d (not used by any saved session). Only completed, comparable sessions are counted; %d other session(s) excluded." % [config["seed"], records.size() - comparable.size()])
	var ids := window.map(func(r): return r["session_id"])
	return _result(rule, baseline, difficulty, weakest, reasons, ids, config, records.size() - comparable.size())


static func _config(start_seed: int, used: Dictionary, options: Dictionary) -> Dictionary:
	var seed_value := start_seed & 0xFFFFFFFF
	var guard := 0
	while used.has(seed_value) and guard < 10000:
		seed_value = (seed_value + SEED_STRIDE) & 0xFFFFFFFF
		guard += 1
	return ScenarioConfig.generate(seed_value, options)["config"]


static func _component_means(records: Array) -> Dictionary:
	var means := {}
	for key in Rubric.COMPONENTS:
		var values := []
		for r in records:
			var comp: Dictionary = r["evaluation"]["components"][key]
			if int(comp["n"]) > 0:
				values.append(float(comp["score"]))
		if not values.is_empty():
			var total := 0.0
			for v in values:
				total += v
			means[key] = total / values.size()
	return means


static func _weakest(means: Dictionary) -> String:
	var best := ""
	for key in Rubric.COMPONENTS:
		if means.has(key) and (best.is_empty() or means[key] < means[best]):
			best = key
	return best


static func _has_penalties(records: Array, rules: Array) -> bool:
	for r in records:
		for f in r["evaluation"]["findings"]:
			if f["rule"] in rules:
				return true
	return false


static func _result(rule: String, baseline: int, difficulty: int, focus: String, reasons: PackedStringArray, evidence: Array, config: Dictionary, excluded: int) -> Dictionary:
	return {"policy": VERSION, "method": "rule-based", "rule": rule, "baseline_difficulty": baseline, "difficulty": difficulty,
		"difficulty_change": "increase" if difficulty > baseline else ("decrease" if difficulty < baseline else "hold"),
		"focus": focus, "reasons": reasons, "evidence_session_ids": evidence, "excluded_sessions": excluded, "config": config}
