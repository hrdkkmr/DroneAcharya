extends Node
## Plays the short sound cues and the looping motor/ambience sounds for one screen.
## Each screen adds one (AudioCues.attach); it is freed with the screen, so changing
## scenes stops every sound. Cues go to the "SFX" bus, loops to "Ambience"; the
## volume settings and mute act on those buses (settings_store.gd).
##
## Rules that keep sound useful rather than irritating:
##  * every cue has a cooldown: the same cue never restarts within it;
##  * a small pool of players, so cues overlap at most a few at a time;
##  * loops pause with the game (their player is PAUSABLE) and the ambience is
##    reduced while a pause menu is open;
##  * every alarm cue has a visual equivalent on screen (CRITICAL_CUES), so nothing
##    depends on hearing it.

const SoundBank := preload("res://scripts/audio/sound_bank.gd")
const SettingsStore := preload("res://scripts/app/settings_store.gd")

const DEFAULT_COOLDOWN_S := 0.12
const COOLDOWN_S := {
	"contact_detected": 1.0, "contact_lost": 1.0, "timer_warning": 2.0, "incoming": 1.2, "sensor_alert": 3.0,
	"impact": 0.4, "bump": 0.6, "checkpoint": 0.3, "tutorial_step": 0.2,
}
## Cues that warn of something important, and the visual sign shown with them.
const CRITICAL_CUES := {
	"incoming": "INCOMING banner with direction and an edge arrow (flight HUD)",
	"timer_warning": "TIME LOW banner and amber clock (flight HUD)",
	"impact": "red screen flash, integrity value and message (flight HUD)",
	"sensor_alert": "SENSOR DEGRADED line in the status card (observation)",
	"confirm_needed": "confirmation text and Confirm / Cancel buttons (decision card)",
	"failure": "Mission failed / Exercise ended screen",
}
const POOL_SIZE := 6

## The most recently attached instance, for UI clicks from shared widgets.
static var active: Node

var history: Array = [] ## names of cues actually started (for tests)
var loops := {} ## name -> AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {} ## cue -> msec


## Creates the cue player for a screen (call from the screen's _ready).
static func attach(parent: Node) -> Node:
	var cues: Node = load("res://scripts/audio/audio_cues.gd").new()
	cues.name = "AudioCues"
	parent.add_child(cues)
	return cues


## Plays a cue on the active screen, if there is one (used by shared UI widgets).
static func play_global(cue: String) -> void:
	if active != null and is_instance_valid(active) and active.is_inside_tree():
		active.play(cue)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SettingsStore.ensure_buses()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_pool.append(player)
	active = self


func _exit_tree() -> void:
	if active == self:
		active = null
	stop_all()


## Starts `cue` unless it played within its cooldown. Returns true when started.
func play(cue: String) -> bool:
	if not SoundBank.CUES.has(cue):
		return false
	var now := Time.get_ticks_msec()
	var cooldown := int(float(COOLDOWN_S.get(cue, DEFAULT_COOLDOWN_S)) * 1000.0)
	if _last_played.has(cue) and now - int(_last_played[cue]) < cooldown:
		return false
	_last_played[cue] = now
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = SoundBank.get_stream(cue)
	player.play()
	history.append(cue)
	return true


## Starts (or keeps) a looping sound. Loops are PAUSABLE so they stop with the game.
func start_loop(name: String, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = loops.get(name)
	if player == null:
		player = AudioStreamPlayer.new()
		player.bus = "Ambience"
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		player.stream = SoundBank.get_stream(name)
		add_child(player)
		loops[name] = player
	player.volume_db = volume_db
	player.pitch_scale = pitch
	if not player.playing:
		player.play()
	return player


func set_loop(name: String, volume_db: float, pitch: float) -> void:
	var player: AudioStreamPlayer = loops.get(name)
	if player:
		player.volume_db = volume_db
		player.pitch_scale = clampf(pitch, 0.5, 2.0)


func stop_loop(name: String) -> void:
	var player: AudioStreamPlayer = loops.get(name)
	if player:
		player.stop()


## Lowers the ambience while a pause menu is open; restores it afterwards.
func set_paused_mix(paused: bool) -> void:
	for name in loops:
		var player: AudioStreamPlayer = loops[name]
		player.stream_paused = paused


func stop_all() -> void:
	for player in _pool:
		if is_instance_valid(player):
			player.stop()
	for name in loops:
		if is_instance_valid(loops[name]):
			loops[name].stop()


## Number of players currently producing sound (for tests).
func playing_count() -> int:
	var count := 0
	for player in _pool:
		count += int(player.playing)
	for name in loops:
		count += int(loops[name].playing and not loops[name].stream_paused)
	return count
