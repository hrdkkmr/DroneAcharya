extends RefCounted
## Runs the decision models for every confirmed track once per second:
## features-1 → Model 1 (rules) and, when loaded, Model 2 (ML classifier) →
## Model 3 (policy). The policy uses the ML assessment when a model is loaded and
## valid, otherwise the rule-based baseline (a labelled fallback). Inputs are tracker
## output and public context only. Every change is returned as a loggable event.

const Features := preload("res://scripts/ai/features.gd")
const RuleEngine := preload("res://scripts/ai/rule_engine.gd")
const DecisionPolicy := preload("res://scripts/ai/decision_policy.gd")

var context: Dictionary
var classifier: RefCounted = null ## optional ML classifier (Phase 4); null = rules only
## track id -> {features, rules, ml, policy, t}
var latest := {}


func _init(public_context: Dictionary, ml_classifier: RefCounted = null) -> void:
	context = public_context
	classifier = ml_classifier


func ml_active() -> bool:
	return classifier != null and classifier.is_loaded()


## Re-assesses all confirmed tracks. Returns events for anything that changed.
func update(tracks: Array, now: float) -> Array:
	var events := []
	for track in tracks:
		var features := Features.extract(track, tracks, context, now)
		var rules := RuleEngine.assess(features)
		var ml := {}
		if ml_active():
			ml = classifier.predict(features)
		var basis := ml if not ml.is_empty() and ml.get("ok", false) else rules
		var policy := DecisionPolicy.recommend(basis, features)
		var previous: Dictionary = latest.get(track["id"], {})
		latest[track["id"]] = {"features": features, "rules": rules, "ml": ml, "policy": policy, "t": now}
		if previous.is_empty() or _summary(previous) != _summary(latest[track["id"]]):
			var event := {"track_id": track["id"], "rules": _short(rules), "policy": {"response": policy["response"], "reason_code": policy["reason_code"], "based_on": policy["based_on"]}}
			if not ml.is_empty():
				event["ml"] = _short(ml)
			events.append(event)
	return events


func recommendation_for(track_id: String) -> Dictionary:
	return latest.get(track_id, {})


static func _short(a: Dictionary) -> Dictionary:
	var result := {"model": a.get("model", ""), "category": a.get("category", ""), "confidence": a.get("confidence", 0.0), "evidence": a.get("evidence", "")}
	if a.has("rule"):
		result["rule"] = a["rule"]
	return result


static func _summary(entry: Dictionary) -> String:
	var ml: Dictionary = entry["ml"]
	return "%s|%s|%s|%s|%s" % [entry["rules"]["category"], entry["rules"]["evidence"], entry["policy"]["response"],
		ml.get("category", ""), entry["policy"]["reason_code"]]
