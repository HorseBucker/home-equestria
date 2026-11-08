extends RefCounted
## A short heavenly tune for the princesses' magic (dev 2026-11-07): Luna's moonbeam, and the set
## coming back down from the sun after Celestia flings it up (magic_quest.gd). Made here, not
## shipped as a sound file: a soft pad of slow major chords with a little vibrato, a rising
## arpeggio of bell notes over it, and an echo that gives it shimmer. About fifteen seconds. Built
## once per game on a worker thread (prepare(), when a princess takes a set) so it never hitches;
## play() gives the player that plays it, fading in, non-positional (like music).

const RATE := 22050
const SECONDS := 15.0
const CHORD_SECONDS := 3.0
const ATTACK := 1.0
const RELEASE := 1.4
## MIDI notes: Cmaj9, Am9, Fmaj7(9), G6/9, Cmaj with the third on top.
const CHORDS := [[60, 64, 67, 71, 74], [57, 60, 64, 67, 71], [53, 57, 60, 64, 69], [55, 59, 62, 67, 74], [60, 64, 67, 72, 76]]
const PAD := 0.07
const BELL := 0.055
const BELL_EVERY := 0.375
const ECHO := 0.31
const ECHO_GAIN := 0.38
const VOLUME_DB := -7.0
const FADE_IN := 1.0

static var _stream: AudioStreamWAV
static var _task := -1
static var _maker: RefCounted

static func prepare() -> void:
	if _stream != null or _task >= 0: return
	_maker = (load("res://mods/watch_party/heavenly.gd") as GDScript).new()
	_task = WorkerThreadPool.add_task(_maker._build)

## The tune, playing under `parent` (a node in the world). Null when it could not be made.
static func play(parent: Node) -> AudioStreamPlayer:
	if _stream == null: prepare()
	if _task >= 0:
		# Done long since, normally (prepare() ran when the quest began); collected either way.
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _stream == null or not is_instance_valid(parent): return null
	var player := AudioStreamPlayer.new()
	player.stream = _stream
	for bus: String in ["Music", "SFX", "Master"]:
		if AudioServer.get_bus_index(bus) >= 0:
			player.bus = bus
			break
	player.volume_db = -40.0
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	player.create_tween().tween_property(player, "volume_db", VOLUME_DB, FADE_IN)
	return player

func _build() -> void:
	var count := int(RATE * SECONDS)
	var out := PackedFloat32Array()
	out.resize(count)
	# The pad: each chord swells in, holds, and fades as the next comes.
	for index in CHORDS.size():
		var start := index * CHORD_SECONDS
		var length := CHORD_SECONDS + RELEASE
		var first := int(start * RATE)
		var last := mini(count, int((start + length) * RATE))
		for note: int in CHORDS[index]:
			var frequency := 440.0 * pow(2.0, (note - 69) / 12.0)
			for k in range(first, last):
				var t := float(k) / RATE - start
				var envelope := minf(1.0, t / ATTACK) * clampf((length - t) / RELEASE, 0.0, 1.0)
				var phase := TAU * frequency * t + 0.6 * sin(TAU * 4.6 * t)
				out[k] += PAD * envelope * (sin(phase) + 0.22 * sin(2.0 * phase))
	# Bells: up and down the chord, an octave or two above it.
	var step := 0
	var at := 0.4
	while at < SECONDS - 2.5:
		var chord: Array = CHORDS[mini(CHORDS.size() - 1, int(at / CHORD_SECONDS))]
		var pattern := [0, 1, 2, 3, 4, 3, 2, 1]
		var note: int = int(chord[pattern[step % pattern.size()]]) + (12 if step % 16 < 8 else 24)
		var frequency := 440.0 * pow(2.0, (note - 69) / 12.0)
		var first := int(at * RATE)
		var last := mini(count, first + int(2.2 * RATE))
		for k in range(first, last):
			var t := float(k - first) / RATE
			var envelope := exp(-2.8 * t) * minf(1.0, t / 0.004)
			out[k] += BELL * envelope * (sin(TAU * frequency * t) + 0.3 * sin(TAU * frequency * 2.76 * t) * exp(-4.0 * t))
		step += 1
		at += BELL_EVERY
	# The shimmer: a soft echo.
	var delay := int(ECHO * RATE)
	for k in range(delay, count):
		out[k] += ECHO_GAIN * out[k - delay]
	var peak := 0.0001
	for k in count: peak = maxf(peak, absf(out[k]))
	var gain := 0.85 / peak
	var data := PackedByteArray()
	data.resize(count * 2)
	var fade_from := count - int(2.0 * RATE)
	for k in count:
		var sample := out[k] * gain
		if k > fade_from: sample *= float(count - k) / float(count - fade_from)
		data.encode_s16(k * 2, int(clampf(sample, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	_stream = stream
