extends RefCounted
## Synthetic onboard radar for flight training. It is the ONLY source of contacts for
## the trainee's radar display: the display never reads ground-truth positions.
##
## Model (a training simplification, documented in docs/SCENARIOS.md):
##  * updates every `update_interval_s`; only objects within `range_m` (projectiles:
##    `projectile_range_m`) can be detected;
##  * detection probability falls linearly from `pd_near` at 0 m to `pd_far` at the
##    range limit, so distant contacts drop out now and then;
##  * reported positions carry seeded Gaussian noise (σ = `noise_m` + `noise_per_m` × range);
##  * a contact not detected for `persistence_s` is shown as stale (last known
##    position, marked uncertain) and is dropped after `drop_s`;
##  * association is ideal (each detection is matched to the right contact); the
##    sensor still hides truth ids behind its own contact ids (C01, C02, …).
## Classification uses observable cues only:
##  * cooperative identification reply (friendly drones reply with probability
##    `iff_reply_p`) → "friendly";
##  * measured speed above `projectile_speed_mps` → "projectile";
##  * closing on the trainee's drone (smoothed range rate) for about `closing_updates` updates within
##    `closing_range_m` → "hostile" (behaviour-based; a harmless drone that happens
##    to head straight for you can be marked hostile too);
##  * otherwise "unknown".

const DEFAULTS := {
	"range_m": 160.0,
	"projectile_range_m": 140.0,
	"update_interval_s": 0.5,
	"pd_near": 0.97,
	"pd_far": 0.6,
	"noise_m": 1.0,
	"noise_per_m": 0.012,
	"persistence_s": 1.6,
	"drop_s": 4.0,
	"iff_reply_p": 0.95,
	"projectile_speed_mps": 16.0,
	"closing_updates": 3,
	"closing_range_m": 110.0,
	"closing_rate_mps": 1.5,
}

var config := {}
var contacts := {} ## contact id -> contact dictionary (see _contact())
var time_s := 0.0
var detections := 0
var missed := 0

var _rng := RandomNumberGenerator.new()
var _next_update := 0.0
var _contact_for_truth := {} ## truth id -> contact id (internal; never exported)
var _next_id := 1


func _init(seed: int, overrides := {}) -> void:
	_rng.seed = seed
	config = DEFAULTS.duplicate()
	config.merge(overrides, true)


## Advances the sensor clock. `truth` = active entities ({id, kind, position, velocity, iff}).
## Returns true when a sensor update happened this call.
func step(dt: float, own: Vector3, truth: Array) -> bool:
	time_s += dt
	if time_s + 0.0001 < _next_update:
		return false
	_next_update = time_s + float(config["update_interval_s"])
	var seen := {}
	for entity in truth:
		var offset: Vector3 = entity["position"] - own
		var distance := offset.length()
		var limit: float = config["projectile_range_m"] if entity["kind"] == "projectile" else config["range_m"]
		if distance > limit:
			continue
		var pd := lerpf(float(config["pd_near"]), float(config["pd_far"]), clampf(distance / limit, 0.0, 1.0))
		if _rng.randf() > pd:
			missed += 1
			continue
		detections += 1
		var sigma: float = config["noise_m"] + config["noise_per_m"] * distance
		var measured: Vector3 = entity["position"] + Vector3(_rng.randfn(0.0, sigma), _rng.randfn(0.0, sigma * 0.5), _rng.randfn(0.0, sigma))
		var replied: bool = entity["iff"] and _rng.randf() < float(config["iff_reply_p"])
		_update_contact(entity["id"], measured, replied, own)
		seen[entity["id"]] = true
	for truth_id in _contact_for_truth.keys():
		var contact: Dictionary = contacts[_contact_for_truth[truth_id]]
		var age := time_s - float(contact["last_seen_t"])
		contact["stale"] = age > float(config["persistence_s"])
		if age > float(config["drop_s"]):
			contacts.erase(contact["id"])
			_contact_for_truth.erase(truth_id)
	return true


func _update_contact(truth_id: String, measured: Vector3, replied: bool, own: Vector3) -> void:
	var id: String = _contact_for_truth.get(truth_id, "")
	if id.is_empty():
		id = "C%02d" % _next_id
		_next_id += 1
		_contact_for_truth[truth_id] = id
		contacts[id] = {"id": id, "position": measured, "velocity": Vector3.ZERO, "kind": "unknown", "last_seen_t": time_s,
			"first_seen_t": time_s, "stale": false, "iff_replies": 0, "updates": 0, "closing": 0, "range": measured.distance_to(own)}
	var contact: Dictionary = contacts[id]
	var dt := time_s - float(contact["last_seen_t"])
	if dt > 0.05:
		var raw: Vector3 = (measured - contact["position"]) / dt
		contact["velocity"] = raw if contact["updates"] < 2 else (contact["velocity"] as Vector3).lerp(raw, 0.5)
	var new_range := measured.distance_to(own)
	# Range rate from the smoothed velocity (less noisy than differencing two ranges).
	var range_rate := (contact["velocity"] as Vector3).dot((measured - own).normalized())
	var closing := range_rate < -float(config["closing_rate_mps"]) and new_range < float(config["closing_range_m"])
	contact["closing"] = int(contact["closing"]) + 1 if closing else maxi(int(contact["closing"]) - 1, 0)
	contact["range"] = new_range
	contact["position"] = measured
	contact["last_seen_t"] = time_s
	contact["stale"] = false
	contact["updates"] = int(contact["updates"]) + 1
	contact["iff_replies"] = int(contact["iff_replies"]) + int(replied)
	contact["kind"] = classify(contact)


func classify(contact: Dictionary) -> String:
	if int(contact["iff_replies"]) > 0:
		return "friendly"
	if contact["updates"] >= 2 and (contact["velocity"] as Vector3).length() > float(config["projectile_speed_mps"]):
		return "projectile"
	if contact["kind"] == "hostile" or int(contact["closing"]) >= int(config["closing_updates"]):
		return "hostile"
	return "unknown"


## How many different contacts the sensor has reported so far.
func contacts_seen() -> int:
	return _next_id - 1


## Contacts for display, sorted by id (positions as last measured).
func contact_list() -> Array:
	var ids := contacts.keys()
	ids.sort()
	var out := []
	for id in ids:
		out.append(contacts[id])
	return out


## Projectile contacts (fresh, from sensor measurements) whose straight path will pass
## within `radius` of a drone at `own` moving at `own_velocity` in the next `horizon`
## seconds: [{id, eta, closest, from: unit vector toward the contact}], soonest first.
## This drives the incoming warning, so the warning is only as good as the sensor.
func incoming(own: Vector3, own_velocity: Vector3, horizon := 4.0, radius := 12.0) -> Array:
	var result := []
	for contact in contacts.values():
		if contact["kind"] != "projectile" or contact["stale"]:
			continue
		var relative: Vector3 = contact["position"] - own
		var rel_velocity: Vector3 = contact["velocity"] - own_velocity
		var speed_sq := rel_velocity.length_squared()
		if speed_sq < 0.01:
			continue
		var t := -relative.dot(rel_velocity) / speed_sq
		if t < 0.0 or t > horizon:
			continue
		var closest := (relative + rel_velocity * t).length()
		if closest <= radius:
			result.append({"id": contact["id"], "eta": t, "closest": closest, "from": relative.normalized()})
	result.sort_custom(func(a, b): return a["eta"] < b["eta"])
	return result
