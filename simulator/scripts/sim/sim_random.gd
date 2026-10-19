extends RefCounted
## Deterministic seeding helpers. Every random stream in the threat simulation is
## derived from the scenario seed plus a label, so adding a new stream never shifts
## the numbers drawn by an existing one.

const MASK32 := 0xFFFFFFFF


## FNV-1a over the UTF-8 bytes of `text`, as an unsigned 32-bit integer.
static func hash32(text: String) -> int:
	var value := 2166136261
	for byte in text.to_utf8_buffer():
		value = ((value ^ byte) * 16777619) & MASK32
	return value


## Independent generator for one named stream of a scenario.
static func stream(scenario_seed: int, label: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash32("%d|%s" % [scenario_seed, label])
	return rng


static func range_between(rng: RandomNumberGenerator, bounds: Array) -> float:
	return rng.randf_range(float(bounds[0]), float(bounds[1]))
