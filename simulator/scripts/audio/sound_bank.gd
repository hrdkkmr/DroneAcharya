extends RefCounted
## Procedurally generated sound cues (no audio files, so no third-party assets or
## licences). Each cue is a short envelope of sine / square / noise partials rendered
## once to a 16-bit mono AudioStreamWAV and cached for the rest of the run.
## Loops (rotor, wind) are rendered with a whole number of cycles so they repeat
## without clicks.

const RATE := 22050

## Cue recipes: list of segments {start, length, freq, to (end freq), wave, gain}.
## wave: "sine", "square" (softened), "noise", "thump" (decaying low sine).
const CUES := {
	"ui_click": [{"start": 0.0, "length": 0.045, "freq": 1250.0, "wave": "sine", "gain": 0.35}],
	"ui_back": [{"start": 0.0, "length": 0.05, "freq": 800.0, "wave": "sine", "gain": 0.3}],
	"mission_start": [{"start": 0.0, "length": 0.12, "freq": 600.0, "wave": "sine", "gain": 0.45},
		{"start": 0.12, "length": 0.18, "freq": 900.0, "wave": "sine", "gain": 0.45}],
	"takeoff": [{"start": 0.0, "length": 0.35, "freq": 300.0, "to": 520.0, "wave": "sine", "gain": 0.35}],
	"checkpoint": [{"start": 0.0, "length": 0.35, "freq": 880.0, "wave": "sine", "gain": 0.4},
		{"start": 0.0, "length": 0.35, "freq": 1320.0, "wave": "sine", "gain": 0.2}],
	"timer_warning": [{"start": 0.0, "length": 0.1, "freq": 1000.0, "wave": "square", "gain": 0.3},
		{"start": 0.18, "length": 0.1, "freq": 1000.0, "wave": "square", "gain": 0.3}],
	"contact_detected": [{"start": 0.0, "length": 0.16, "freq": 1400.0, "wave": "sine", "gain": 0.3}],
	"contact_lost": [{"start": 0.0, "length": 0.22, "freq": 800.0, "to": 480.0, "wave": "sine", "gain": 0.28}],
	"decision_confirmed": [{"start": 0.0, "length": 0.08, "freq": 700.0, "wave": "sine", "gain": 0.4},
		{"start": 0.08, "length": 0.1, "freq": 1050.0, "wave": "sine", "gain": 0.4}],
	"decision_rejected": [{"start": 0.0, "length": 0.16, "freq": 220.0, "wave": "square", "gain": 0.25}],
	"confirm_needed": [{"start": 0.0, "length": 0.12, "freq": 660.0, "wave": "square", "gain": 0.22},
		{"start": 0.14, "length": 0.12, "freq": 660.0, "wave": "square", "gain": 0.22}],
	"sensor_alert": [{"start": 0.0, "length": 0.25, "freq": 520.0, "to": 380.0, "wave": "square", "gain": 0.22}],
	"incoming": [{"start": 0.0, "length": 0.06, "freq": 1800.0, "wave": "square", "gain": 0.3},
		{"start": 0.1, "length": 0.06, "freq": 1800.0, "wave": "square", "gain": 0.3},
		{"start": 0.2, "length": 0.06, "freq": 1800.0, "wave": "square", "gain": 0.3}],
	"impact": [{"start": 0.0, "length": 0.28, "freq": 70.0, "wave": "thump", "gain": 0.7},
		{"start": 0.0, "length": 0.18, "freq": 0.0, "wave": "noise", "gain": 0.35}],
	"bump": [{"start": 0.0, "length": 0.12, "freq": 110.0, "wave": "thump", "gain": 0.5},
		{"start": 0.0, "length": 0.06, "freq": 0.0, "wave": "noise", "gain": 0.15}],
	"success": [{"start": 0.0, "length": 0.15, "freq": 523.0, "wave": "sine", "gain": 0.4},
		{"start": 0.15, "length": 0.15, "freq": 659.0, "wave": "sine", "gain": 0.4},
		{"start": 0.3, "length": 0.3, "freq": 784.0, "wave": "sine", "gain": 0.4}],
	"failure": [{"start": 0.0, "length": 0.18, "freq": 392.0, "wave": "square", "gain": 0.22},
		{"start": 0.18, "length": 0.18, "freq": 330.0, "wave": "square", "gain": 0.22},
		{"start": 0.36, "length": 0.3, "freq": 262.0, "wave": "square", "gain": 0.22}],
	"tutorial_step": [{"start": 0.0, "length": 0.22, "freq": 988.0, "wave": "sine", "gain": 0.25},
		{"start": 0.0, "length": 0.22, "freq": 1480.0, "wave": "sine", "gain": 0.1}],
}

static var _cache := {}


static func has(cue: String) -> bool:
	return CUES.has(cue) or cue in ["rotor", "wind"]


static func get_stream(cue: String) -> AudioStreamWAV:
	if _cache.has(cue):
		return _cache[cue]
	var stream: AudioStreamWAV
	match cue:
		"rotor":
			stream = _rotor_loop()
		"wind":
			stream = _wind_loop()
		_:
			stream = _render(CUES[cue])
	_cache[cue] = stream
	return stream


static func _render(segments: Array) -> AudioStreamWAV:
	var length := 0.0
	for seg in segments:
		length = maxf(length, float(seg["start"]) + float(seg["length"]))
	var count := int(length * RATE) + 64
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for seg in segments:
		var start := int(float(seg["start"]) * RATE)
		var n := int(float(seg["length"]) * RATE)
		var f0: float = seg["freq"]
		var f1: float = seg.get("to", f0)
		var phase := 0.0
		for i in n:
			var t := float(i) / n
			var freq := lerpf(f0, f1, t)
			phase += TAU * freq / RATE
			var attack := minf(float(i) / (0.005 * RATE), 1.0)
			var envelope := attack * pow(1.0 - t, 1.6)
			var value := 0.0
			match seg["wave"]:
				"sine":
					value = sin(phase)
				"square":
					value = clampf(sin(phase) * 3.0, -1.0, 1.0) * 0.7
				"noise":
					value = rng.randf_range(-1.0, 1.0)
				"thump":
					value = sin(phase) * pow(1.0 - t, 3.0)
			samples[start + i] += value * envelope * float(seg["gain"])
	return _to_wav(samples, false)


## Rotor: blade-pass tone with harmonics and a little noise, 1 s, 110 whole cycles.
static func _rotor_loop() -> AudioStreamWAV:
	var count := RATE
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var noise := 0.0
	for i in count:
		var phase := TAU * 110.0 * i / RATE
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.15)
		samples[i] = 0.28 * sin(phase) + 0.14 * sin(phase * 2.0) + 0.08 * sin(phase * 3.0) + 0.06 * noise
	return _to_wav(samples, true)


## Wind: low-passed noise with a slow swell, 2 s.
static func _wind_loop() -> AudioStreamWAV:
	var count := RATE * 2
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var value := 0.0
	for i in count:
		value = lerpf(value, rng.randf_range(-1.0, 1.0), 0.02)
		samples[i] = value * (0.6 + 0.4 * sin(TAU * float(i) / count)) * 1.6
	return _to_wav(samples, true)


static func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
