extends RefCounted
## The sounds of Celestia flinging a set up to the sun (magic_quest.gd _sun), made here rather than
## shipped as files: the whoosh of the throw, a thin whistle as it climbs, the twinkle when it
## vanishes into the sun, the meteor's roar as it falls (a far rumble swelling to a roar, a falling
## whistle and crackle), the thump and zing of her magic catching it, the hiss as the flames go out
## and a soft tink as it touches down. Built once per game on a worker thread (prepare(), when she
## takes a set); play() puts one at a place in the world, or follows a node.

const RATE := 22050
const NAMES := ["whoosh", "climb", "twinkle", "meteor", "catch", "hiss", "tink"]
## The meteor's sound lasts as long as the fall (magic_quest.gd SUN_FALL).
const METEOR_SECONDS := 3.6

static var _streams: Dictionary = {}
static var _task := -1
static var _maker: RefCounted

static func prepare() -> void:
	if not _streams.is_empty() or _task >= 0: return
	_maker = (load("res://mods/watch_party/sky_sfx.gd") as GDScript).new()
	_task = WorkerThreadPool.add_task(_maker._build)

static func _ready_now() -> void:
	if _streams.is_empty(): prepare()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

## The sound `name`, under `parent` (it follows it), heard from `reach` metres. Null when not made.
static func play(name: String, parent: Node3D, volume_db := 0.0, reach := 40.0) -> AudioStreamPlayer3D:
	_ready_now()
	if not _streams.has(name) or not is_instance_valid(parent): return null
	var player := AudioStreamPlayer3D.new()
	player.stream = _streams[name]
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	player.unit_size = reach
	player.max_distance = reach * 25.0
	player.volume_db = volume_db
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player

## The same, heard as if everywhere (the twinkle, far up in the sky).
static func play_flat(name: String, parent: Node, volume_db := 0.0) -> AudioStreamPlayer:
	_ready_now()
	if not _streams.has(name) or not is_instance_valid(parent): return null
	var player := AudioStreamPlayer.new()
	player.stream = _streams[name]
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	player.volume_db = volume_db
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player

func _build() -> void:
	var made := {}
	made.whoosh = _wav(_whoosh())
	made.climb = _wav(_climb())
	made.twinkle = _wav(_twinkle())
	made.meteor = _wav(_meteor())
	made.catch = _wav(_catch())
	made.hiss = _wav(_hiss())
	made.tink = _wav(_tink())
	_streams = made

# --- the sounds ---------------------------------------------------------------------------------

func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(RATE * seconds))
	return out

## The throw: a band of rushing noise that swells fast and falls away, rising in pitch.
func _whoosh() -> PackedFloat32Array:
	var out := _buffer(0.9)
	var low := 0.0
	var lower := 0.0
	for k in out.size():
		var t := float(k) / RATE
		var bright := lerpf(0.08, 0.45, clampf(t / 0.3, 0.0, 1.0))
		low += (randf_range(-1.0, 1.0) - low) * bright
		lower += (low - lower) * 0.05
		var envelope := minf(1.0, t / 0.06) * exp(-4.5 * maxf(0.0, t - 0.06))
		out[k] = (low - lower) * envelope * 1.6
	return out

## Climbing away: a thin whistle rising and fading into the distance.
func _climb() -> PackedFloat32Array:
	var out := _buffer(2.8)
	var phase := 0.0
	for k in out.size():
		var t := float(k) / RATE
		var frequency := lerpf(900.0, 2600.0, t / 2.8)
		phase += TAU * frequency / RATE
		out[k] = sin(phase) * 0.18 * minf(1.0, t / 0.1) * pow(1.0 - t / 2.8, 2.0)
	return out

## The twinkle: a quick bright arpeggio of high bells with a long shimmering tail.
func _twinkle() -> PackedFloat32Array:
	var out := _buffer(2.2)
	var notes := [2093.0, 2637.0, 3136.0, 4186.0, 5274.0]
	for index in notes.size():
		var start := int(index * 0.055 * RATE)
		var frequency: float = notes[index]
		for k in range(start, out.size()):
			var t := float(k - start) / RATE
			var envelope := exp(-3.2 * t) * minf(1.0, t / 0.002)
			out[k] += 0.16 * envelope * (sin(TAU * frequency * t) + 0.25 * sin(TAU * frequency * 2.01 * t) * exp(-6.0 * t))
	return out

## The fall: a far rumble that swells to a roar, a whistle dropping in pitch as it comes, and
## crackling fire, all getting louder to the end.
func _meteor() -> PackedFloat32Array:
	var out := _buffer(METEOR_SECONDS)
	var low := 0.0
	var lower := 0.0
	var phase := 0.0
	var crackle := 0.0
	for k in out.size():
		var t := float(k) / RATE
		var near := t / METEOR_SECONDS
		var swell := pow(near, 1.6)
		low += (randf_range(-1.0, 1.0) - low) * lerpf(0.04, 0.3, swell)
		lower += (low - lower) * 0.08
		var roar := (low * 0.6 + lower * 2.5) * lerpf(0.08, 1.0, swell)
		var frequency := lerpf(1900.0, 420.0, near * near)
		phase += TAU * frequency / RATE
		var whistle := sin(phase) * 0.22 * minf(1.0, near * 3.0) * (1.0 - 0.5 * swell)
		if randf() < lerpf(0.0005, 0.012, swell): crackle = randf_range(0.4, 1.0)
		crackle *= 0.86
		out[k] = roar + whistle + crackle * randf_range(-1.0, 1.0) * 0.5 * swell
	return out

## Her magic catching it: a deep thump and a rising zing.
func _catch() -> PackedFloat32Array:
	var out := _buffer(1.0)
	var phase := 0.0
	for k in out.size():
		var t := float(k) / RATE
		var thump := sin(TAU * (70.0 - 30.0 * t) * t) * exp(-9.0 * t) * 0.9
		var click := randf_range(-1.0, 1.0) * exp(-60.0 * t) * 0.4
		phase += TAU * lerpf(380.0, 1500.0, minf(1.0, t / 0.5)) / RATE
		var zing := sin(phase) * 0.22 * minf(1.0, t / 0.03) * exp(-3.5 * t)
		out[k] = thump + click + zing
	return out

## The flames put out: a hiss of steam, falling away.
func _hiss() -> PackedFloat32Array:
	var out := _buffer(1.6)
	var last := 0.0
	for k in out.size():
		var t := float(k) / RATE
		var noise := randf_range(-1.0, 1.0)
		var high := noise - last
		last = noise
		out[k] = high * 0.35 * minf(1.0, t / 0.02) * exp(-2.2 * t)
	return out

## Touching down: a small bright tink.
func _tink() -> PackedFloat32Array:
	var out := _buffer(0.5)
	for k in out.size():
		var t := float(k) / RATE
		out[k] = (sin(TAU * 2600.0 * t) + 0.4 * sin(TAU * 3900.0 * t)) * 0.2 * exp(-11.0 * t)
	return out

static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for value in samples: peak = maxf(peak, absf(value))
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for k in samples.size():
		data.encode_s16(k * 2, int(clampf(samples[k] * gain, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
