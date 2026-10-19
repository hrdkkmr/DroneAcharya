extends RefCounted
## Model 3 — decision/response recommendation policy (rule-based, not ML).
## Consumes an assessment (from the rule engine or the ML classifier), its evidence
## quality and confidence, and public scenario geometry. It never sees ground truth.
## Classification and response selection are deliberately separate components.
## Confidence values are treated as uncalibrated scores (thresholds only).

const VERSION := "policy-da-1"
const MIN_CONFIDENCE := 0.6 ## below this the policy asks for more identification

## [reason code, response, explanation]
const TABLE := {
	"P_INSUFFICIENT": ["continue_observing", "Evidence is insufficient to classify; keep observing."],
	"P_INSUFFICIENT_UAV_LIKE": ["request_identification", "Too little evidence, but the motion looks powered and there is no cooperative ID; request additional identification."],
	"P_UNKNOWN": ["request_identification", "The assessment is unknown; request additional identification."],
	"P_LOW_CONFIDENCE": ["request_identification", "The assessment confidence is below the policy threshold; request additional identification before acting."],
	"P_BACKGROUND": ["log_observation", "Assessed as a background object (bird or balloon); log it."],
	"P_COOPERATIVE": ["log_observation", "Assessed as authorised traffic with a cooperative ID; log it."],
	"P_UNIDENTIFIED": ["notify_supervisor", "Assessed as an unidentified UAV outside the protected area; notify the supervisor."],
	"P_UNIDENTIFIED_IN_ZONE": ["training_area_alert", "Assessed as an unidentified UAV inside the protected area; issue a training-area alert."],
	"P_SWARM": ["training_area_alert", "Assessed as a coordinated swarm; issue a training-area alert."],
}


## assessment: {category, confidence, evidence}; features: features-1 dictionary.
## Returns {policy, response, reason_code, explanation, based_on}.
static func recommend(assessment: Dictionary, features: Dictionary) -> Dictionary:
	var code := _choose(assessment, features)
	return {
		"policy": VERSION, "method": "rule-based", "response": TABLE[code][0], "reason_code": code,
		"explanation": TABLE[code][1], "based_on": assessment.get("model", "unknown"),
	}


static func _choose(a: Dictionary, f: Dictionary) -> String:
	if a["evidence"] == "insufficient":
		var uav_like: bool = f["speed_mean"] > 3.0 and f["id_reply_fraction"] < 0.2 and f["flap_fraction"] < 0.5
		return "P_INSUFFICIENT_UAV_LIKE" if uav_like else "P_INSUFFICIENT"
	if a["category"] == "unknown":
		return "P_UNKNOWN"
	if float(a["confidence"]) < MIN_CONFIDENCE:
		return "P_LOW_CONFIDENCE"
	match a["category"]:
		"bird", "balloon":
			return "P_BACKGROUND"
		"authorised_uav":
			return "P_COOPERATIVE"
		"swarm":
			return "P_SWARM"
		"unidentified_uav":
			return "P_UNIDENTIFIED_IN_ZONE" if f["zone_distance_last"] <= 1.0 else "P_UNIDENTIFIED"
	return "P_UNKNOWN"
