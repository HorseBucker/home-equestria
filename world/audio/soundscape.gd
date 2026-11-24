extends Node3D
## Ponyville soundscape (dev 2026-11-10: "a soundscape, fuck, a soundscape"). A child of the
## Ambience node (world/ambience.gd), which keeps wind, the forest bed, crickets, birds and steps.
## This adds the sounds of a place somebody lives in, and puts each one where its source is, so
## it comes from a direction and fades with distance (the headset hears it in space):
##   fountain on the plaza (silent while iced over) · the windmill · chickens at the barn and at
##   Fluttershy's cottage · wind chimes at the cottage and the boutique on a breezy day ·
##   a hearth at the nearest lit house ·
##   frogs at the nearest water on warm nights · a soft brook along the nearest rivers · an owl in a nearby tree at night ·
##   the town bell on the hour · a rooster at dawn · a distant train now and then ·
##   a storm wind in a blizzard or gale · bees over the meadows and cicadas on hot afternoons ·
##   drips while snow thaws · sparrows in the town's trees by day · sleigh bells far off in winter.
## Falling snow and lying snow hush everything distant (snow soaks sound up): less reach, a little quieter.
## A recording of the square at summer noon measured as silence (2026-11-10, tools/look/
## baseline_shots.gd --record-sound): every placed source was out of reach and the town had no
## day sound of its own. The sparrows are that sound; they sit in real trees, so they have a place.
## Recorded samples only (CC0 field recordings; tools/audio/build_soundscape.py in the private
## root cut them; sources in the private archive). Every file is a placeholder dev may swap:
## replace the .ogg under world/audio/soundscape/ and keep its name.
##
## Cost: a 2 Hz decision step and a volume fade per frame over about twenty players; a player
## whose layer is silent is stopped. No physics queries of its own (water and tree lookups reuse
## the Ambience node's, at most once every few seconds).
## Rollback: ENABLED = false, or Settings > Audio is unaffected and no file is touched.

const ENABLED := true
const DIR := "res://world/audio/soundscape/"
const GLOW := preload("res://world/buildings/window_glow/window_glow.gd")
const TOWN := Vector3(135.5, 0.0, -175.89)
const STEP := 0.5
const SILENT := -60.0

## Placed loops: name -> [file, world x, world z, volume dB, unit size, max distance].
## The fountain's row position is only a placeholder: it plays at the Town Square fountain's water
## (world/water/fountain_water.gd sound_point, found at run time since a town build may move it) and
## is silent until that is found. Play test 2026-11-16 ("this water should be much quieter, or make
## no sound, since it's not flowing like the rivers"): 10 dB down from -9 and a short reach (unit 5 -> 2,
## gone by 14 m instead of 55), so it is only just heard beside the basin.
const PLACED := {
	"fountain": ["fountain", 114.0, -189.4, -19.0, 2.0, 14.0],
	# (Ponyville overhaul, 2026-11-23 player report: "The windmill soundscape is still where the old windmill location
	# was": at each of the remade town's windmills, and the hens and chimes moved with the barn, Fluttershy's cottage
	# and the Carousel Boutique, at the same spot beside each as before)
	"windmill": ["windmill", 310.0, -200.8, -10.0, 7.0, 70.0],
	"windmill_2": ["windmill", -8.4, -77.5, -10.0, 7.0, 70.0],
	"chickens_barn": ["chickens", -15.5, 51.4, -13.0, 5.0, 45.0],
	"chickens_cottage": ["chickens", 417.1, 0.2, -15.0, 5.0, 40.0],
	"chimes_cottage": ["chimes", 407.9, 1.1, -14.0, 4.0, 35.0],
	"chimes_boutique": ["chimes", 106.0, -96.0, -15.0, 4.0, 35.0],
}
## Beds that are not at a place: name -> [file, volume dB].
const BEDS := {
	"storm_wind": ["wind_howl", -17.0],
	"snow_wind": ["winter_wind", -22.0],
	"bees": ["meadow_bees", -24.0],
	"cicadas": ["cicadas", -27.0],
}
## No bed plays inside a home (dev 2026-11-11: a clock ticked in the Mayor's house with no clock
## in the room, a fire crackled over empty hearths). A room sound needs a thing in the room that
## makes it, placed at that thing; until then a room is quiet.
const BELL_AT := Vector3(135.5, 0.0, -175.89)
const ROOSTER_AT := Vector3(-27.4, 0.0, 51.52)
const TRAIN_AT := Vector3(-700.0, 0.0, -330.0)
## Sparrow groups: how far one is heard, and the least distance between two groups (metres).
const SPARROW_REACH := 48.0
const SPARROW_APART := 9.0
## The brook (2026-11-15, "quiet, subtle water-flow sound"): three voices of one synthesised loop
## (tools/town_planner/build/make_stream_sound.py) glide to the nearest stretches of the rivers
## (WorldWater.flow_streams, from world/water/ponyville_flow.json) within STREAM_NEAR metres of the
## listener, at least STREAM_APART apart. Small sources: heard close, gone by STREAM_REACH.
const STREAM_VOICES := 3
## Third play test (2026-11-16): "only audible if you're standing in it". The first voices (unit 2.8 m,
## -22 dB, gone by 22 m) were 11 dB down at 10 m from the bank. Now a wider source: full level out
## to 6 m, about 5 dB down at 10 m and 12 dB at 20 m, never louder than its level when one stands in it.
const STREAM_NEAR := 42.0
const STREAM_APART := 14.0
const STREAM_REACH := 40.0
const STREAM_UNIT := 6.0
## Play test 2026-11-16 ("decrease the volume of water just a bit"): 3 dB down from -17, same reach.
## The loop was resynthesised the same day without its bubbles, at the same RMS.
const STREAM_DB := -20.0
## How far over its level a brook voice may rise close up (the bank at 4 m is 3.5 dB over; a bridge deck 2 m
## above the water was 9.5 dB over, and three voices can be that near at a confluence).
const STREAM_NEAR_GAIN_DB := 3.0

var _ambience: Node3D
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _settled := false
var _loops: Dictionary = {}      # name -> player (AudioStreamPlayer or AudioStreamPlayer3D)
var _targets: Dictionary = {}    # name -> target dB
var _levels: Dictionary = {}     # name -> current dB
var _base: Dictionary = {}       # name -> full volume dB
var _shots: Dictionary = {}      # name -> AudioStreamPlayer3D
var _hearth: AudioStreamPlayer3D
var _frogs: AudioStreamPlayer3D
var _sparrows: Array = []        # AudioStreamPlayer3D, one per group
var _streams: Array[AudioStreamPlayer3D] = []   # brook voices; meta "spot" = where each is gliding to
var _sleigh_wait := 240.0
var _seek_wait := 0.0
var _owl_wait := 40.0
var _train_wait := 240.0
var _drip_wait := 8.0
var _last_hour := -1
var _weather: Node
var _seasons: Node
var _fountain: Node3D


func _ready() -> void:
	_ambience = get_parent() as Node3D
	if not ENABLED or _ambience == null:
		set_process(false)
		return
	_rng.randomize()
	var bus := "WorldAmbience" if AudioServer.get_bus_index("WorldAmbience") >= 0 else ("Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master")
	for name: String in PLACED:
		var row: Array = PLACED[name]
		var placed := _spatial(str(row[0]), true, bus, float(row[4]), float(row[5]))
		if placed == null: continue
		placed.position = Vector3(float(row[1]), 0.0, float(row[2]))
		_register(name, placed, float(row[3]))
	for name: String in BEDS:
		var row: Array = BEDS[name]
		var stream := _stream(str(row[0]), true)
		if stream == null: continue
		var bed := AudioStreamPlayer.new()
		bed.bus = bus; bed.stream = stream; bed.volume_db = SILENT
		add_child(bed)
		_register(name, bed, float(row[1]))
	_hearth = _spatial("hearth", true, bus, 3.0, 22.0)
	if _hearth != null: _register("hearth", _hearth, -10.0)
	_frogs = _spatial("frogs", true, bus, 6.0, 60.0)
	if _frogs != null: _register("frogs", _frogs, -15.0)
	for index: int in 2:
		var group := _spatial("town_birds", true, bus, 7.0, SPARROW_REACH)
		if group == null: continue
		# Two cuts of one recording must not sound like one: different pitch, different start.
		group.pitch_scale = 0.96 if index == 0 else 1.05
		_sparrows.append(group)
		# -17 dB measured 7 dB under the night's crickets on a recording of the square; a town at
		# noon is at least as present as a field at night.
		_register("sparrows_%d" % index, group, -12.0 - 2.0 * index)
	for index: int in STREAM_VOICES:
		var voice := _spatial("stream", true, bus, STREAM_UNIT, STREAM_REACH)
		if voice == null: continue
		# Never louder than its own level (play test 2026-11-16: "too loud when going over it on a bridge"). The
		# engine's cap, max_db, is on the level after distance: at 0 dB it let a voice 2 m under a bridge play
		# 9 dB over its level (inverse distance: unit 6 m / 2 m). _process keeps the cap STREAM_NEAR_GAIN_DB over the
		# voice's level: flat from about 4 m inward; beyond that nothing changes.
		voice.set_meta("flat_near", true)
		voice.max_db = SILENT
		# One loop three times over must not sound like one: its own pitch and its own place in the loop.
		voice.pitch_scale = [0.95, 1.03, 1.1][index % 3]
		voice.set_meta("spread_start", true)
		_streams.append(voice)
		_register("stream_%d" % index, voice, STREAM_DB - 1.0 * index)
	for name: String in ["owl", "bell", "rooster", "train_distant", "train_whistle", "droplets", "sleigh_bells"]:
		var shot := _spatial(name, false, bus, 12.0, 400.0)
		if shot != null: _shots[name] = shot
	_owl_wait = _rng.randf_range(30.0, 90.0)
	_train_wait = _rng.randf_range(150.0, 420.0)
	_sleigh_wait = _rng.randf_range(120.0, 400.0)


func _stream(file: String, looped: bool) -> AudioStream:
	var path := DIR + file + ".ogg"
	if not ResourceLoader.exists(path): return null
	var stream := (load(path) as AudioStream).duplicate() as AudioStream
	if stream is AudioStreamOggVorbis: (stream as AudioStreamOggVorbis).loop = looped
	return stream


func _spatial(file: String, looped: bool, bus: String, unit: float, reach: float) -> AudioStreamPlayer3D:
	var stream := _stream(file, looped)
	if stream == null: return null
	var player := AudioStreamPlayer3D.new()
	player.bus = bus; player.stream = stream
	player.unit_size = unit; player.max_distance = reach
	# No distance filter. The engine's one is a treble cut whose depth follows the player's whole
	# attenuation, volume_db included: a source set to -15 dB lost about 20 dB of treble at any
	# range. Measured on a recording beside the boutique's chimes (2026-11-10): the chimes, all
	# treble, were gone. 20500 Hz and above switches the filter off.
	player.attenuation_filter_cutoff_hz = 20500.0
	player.volume_db = SILENT if looped else 0.0
	add_child(player)
	return player


func _register(name: String, player: Node, db: float) -> void:
	_loops[name] = player; _base[name] = db; _targets[name] = SILENT; _levels[name] = SILENT


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = STEP
		_decide()
		# The targets may have moved; one pass also restarts a loop that stopped on its own.
		_settled = false
	# Brook voices glide toward their spots (a few metres a second; a jump would be heard as one).
	for voice: AudioStreamPlayer3D in _streams:
		if not voice.has_meta("spot"): continue
		var spot: Vector3 = voice.get_meta("spot")
		if voice.global_position.distance_squared_to(spot) > 0.01:
			voice.global_position = voice.global_position.lerp(spot, 1.0 - exp(-delta * 1.2))
	# Every loop sits at its target: nothing to fade until the next decision.
	if _settled: return
	_settled = true
	# Fade toward the targets; a silent loop is stopped so it costs nothing.
	for name: String in _loops:
		var player: Node = _loops[name]
		var target: float = _targets[name]
		var level: float = move_toward(float(_levels[name]), target, delta * 24.0)
		if not is_equal_approx(level, target): _settled = false
		if is_equal_approx(level, float(_levels[name])) and level <= SILENT + 0.01:
			continue
		_levels[name] = level
		var playing: bool = player.get("playing")
		if level <= SILENT + 0.01:
			if playing: player.call("stop")
			continue
		if not playing:
			var stream: AudioStream = player.get("stream")
			var spread := player.has_meta("spread_start") and stream != null and stream.get_length() > 1.0
			player.call("play", _rng.randf() * (stream.get_length() - 0.5 if spread else 4.0))
		player.set("volume_db", level)
		if player.has_meta("flat_near"): player.set("max_db", level + STREAM_NEAR_GAIN_DB)


func _listener() -> Node3D:
	var node: Variant = _ambience.get("listener")
	return node as Node3D if is_instance_valid(node) else null


func _ground(at: Vector3) -> Vector3:
	if is_instance_valid(WorldTerrain.instance):
		var h: float = WorldTerrain.instance.height_at(at)
		if is_finite(h): at.y = h + 2.0
	return at


func _want(name: String, amount: float) -> void:
	if not _loops.has(name): return
	_targets[name] = float(_base[name]) + linear_to_db(clampf(amount, 0.0001, 1.0)) if amount > 0.01 else SILENT
	_settled = false


## The 2 Hz step: what should be heard, how loud, and where the moving sources stand.
func _decide() -> void:
	var listener := _listener()
	if listener == null or not listener.global_position.is_finite(): return
	var at := listener.global_position
	var tree := get_tree()
	if not is_instance_valid(_weather): _weather = tree.get_first_node_in_group("weather")
	if not is_instance_valid(_seasons): _seasons = tree.get_first_node_in_group("season_state")
	var clock: Node = get_node_or_null("/root/TimeOfDay")
	var hours: float = float(clock.get("hours")) if clock != null else 12.0
	var daylight: float = float(clock.call("daylight")) if clock != null else 1.0
	var season: String = str(_seasons.call("season")) if is_instance_valid(_seasons) else "summer"
	var cover: float = float(_seasons.call("snow_cover")) if is_instance_valid(_seasons) else 0.0
	var ice: float = float(_seasons.call("ice")) if is_instance_valid(_seasons) else 0.0
	var params: Dictionary = _weather.get("params") if is_instance_valid(_weather) and _weather.get("params") is Dictionary else {}
	var rain := float(params.get("rain", 0.0)); var snow := float(params.get("snow", 0.0))
	var gust := float(params.get("gust", 0.0))
	var outdoor: float = float(_ambience.get("outdoor_gain"))
	var room: Variant = _ambience.get("room")
	var indoors := is_instance_valid(room)
	var warm := season == "spring" or season == "summer"
	var dry := rain < 0.05 and snow < 0.05
	var night := 1.0 - daylight
	var far_from_town := clampf((Vector2(at.x - TOWN.x, at.z - TOWN.z).length() - 110.0) / 90.0, 0.0, 1.0)
	# Snow in the air and on the ground soaks sound up over distance: a placed source carries
	# seven tenths as far and is up to 4 dB quieter. (A first version only turned sources down,
	# 9 dB even for a fountain eight metres away; measured on a recording, 2026-11-10.)
	# Near sounds (hearth, drips) are not hushed.
	var muffle := clampf(0.6 * snow + 0.4 * smoothstep(0.3, 0.8, cover), 0.0, 1.0)
	var hush := lerpf(1.0, 0.63, muffle)

	# Placed loops. Heights follow the ground once it is loaded.
	for name: String in PLACED:
		var placed := _loops.get(name) as AudioStreamPlayer3D
		if placed == null: continue
		if placed.position.y == 0.0: placed.position = _ground(placed.position)
		placed.max_distance = float((PLACED[name] as Array)[5]) * lerpf(1.0, 0.7, muffle)
	_want("fountain", outdoor * hush * (1.0 - smoothstep(0.3, 0.7, ice)) * (1.0 if _place_fountain() else 0.0))
	var turning := outdoor * hush * clampf(0.35 + gust, 0.0, 1.0)
	_want("windmill", turning); _want("windmill_2", turning)
	var hens := outdoor * hush * smoothstep(0.25, 0.6, daylight) * (1.0 if dry else 0.0) * (0.6 if season == "winter" else 1.0)
	_want("chickens_barn", hens); _want("chickens_cottage", hens)
	var breeze := outdoor * hush * smoothstep(0.08, 0.5, gust)
	_want("chimes_cottage", breeze); _want("chimes_boutique", breeze)
	# The brook: like the fountain, silent under ice and turned down indoors; a voice with no river
	# stretch near the listener is silent.
	_place_streams(at)
	var running := outdoor * hush * (1.0 - smoothstep(0.3, 0.7, ice))
	for index: int in _streams.size():
		var voice := _streams[index]
		voice.max_distance = STREAM_REACH * lerpf(1.0, 0.7, muffle)
		_want("stream_%d" % index, running if voice.has_meta("spot") else 0.0)

	# Beds.
	_want("storm_wind", outdoor * smoothstep(0.55, 1.0, gust))
	_want("snow_wind", outdoor * snow * (1.0 - smoothstep(0.55, 1.0, gust)) * 0.8)
	_want("bees", outdoor * far_from_town * daylight * (1.0 if warm and dry else 0.0) * (1.0 - gust))
	var heat := smoothstep(12.5, 14.5, hours) * (1.0 - smoothstep(17.0, 18.5, hours))
	_want("cicadas", outdoor * heat * (1.0 if season == "summer" and dry else 0.0))

	# Sources that move: the nearest lit house's hearth, frogs at the nearest water.
	_seek_wait -= STEP
	if _seek_wait <= 0.0:
		_seek_wait = 3.0
		_place_hearth(at, indoors)
		_place_frogs(at)
		_place_sparrows(at)
	# Sparrows: by day, in the dry, in town. Fewer in autumn, one thin group in winter, none in a gale.
	var chatter := outdoor * hush * (1.0 - far_from_town) * smoothstep(0.2, 0.5, daylight) * (1.0 if rain < 0.05 else 0.0) \
		* (1.0 - smoothstep(0.2, 0.7, snow)) * (1.0 - smoothstep(0.5, 0.9, gust))
	for index: int in _sparrows.size():
		var group := _sparrows[index] as AudioStreamPlayer3D
		var share := (0.45 if index == 0 else 0.0) if season == "winter" else (0.75 if season == "autumn" else 1.0)
		_want("sparrows_%d" % index, chatter * share if group.has_meta("perch") else 0.0)
	var cold_evening := season == "winter" or season == "autumn" or night > 0.4
	_want("hearth", (0.0 if indoors else 1.0) * (1.0 if _hearth != null and _hearth.has_meta("lit") and cold_evening else 0.0))
	_want("frogs", outdoor * smoothstep(0.5, 0.9, night) * (1.0 if warm and snow < 0.05 and _frogs != null and _frogs.has_meta("water") else 0.0))

	# One-shots.
	if outdoor > 0.3 and night > 0.8 and dry:
		_owl_wait -= STEP
		if _owl_wait <= 0.0:
			_owl_wait = _rng.randf_range(45.0, 140.0)
			var perch: Dictionary = _ambience.call("_tree_perch", at, 20.0, 60.0)
			if not perch.is_empty(): _shot("owl", perch.position, -8.0, _rng.randf_range(0.92, 1.06))
	var hour := int(floor(hours))
	if hour != _last_hour:
		if _last_hour >= 0 and hour >= 7 and hour <= 21 and (hour - _last_hour + 24) % 24 == 1:
			# Level by arithmetic, not yet by ear or recording: the strike is -22 dB mean, the beds
			# around it measure about -56 dB. At -4 dB and unit 30 it stood 24 to 30 dB over
			# everything in town (dev 2026-11-10: "a big bell just now"). Now about 8 dB over the
			# beds on the square (60 m) and 18 dB at the foot of the tower.
			_shot("bell", _ground(BELL_AT) + Vector3(0.0, 10.0, 0.0), -16.0 + linear_to_db(hush), 1.0, 18.0)
		if _last_hour == 5 and hour == 6 and dry:
			_shot("rooster", _ground(ROOSTER_AT), -6.0, 1.0, 25.0)
		_last_hour = hour
	if daylight > 0.5:
		_train_wait -= STEP
		if _train_wait <= 0.0:
			_train_wait = _rng.randf_range(360.0, 780.0)
			_shot("train_whistle" if _rng.randf() < 0.5 else "train_distant", TRAIN_AT + Vector3(0.0, 20.0, 0.0), -3.0 + linear_to_db(hush), 1.0, 140.0)
	# A sleigh somewhere off in town, now and then on a winter day.
	if season == "winter" and cover > 0.2 and outdoor > 0.3 and daylight > 0.4 and gust < 0.6:
		_sleigh_wait -= STEP
		if _sleigh_wait <= 0.0:
			_sleigh_wait = _rng.randf_range(300.0, 660.0)
			var bearing := _rng.randf_range(0.0, TAU)
			var away := Vector3(cos(bearing), 0.0, sin(bearing)) * _rng.randf_range(45.0, 80.0)
			_shot("sleigh_bells", at + away, -9.0 + linear_to_db(hush), _rng.randf_range(0.97, 1.03), 22.0)
	if cover > 0.05 and season == "spring" and outdoor > 0.3 and daylight > 0.4:
		_drip_wait -= STEP
		if _drip_wait <= 0.0:
			_drip_wait = _rng.randf_range(14.0, 30.0)
			var side := Vector3(_rng.randf_range(-6.0, 6.0), 1.5, _rng.randf_range(-6.0, 6.0))
			_shot("droplets", at + side, -10.0, _rng.randf_range(0.95, 1.08), 4.0)


func _shot(name: String, at: Vector3, db: float, pitch := 1.0, unit := 12.0) -> void:
	var player := _shots.get(name) as AudioStreamPlayer3D
	if player == null or player.playing or not at.is_finite(): return
	player.global_position = at
	player.unit_size = unit; player.volume_db = db; player.pitch_scale = pitch
	player.play()


func _place_hearth(at: Vector3, indoors: bool) -> void:
	if _hearth == null: return
	_hearth.remove_meta("lit")
	if indoors or GLOW._lit_places.is_empty(): return
	var best: Node3D = null
	var best_distance := 26.0 * 26.0
	for home: Node in get_tree().get_nodes_in_group("house_interiors"):
		var house := home as Node3D
		if house == null or not house.has_method("place_id"): continue
		var d := house.global_position.distance_squared_to(at)
		if d < best_distance and GLOW._lit_places.has(str(house.call("place_id"))):
			best = house; best_distance = d
	if best == null: return
	_hearth.global_position = best.global_position + Vector3(0.0, 1.2, 0.0)
	_hearth.set_meta("lit", true)


## A sparrow group stays in its tree until the listener is out of its reach (it is silent there,
## so the move is not heard), then takes a tree near them. With no tree near, a roof-high spot.
func _place_sparrows(at: Vector3) -> void:
	for index: int in _sparrows.size():
		var group := _sparrows[index] as AudioStreamPlayer3D
		if group.has_meta("perch") and group.global_position.distance_to(at) < SPARROW_REACH: continue
		var perch: Dictionary = _ambience.call("_tree_perch", at, 8.0 + 9.0 * index, 26.0 + 12.0 * index)
		var where: Vector3
		if perch.get("position") is Vector3:
			where = perch.position
		else:
			var bearing := _rng.randf_range(0.0, TAU)
			where = at + Vector3(cos(bearing) * 14.0, 5.0, sin(bearing) * 14.0)
		var other: AudioStreamPlayer3D = (_sparrows[1 - index] as AudioStreamPlayer3D) if _sparrows.size() > 1 else null
		if other != null and other.has_meta("perch") and other.global_position.distance_to(where) < SPARROW_APART:
			group.remove_meta("perch")
			continue
		group.global_position = where
		group.set_meta("perch", true)


## The brook voices' spots: the nearest point of the nearest river first, then the next nearest
## river points at least STREAM_APART from every spot taken, all within STREAM_NEAR. Each voice
## takes the spot nearest where it already is (so they do not swap sides); a voice that is silent
## jumps straight there, one that is sounding glides (_process).
func _place_streams(at: Vector3) -> void:
	if _streams.is_empty(): return
	var lines: Array[PackedVector3Array] = []
	if is_instance_valid(WorldWater.instance): lines = WorldWater.instance.flow_streams
	var flat := Vector2(at.x, at.z)
	var near: Array = []   # [distance, point]
	for line: PackedVector3Array in lines:
		for i: int in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var k := clampf((flat - Vector2(a.x, a.z)).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var p := a.lerp(b, k)
			var d := Vector2(p.x, p.z).distance_to(flat)
			if d <= STREAM_NEAR: near.append([d, p])
	near.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var spots: Array[Vector3] = []
	for item: Array in near:
		if spots.size() >= _streams.size(): break
		var p: Vector3 = item[1]
		var apart := true
		for s: Vector3 in spots:
			if Vector2(s.x - p.x, s.z - p.z).length() < STREAM_APART:
				apart = false; break
		if apart: spots.append(p + Vector3(0.0, 0.3, 0.0))
	var free: Array[AudioStreamPlayer3D] = []
	free.assign(_streams)
	for spot: Vector3 in spots:
		var best: AudioStreamPlayer3D = null
		var best_d := INF
		for voice: AudioStreamPlayer3D in free:
			var d := voice.global_position.distance_squared_to(spot) if voice.has_meta("spot") else INF * 0.5
			if best == null or d < best_d:
				best = voice; best_d = d
		free.erase(best)
		if not best.has_meta("spot") or not best.playing: best.global_position = spot
		best.set_meta("spot", spot)
	for voice: AudioStreamPlayer3D in free:
		voice.remove_meta("spot")


## The fountain sound at the real fountain's water; false (silent) while no fountain is loaded.
func _place_fountain() -> bool:
	var placed := _loops.get("fountain") as AudioStreamPlayer3D
	if placed == null: return false
	if not is_instance_valid(_fountain): _fountain = get_tree().get_first_node_in_group("town_fountains") as Node3D
	if not is_instance_valid(_fountain) or not _fountain.is_inside_tree() or not _fountain.has_method("sound_point"): return false
	placed.global_position = _fountain.call("sound_point")
	return true


func _place_frogs(at: Vector3) -> void:
	if _frogs == null: return
	_frogs.remove_meta("water")
	var found: Dictionary = _ambience.call("_nearest_water", at)
	var where: Variant = found.get("position")
	if where is Vector3 and (where as Vector3).is_finite():
		_frogs.global_position = where
		_frogs.set_meta("water", true)
