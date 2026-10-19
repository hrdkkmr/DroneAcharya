extends RefCounted
## Shared training vocabulary: assessment categories and procedural responses.
## Responses are communication/procedure steps only — no engagement actions exist.

const CATEGORIES := ["bird", "balloon", "authorised_uav", "unidentified_uav", "swarm", "unknown"]
const CATEGORY_LABELS := {
	"bird": "Bird (biological)", "balloon": "Drifting balloon", "authorised_uav": "Authorised UAV",
	"unidentified_uav": "Unidentified UAV", "swarm": "Coordinated swarm", "unknown": "Unknown / insufficient evidence",
}
const RESPONSES := ["continue_observing", "request_identification", "log_observation", "notify_supervisor", "training_area_alert"]
const RESPONSE_LABELS := {
	"continue_observing": "Continue observing", "request_identification": "Request additional identification",
	"log_observation": "Log the observation", "notify_supervisor": "Notify the supervisor",
	"training_area_alert": "Issue a training-area alert",
}
## Responses that count as raising an alarm (false alarm if the object is not a threat).
const ALARM_RESPONSES := ["notify_supervisor", "training_area_alert"]

## Evaluation only: the category a correct trainee should assign to each truth profile.
## Never use this mapping at inference time.
const TRUTH_CATEGORY_FOR_PROFILE := {
	"bird": "bird", "balloon": "balloon", "authorised_uav": "authorised_uav",
	"unidentified_uav": "unidentified_uav", "swarm_uav": "swarm",
}
