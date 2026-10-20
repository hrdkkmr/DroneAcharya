extends RefCounted
## Ground truth of everything else flying in a flight-training mission: friendly patrol
## drones, unknown transiting drones and, in hostile-area missions, a hostile drone and
## fictional ground emplacements that launch slow simulated projectiles.
##
## Training-game mechanics only. Projectiles fly in a straight line at constant speed
## toward where the trainee's drone was at launch (no lead, no prediction, no guidance).
## The hostile drone simply moves toward the trainee's drone at a fixed, modest speed
## when it is near, and gives up after a while. Nothing here models real weapons.
##
## Pure and deterministic: stepped at a fixed dt with the trainee's position; all
## randomness comes from one seeded generator. An optional `blocker` Callable
## (from: Vector3, to: Vector3) -> bool lets the scene stop projectiles at buildings
## and hold fire without line of sight; tests run without it.

const DEFAULTS := {
	"friendlies": 2, ## patrol drones with a cooperative identification reply
	"unknown_interval_s": [25.0, 40.0], ## a harmless unknown drone crosses the area this often
	"site_range_m": 120.0, ## emplacements launch only when the trainee is this close
	"cooldown_s": [6.0, 9.0],
	"first_shot_delay_s": 4.0,
	"projectile_speed": 22.0, ## m/s, slow enough to see and avoid
	"projectile_max_distance": 180.0,
	"hit_radius": 2.0,
	"damage": 35.0,
	"hostile_detect_m": 90.0,
	"hostile_speed": 4.5, ## m/s; slower than every drone profile's top speed
	"hostile_give_up_s": 25.0,
	"hostile_break_off_s": 10.0,
}

var config := {}
var sites: Array = [] ## Vector3 ground positions of hostile emplacements (briefed areas)
var entities: Array = [] ## {id, kind, position, velocity, iff, active, ...}
var time_s := 0.0
var blocker: Callable
var events: Array = [] ## {t, type, data}, drained by take_events()

var _rng := RandomNumberGenerator.new()
var _next_id := 1
var _site_timers: Array = []
var _next_unknown := 0.0
var _area: Rect2


## `mission` provides `area` (Rect2), `route` and optional `threats` overrides.
func _init(mission: Dictionary, area: Rect2, seed: int) -> void:
	_rng.seed = seed
	_area = area
	config = DEFAULTS.duplicate()
	config.merge(mission.get("threat_config", {}), true)
	var route: Dictionary = mission.get("route", {})
	var centre := Vector3(area.get_center().x, 0, area.get_center().y)
	if mission.get("traffic", false):
		for i in int(config["friendlies"]):
			var anchor := centre + Vector3(_rng.randf_range(-80, 80), 0, _rng.randf_range(-80, 80))
			_spawn("friendly", anchor + Vector3(30, _rng.randf_range(28.0, 40.0), 0), Vector3.ZERO, true,
				{"anchor": anchor, "radius": _rng.randf_range(30.0, 50.0), "angle": _rng.randf() * TAU, "speed": 6.0})
		_next_unknown = _rng.randf_range(5.0, 12.0)
	if mission.get("hostile", false):
		for site in mission.get("sites", []):
			sites.append(site)
			_site_timers.append(float(config["first_shot_delay_s"]) + _rng.randf_range(0.0, 2.0))
		var patrol: Vector3 = mission.get("hostile_patrol", centre + Vector3(0, 30, 0))
		_spawn("hostile_drone", patrol, Vector3.ZERO, false,
			{"anchor": patrol, "angle": 0.0, "mode": "patrol", "mode_t": 0.0})


func _spawn(kind: String, position: Vector3, velocity: Vector3, iff: bool, extra := {}) -> Dictionary:
	var entity := {"id": "E%02d" % _next_id, "kind": kind, "position": position, "velocity": velocity, "iff": iff, "active": true}
	entity.merge(extra)
	_next_id += 1
	entities.append(entity)
	_log("spawned", {"id": entity["id"], "kind": kind})
	return entity


## Advances by `dt` seconds. `own` is the trainee drone's position; returns the
## damage dealt this step (0 when nothing hit).
func step(dt: float, own: Vector3) -> float:
	if dt <= 0.0 or not is_finite(dt):
		return 0.0
	time_s += dt
	var damage := 0.0
	for entity in entities:
		if not entity["active"]:
			continue
		match entity["kind"]:
			"friendly":
				_patrol(entity, dt)
			"unknown":
				entity["position"] += entity["velocity"] * dt
				if not _area.grow(40.0).has_point(Vector2(entity["position"].x, entity["position"].z)):
					_retire(entity, "left the area")
			"hostile_drone":
				damage += _hostile_step(entity, dt, own)
			"projectile":
				damage += _projectile_step(entity, dt, own)
	_maybe_spawn_unknown()
	_fire(own)
	entities = entities.filter(func(e): return e["active"])
	return damage


func _patrol(entity: Dictionary, dt: float) -> void:
	entity["angle"] = fmod(float(entity["angle"]) + float(entity["speed"]) / float(entity["radius"]) * dt, TAU)
	var anchor: Vector3 = entity["anchor"]
	var target := Vector3(anchor.x + cos(entity["angle"]) * entity["radius"], entity["position"].y, anchor.z + sin(entity["angle"]) * entity["radius"])
	entity["velocity"] = (target - entity["position"]) / dt
	entity["position"] = target


func _maybe_spawn_unknown() -> void:
	if _next_unknown <= 0.0 or time_s < _next_unknown:
		return
	var interval: Array = config["unknown_interval_s"]
	_next_unknown = time_s + _rng.randf_range(interval[0], interval[1])
	# Enter from a random edge and cross to the opposite one.
	var angle := _rng.randf() * TAU
	var centre := Vector3(_area.get_center().x, 0, _area.get_center().y)
	var reach := maxf(_area.size.x, _area.size.y) * 0.6
	var start := centre + Vector3(cos(angle), 0, sin(angle)) * reach + Vector3(0, _rng.randf_range(30.0, 50.0), 0)
	var through := centre + Vector3(_rng.randf_range(-60, 60), start.y, _rng.randf_range(-60, 60))
	_spawn("unknown", start, (through - start).normalized() * _rng.randf_range(7.0, 10.0), false)


func _hostile_step(entity: Dictionary, dt: float, own: Vector3) -> float:
	var to_own: Vector3 = own - entity["position"]
	var distance := to_own.length()
	entity["mode_t"] = float(entity["mode_t"]) + dt
	var speed: float = config["hostile_speed"]
	match entity["mode"]:
		"patrol":
			entity["angle"] = fmod(float(entity["angle"]) + 0.12 * dt, TAU)
			var anchor: Vector3 = entity["anchor"]
			var target := anchor + Vector3(cos(entity["angle"]) * 25.0, 0, sin(entity["angle"]) * 25.0)
			entity["velocity"] = (target - entity["position"]).limit_length(speed)
			if distance < float(config["hostile_detect_m"]):
				_set_mode(entity, "follow")
		"follow":
			entity["velocity"] = to_own.normalized() * speed
			if entity["mode_t"] > float(config["hostile_give_up_s"]) or distance > float(config["hostile_detect_m"]) * 1.6:
				_set_mode(entity, "break_off")
		"break_off":
			entity["velocity"] = ((entity["anchor"] as Vector3) - entity["position"]).limit_length(speed)
			if entity["mode_t"] > float(config["hostile_break_off_s"]):
				_set_mode(entity, "patrol")
	entity["position"] += entity["velocity"] * dt
	if entity["mode"] == "follow" and (entity["position"] as Vector3).distance_to(own) <= float(config["hit_radius"]) + 1.0:
		_log("hit", {"by": entity["id"], "kind": "hostile_drone"})
		_set_mode(entity, "break_off")
		return float(config["damage"])
	return 0.0


func _set_mode(entity: Dictionary, mode: String) -> void:
	entity["mode"] = mode
	entity["mode_t"] = 0.0
	_log("hostile_" + mode, {"id": entity["id"]})


func _projectile_step(entity: Dictionary, dt: float, own: Vector3) -> float:
	var from: Vector3 = entity["position"]
	var to: Vector3 = from + entity["velocity"] * dt
	entity["travelled"] = float(entity["travelled"]) + from.distance_to(to)
	# Closest approach to the trainee during this step (no tunnelling at high speed).
	var segment := to - from
	var t := clampf((own - from).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
	if (from + segment * t).distance_to(own) <= float(config["hit_radius"]):
		_retire(entity, "hit")
		_log("hit", {"by": entity["id"], "kind": "projectile"})
		return float(config["damage"])
	if blocker.is_valid() and blocker.call(from, to):
		_retire(entity, "struck a structure")
		return 0.0
	entity["position"] = to
	if to.y <= 0.0 or float(entity["travelled"]) >= float(config["projectile_max_distance"]):
		_retire(entity, "expired")
	return 0.0


func _fire(own: Vector3) -> void:
	for i in sites.size():
		if time_s < float(_site_timers[i]):
			continue
		var origin: Vector3 = sites[i] + Vector3(0, 2.0, 0)
		if origin.distance_to(own) > float(config["site_range_m"]) or own.y < 1.0:
			continue
		if blocker.is_valid() and blocker.call(origin, own):
			continue
		var cooldown: Array = config["cooldown_s"]
		_site_timers[i] = time_s + _rng.randf_range(cooldown[0], cooldown[1])
		var projectile := _spawn("projectile", origin, (own - origin).normalized() * float(config["projectile_speed"]), false, {"travelled": 0.0, "site": i})
		_log("launched", {"id": projectile["id"], "site": i})


func _retire(entity: Dictionary, reason: String) -> void:
	entity["active"] = false
	entity["retired_t"] = time_s
	_log("retired", {"id": entity["id"], "kind": entity["kind"], "reason": reason})


func active_entities() -> Array:
	return entities.filter(func(e): return e["active"])


func take_events() -> Array:
	var out := events
	events = []
	return out


func _log(type: String, data: Dictionary) -> void:
	events.append({"t": snappedf(time_s, 0.01), "type": type, "data": data})
