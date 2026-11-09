extends Node3D
## One television, any model: the vintage set (tv_model.gd) or a flatscreen (flat_model.gd, on its
## stand or on the wall). catalog.gd sets `model` and `variant` when it builds the set; all the
## shape this script needs comes from model.spec(variant) (screen_common.gd), so everything below
## (videos, the photo slideshow, the web browser, the set's light, sound, captions, ponies watching
## along) is shared by every model.
## Made under the set's shop visual (catalog.gd build_visual), so it exists on the market table,
## in the hands and placed in a house. It works once it stands somewhere and its kind is woken
## (finds.gd powered: the spell gives it its own endless power, so anywhere will do): placed
## in a house (any house, ext/home_furnishing.gd; its briefcase loan has a furnishing_home), or set
## down out of doors, upright and at rest. It stops when picked up again (its media player and
## screen are freed) or when it tips over.
## While working, the item's body carries meta "watch_tv" -> this node (tv_controls.gd keeps E and
## clicks on the front from picking the set up). The TV remote calls press(action); the TV menu
## calls play_file, the track and picture setters, start_slides, open_web and status(); TV mode
## (screen_input.gd) calls pointer_*, key and set_cursor.
## What is on (`source`): "video" (ffmpeg, media_player.gd), "slides" (slideshow.gd, also on its
## own after IDLE_SECONDS with nothing on) or "web" (web_view.gd); "" when nothing is.
## On the screen: a caption at the top (what is on, for a few seconds after a change) and the
## subtitles at the bottom. The vintage screen plays a power-on line and a power-off dot, a
## flatscreen fades; a shadowless spotlight in front takes the picture's colour and brightness, so
## the room is lit by the set; the power light glows while something is on.
## Ponies watching along (watch_company.gd) read the subtitles through heard() and talking_now():
## the shown track when it is text, otherwise the best text track, read in the background even with
## subtitles off on the screen. Without a text track, a picture track (Blu-ray, DVD) is read with
## OCR, or else the picture itself (picture_subs.gd, _start_ocr). On a web page
## they get the pages opened instead, and only as far as the player lets them (settings web_ponies:
## "none", "words" = the page's title, address and some text, YouTube captions; "pictures" = also
## the page itself through pony vision).
## Out of the Everfree, a set does nothing (dark, the remote finds no set that is on) until
## somepony has woken one of its kind with magic (finds.gd powered, magic_quest.gd). Placed
## but not working it is in the group "watch_tvs_dormant"; power_up() is her spell: the vintage set
## hisses with static for a while, a flatscreen shows a drifting "No Signal".

const FINDS := preload("res://mods/watch_party/finds.gd")
const MODEL := preload("res://mods/watch_party/tv_model.gd")
const COMMON := preload("res://mods/watch_party/screen_common.gd")
const PLAYER := preload("res://mods/watch_party/media_player.gd")
const TOOLS := preload("res://mods/watch_party/ffmpeg_tools.gd")
const SUBTITLES := preload("res://mods/watch_party/subtitles.gd")
## Subtitles read with OCR, for a film the ponies could not follow otherwise.
const PICTURE_SUBS := preload("res://mods/watch_party/picture_subs.gd")
const SLIDES := preload("res://mods/watch_party/slideshow.gd")
const WEB := preload("res://mods/watch_party/web_view.gd")
const HUB := "/root/Mods/watch_party"
const CHECK_SECONDS := 0.5
const CAPTION_SECONDS := 3.5
const SKIP_SECONDS := 10.0
const VOLUME_STEP := 3.0
## The quietest volume; one step below it the set is muted (MUTED_DB).
const VOLUME_MIN := -40.0
const VOLUME_MAX := 6.0
const MUTED_DB := -80.0
const REMEMBER_EVERY := 10.0
## The set's light: how far it reaches, how bright a white picture makes it, how fast it follows.
const GLOW_RANGE := 4.5
const GLOW_NEAR_RANGE := 2.2
const GLOW_ENERGY := 1.0
## How strongly mid-bright pictures are lifted toward full light (_update_glow).
const GLOW_LIFT := 2.5
const GLOW_FOLLOW := 6.0
const POWER_ON_SECONDS := 0.4
const POWER_OFF_SECONDS := 0.32
const FADE_ON_SECONDS := 0.35
const FADE_OFF_SECONDS := 0.3
## In the hand the set is a small model of itself (playtest 2026-11-03: the full-size set filled
## the view): this long across, its collision box (placement checks) stays full size.
const HELD_SIZE := 0.26
const HELD_SHRINK_SPEED := 10.0
## The slideshow starts by itself after the set has been off this long (dark: switched off with
## the power button, or nothing put on), when Settings → Watch Party allows it (off by default;
## dev 2026-11-06: "start when it is off for 5 minutes").
const IDLE_SECONDS := 300.0
## How often a set that has been off long enough checks whether it may start (Anon near, no other set on).
const IDLE_CHECK := 1.0
## The crossfade between pictures (playtest 2026-11-04: 1.2 s felt slow).
const SLIDE_FADE := 0.6
const IDLE_NEAR := 12.0
## How often the page's colour is sampled for the set's light.
const WEB_AVERAGE_EVERY := 0.25
## The first picture after the spell: static (vintage) or "No Signal" (flatscreen), this long.
const WAKE_SECONDS := 25.0
## Luna's set wakes to a night sky (night_sky.gd) for this long instead, its stars twinkling this
## many times a second.
const NIGHT_SECONDS := 45.0
const NIGHT_FPS := 3.0
## Celestia's sunrise plays over this long, then stays until the wake is over.
const SUNRISE_RISE := 22.0
## Static: frames made once at this size, shown this many times a second, with its hiss this loud.
const STATIC_SIZE := Vector2i(160, 120)
const STATIC_FRAMES := 8
const STATIC_FPS := 20.0
const HISS_DB := -14.0
## The "No Signal" label drifts across the dark panel this fast (screen widths per second).
const NO_SIGNAL_SPEED := 0.08

var model: Script = MODEL
var variant := ""
var spec: Dictionary = {}
var body: RigidBody3D
var screen: MeshInstance3D
var active := false
var player: Node
var speaker: AudioStreamPlayer3D
var caption: Label3D
var subtitle_label: Label3D
var subtitles := SUBTITLES.new()
var current := ""
var info: Dictionary = {}
var subtitle_key := "off"
var source := ""
var slides: Node
var web: Node
var _check := 0.0
## Settings → Watch Party, "Light from the screen" (settings_tab.gd): "full", "near" or "off".
var _light_mode := "full"
var _caption_until := 0.0
var _remember := 0.0
var _probe: Thread
var _probe_for := ""
var _probe_at := -1.0
var _material: ShaderMaterial
var _powered := false
var _power_tween: Tween
var _fade_tween: Tween
var _glow: SpotLight3D
var _glow_colour := Color.BLACK
var _glow_energy := 0.0
var _glow_time := 0.0
var _power_light: MeshInstance3D
var _power_light_on := false
var _held := false
var _idle := 0.0
var _idle_check := 0.0
## The power button turned it off: no slideshow until it is used again.
var _switched_off := false
var _shown: Texture2D
var _slide_average := Color.BLACK
## A GIF or WebM in the slideshow: its file, when it started, and that its first frame is new.
var _moving := ""
var _moving_since := 0.0
var _moving_fresh := false
## WebMs looked at for a sound track (path -> has one); a GIF never has one.
var _moving_sound := {}
var _moving_probe: Thread
var _web_average := Color(0.8, 0.8, 0.8)
var _web_sample := 0.0
var _web_session := 0
## The ponies' own subtitle reader (when the shown track is not text) and what they read.
var pony_lines := SUBTITLES.new()
## No text subtitles: a picture track, or the picture itself, read with OCR (_start_ocr).
var pony_ocr := PICTURE_SUBS.new()
var _live_clock := 0.0
var _pony_shared := false
var pony_track := ""
## Where a watching pony looks: the middle of the screen.
var gaze_point: Node3D
## The film turned down while a pony nearby speaks (watch_company.gd), in dB.
var duck_db := 0.0
## Set down outside a house (_standing): upright this much (the cosine of its lean) to come on,
## this much to stay on, and moving slower than this (m/s) to come on.
const STAND_UPRIGHT := 0.8
const STAND_KEEP := 0.5
const STAND_STILL := 0.15
## Standing somewhere (_standing), but its kind is not woken yet (FINDS.powered).
var dormant := false
## Seconds left of the wake-up picture (power_up), 0 when none.
var _waking := 0.0
## The spell is in it but nopony has switched it on yet (arm): dark, and the first press of
## the remote's power or play button brings up the wake-up picture (magic_quest.gd waits for it).
var _armed := false
## Trixie's spell went wrong (magic_quest.gd): the first switch-on (press or her own) does not wake
## it but sets `blown`, and the quest blows it up (tv_blast.gd).
var doomed := false
var blown := false
## Seconds of smoke still curling out of its back (smoke(); Trixie's spell), INF while it lasts.
var _smoke_left := 0.0
var _smoke_clock := 0.0
const SMOKE_EVERY := 0.55
const SMOKE_AFTER_ON := 30.0
var _static: Array[ImageTexture] = []
## The slideshow for ponies watching along (watch_company.gd): the picture on now, how many have
## shown, since when, and a number for each run (so a description belongs to one run).
var _slide_shown: Texture2D
## How the next power_up wakes it: "" (static or "No Signal"), "night" (Luna) or "sunrise"
## (Celestia): magic_quest.gd sets it with prepare_wake, which makes the pictures ahead on a worker
## thread. The pictures of the wake under way, and which shows.
var wake_style := ""
var _wake_images: Array = []
var _wake_task := -1
var _night: Array[ImageTexture] = []
var _night_index := 0
var _wake_clock := 0.0
var _slide_count := 0
var _slides_started := 0
var _slides_run := 0
var _static_clock := 0.0
var _hiss: AudioStreamPlayer3D
var _hiss_playback: AudioStreamGeneratorPlayback
var _no_signal: Label3D
var _no_signal_velocity := Vector2.ZERO

func _ready() -> void:
	spec = model.call("spec", variant)
	screen = get_parent().get_node_or_null("Screen") as MeshInstance3D
	if is_instance_valid(screen): _material = screen.material_override as ShaderMaterial
	_power_light = get_parent().get_node_or_null("PowerLight") as MeshInstance3D
	var up := get_parent()
	while up != null and not up is RigidBody3D: up = up.get_parent()
	body = up as RigidBody3D

func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = CHECK_SECONDS
		var standing := _standing(not active)
		var working := standing and FINDS.powered(item_id())
		if working and not active: _activate()
		elif not working and active: _deactivate()
		_set_dormant(standing and not working)
		_held = _in_hand()
		var settings: RefCounted = _settings()
		_light_mode = str(settings.room_light) if settings != null else "full"
	_shrink(delta)
	if _smoke_left > 0.0: _update_smoke(delta)
	if not active: return
	if _waking > 0.0: _update_wake(delta)
	_remember -= delta
	if _remember <= 0.0 and source == "video" and is_instance_valid(player) and player.state == "playing":
		_remember = REMEMBER_EVERY
		_keep_place(false)
	_update_idle(delta)
	_update_caption()
	_update_subtitle()
	_update_ocr(delta)
	_update_glow(delta)
	_update_power_light()

func _exit_tree() -> void:
	_collect_wake()
	if active: _deactivate()
	_finish_probe()
	_finish_moving_probe()
	subtitles.stop()
	pony_lines.stop()
	pony_ocr.stop()

## Placed in a house: frozen, solid on layer 1, and furnished in its briefcase loan.
func _placed() -> bool:
	if not is_instance_valid(body) or not body.is_inside_tree() or body.has_meta("for_sale"): return false
	if not body.freeze or (body.collision_layer & 1) == 0: return false
	var token := str(body.get_meta("token", ""))
	var store: Variant = _store()
	if token.is_empty() or store == null: return false
	var loans: Variant = (store as Object).get("loans")
	if not loans is Dictionary or not (loans as Dictionary).has(token): return false
	var loan: Variant = (loans as Dictionary)[token]
	return loan is Dictionary and (loan as Dictionary).has("furnishing_home")

## Where it can work: placed in a house, or Anon's own set put down anywhere else, upright (not on
## its side or face) and, to start (`settled`), at rest. Once on it keeps going through a bump.
func _standing(settled: bool) -> bool:
	if _placed(): return true
	if not is_instance_valid(body) or not body.is_inside_tree() or body.has_meta("for_sale"): return false
	if str(body.get_meta("token", "")).is_empty() or _in_hand(): return false
	var up := body.global_basis.y.normalized().dot(Vector3.UP)
	if not settled: return up > STAND_KEEP
	return up > STAND_UPRIGHT and (body.freeze or body.linear_velocity.length() < STAND_STILL)

## The good this set is ("goods:watch-tv-vintage", ...), from its shop visual (catalog.gd).
func item_id() -> String:
	var visual := get_parent()
	return str(visual.get("item_id")) if visual != null and visual.get("item_id") != null else ""

func _set_dormant(on: bool) -> void:
	if on == dormant: return
	dormant = on
	if on: add_to_group("watch_tvs_dormant")
	else: remove_from_group("watch_tvs_dormant")

## The spell is in it and Anon switches it on (or she does): the set comes on for the first time,
## showing the wake-up picture until WAKE_SECONDS pass or the remote is used.
func arm() -> void:
	if not active and _standing(false): _activate()
	if not active: return
	_set_dormant(false)
	_armed = true
	if is_instance_valid(caption): caption.visible = false

func armed() -> bool:
	return _armed

## The next wake-up picture is a night sky or a sunrise: its pictures are made now, on a worker
## thread, so switching it on does not stutter.
func prepare_wake(style: String) -> void:
	_collect_wake()
	wake_style = style
	_wake_images = []
	var size := _wake_size()
	var script: Script = _wake_script(style)
	if script == null: return
	_wake_task = WorkerThreadPool.add_task(func() -> void: _wake_images = script.call("images", size))

func _collect_wake() -> void:
	if _wake_task < 0: return
	WorkerThreadPool.wait_for_task_completion(_wake_task)
	_wake_task = -1

func _wake_size() -> Vector2i:
	var aspect := _size().x / maxf(0.01, _size().y)
	return Vector2i(roundi(200.0 * aspect), 200)

static func _wake_script(style: String) -> Script:
	return load("res://mods/watch_party/sunrise.gd" if style == "sunrise" else "res://mods/watch_party/night_sky.gd")

## Smoke out of the set's back for `seconds` (INF: until smoke(0)). Trixie's spell (magic_quest.gd).
func smoke(seconds: float) -> void:
	_smoke_left = seconds
	_smoke_clock = 0.0

func _update_smoke(delta: float) -> void:
	_smoke_left -= delta
	_smoke_clock -= delta
	if _smoke_clock > 0.0 or _in_hand(): return
	_smoke_clock = SMOKE_EVERY * randf_range(0.7, 1.3)
	var top := Vector3(_centre().x * 0.5, _centre().y + _size().y * 0.5, float(spec.get("z", 0.0)) - 0.12)
	var blast: Script = load("res://mods/watch_party/tv_blast.gd")
	if blast != null: blast.call("wisp", self, to_global(top))

func waking() -> bool:
	return _waking > 0.0

func power_up() -> void:
	_armed = false
	# Trixie's smoke thins out once it is on (magic_quest.gd sets it when her quest is still there).
	if _smoke_left > SMOKE_AFTER_ON: _smoke_left = SMOKE_AFTER_ON
	if not active and _standing(false): _activate()
	if not active: return
	_set_dormant(false)
	if source != "": stop()
	# Woken again while still waking: the old picture goes first (never two "No Signal"s).
	if _waking > 0.0: _end_wake(false)
	_waking = WAKE_SECONDS
	_static_clock = 0.0
	if wake_style in ["night", "sunrise"]:
		# Luna's peaceful night sky, its stars twinkling, or Celestia's sunrise (the CRT look
		# applies as to any picture).
		var style := wake_style
		wake_style = ""
		_waking = NIGHT_SECONDS
		_wake_clock = 0.0
		_collect_wake()
		if _wake_images.is_empty(): _wake_images = _wake_script(style).call("images", _wake_size())
		_night.clear()
		for image: Variant in _wake_images:
			if image is Image: _night.append(ImageTexture.create_from_image(image))
		_wake_images = []
		_night_index = 0
		set_meta("wake_rise", style == "sunrise")
		if not _night.is_empty(): _show_texture(_night[0])
		if is_instance_valid(caption): caption.visible = false
		print("[watch_party] a %s woke up (%s)" % [str(spec.kind), "a night sky" if style == "night" else "a sunrise"])
		return
	if str(spec.kind) == "crt":
		_make_static()
		_show_texture(_static[0])
		_start_hiss()
	else:
		var black := Image.create(4, 4, false, Image.FORMAT_RGB8)
		black.fill(Color(0.01, 0.01, 0.03))
		_show_texture(ImageTexture.create_from_image(black))
		var text_scale := _size().y / 0.63
		_no_signal = _screen_label("TvNoSignal", 30, Vector3(_centre().x, _centre().y, float(spec.text_z)), text_scale)
		_no_signal.autowrap_mode = TextServer.AUTOWRAP_OFF
		_no_signal.text = "No Signal"
		_no_signal.modulate = Color("dfe6ff")
		_no_signal.outline_modulate = Color(0.05, 0.1, 0.45, 1.0)
		_no_signal.outline_size = 12
		_no_signal_velocity = Vector2(1.0, 0.62).normalized() * NO_SIGNAL_SPEED * _size().x
	if is_instance_valid(caption): caption.visible = false
	print("[watch_party] a %s woke up (%s)" % [str(spec.kind), "static" if str(spec.kind) == "crt" else "no signal"])

func _update_wake(delta: float) -> void:
	_waking -= delta
	if _waking <= 0.0:
		_end_wake(true)
		return
	if not _night.is_empty():
		_wake_clock += delta
		if bool(get_meta("wake_rise", false)):
			# The sunrise: each picture in turn across SUNRISE_RISE, then the morning stays.
			var index := mini(_night.size() - 1, int(_wake_clock / SUNRISE_RISE * _night.size()))
			if index != _night_index:
				_night_index = index
				_show_texture(_night[index])
			return
		_static_clock -= delta
		if _static_clock <= 0.0:
			_static_clock = 1.0 / NIGHT_FPS
			_night_index = (_night_index + 1) % _night.size()
			_show_texture(_night[_night_index])
		return
	if not _static.is_empty() and str(spec.kind) == "crt":
		_static_clock -= delta
		if _static_clock <= 0.0:
			_static_clock = 1.0 / STATIC_FPS
			_show_texture(_static[randi() % _static.size()])
		_feed_hiss()
	if is_instance_valid(_no_signal):
		# Bounces off the screen's edges, the way an idle panel's notice drifts.
		var half := Vector2(0.111, 0.027) * (_size().y / 0.63)
		var low := _centre() - _size() * 0.5 + half
		var high := _centre() + _size() * 0.5 - half
		var at := Vector2(_no_signal.position.x, _no_signal.position.y) + _no_signal_velocity * delta
		if at.x < low.x or at.x > high.x: _no_signal_velocity.x = -_no_signal_velocity.x
		if at.y < low.y or at.y > high.y: _no_signal_velocity.y = -_no_signal_velocity.y
		at = at.clamp(low, high)
		_no_signal.position = Vector3(at.x, at.y, _no_signal.position.z)

## The wake-up picture is over (its time is up, the remote was used, or the set was put away).
func _end_wake(power_off: bool) -> void:
	if _waking <= 0.0 and not is_instance_valid(_hiss) and not is_instance_valid(_no_signal) and _night.is_empty(): return
	_waking = 0.0
	_night.clear()
	if is_instance_valid(_hiss): _hiss.queue_free()
	_hiss = null
	_hiss_playback = null
	if is_instance_valid(_no_signal): _no_signal.queue_free()
	_no_signal = null
	if power_off and source == "":
		_power_off(true)
		_show_caption()

## Grey snow, made once: a few frames shown in random order look like a live tube.
func _make_static() -> void:
	if not _static.is_empty(): return
	var rng := RandomNumberGenerator.new()
	for frame in STATIC_FRAMES:
		var bytes := PackedByteArray()
		bytes.resize(STATIC_SIZE.x * STATIC_SIZE.y)
		for row in STATIC_SIZE.y:
			# A faint rolling band, brighter on some lines.
			var band := 0.75 + 0.25 * sin(float(row + frame * 13) * 0.21)
			for column in STATIC_SIZE.x:
				bytes[row * STATIC_SIZE.x + column] = int(clampf(rng.randf() * 255.0 * band, 0.0, 255.0))
		_static.append(ImageTexture.create_from_image(Image.create_from_data(STATIC_SIZE.x, STATIC_SIZE.y, false, Image.FORMAT_L8, bytes)))

## The tube's hiss, from the set itself (white noise, softened a little).
func _start_hiss() -> void:
	if is_instance_valid(_hiss): return
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.3
	_hiss = AudioStreamPlayer3D.new(); _hiss.name = "TvHiss"
	_hiss.stream = generator
	_hiss.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_hiss.unit_size = 3.0
	_hiss.max_distance = 30.0
	_hiss.position = spec.speaker
	var settings: RefCounted = _settings()
	_hiss.volume_db = (float(settings.volume_db) if settings != null else -6.0) + HISS_DB
	add_child(_hiss)
	_hiss.play()
	_hiss_playback = _hiss.get_stream_playback() as AudioStreamGeneratorPlayback
	_feed_hiss()

var _hiss_last := 0.0
func _feed_hiss() -> void:
	if _hiss_playback == null: return
	var count := _hiss_playback.get_frames_available()
	if count <= 0: return
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		_hiss_last = _hiss_last * 0.35 + randf_range(-1.0, 1.0) * 0.65
		frames[i] = Vector2(_hiss_last, _hiss_last) * 0.6
	_hiss_playback.push_buffer(frames)

## In one of the player's hands (the briefcase's held items).
func _in_hand() -> bool:
	var game: Variant = Mods.game
	var inventory: Variant = (game as Node).get("inventory") if is_instance_valid(game) else null
	var held: Variant = (inventory as Node).get("held") if is_instance_valid(inventory) else null
	return held is Dictionary and body in (held as Dictionary).values()

## Eases the look between full size and the small model held in the hand.
func _shrink(delta: float) -> void:
	var visual := get_parent() as Node3D
	if visual == null: return
	var box: AABB = model.call("bounds", variant)
	var target := HELD_SIZE / maxf(box.size.x, box.size.y) if _held else 1.0
	var now := visual.scale.x
	if is_equal_approx(now, target): return
	var next := lerpf(now, target, clampf(delta * HELD_SHRINK_SPEED, 0.0, 1.0))
	if absf(next - target) < 0.002: next = target
	visual.scale = Vector3.ONE * next

func _store() -> Variant:
	var game: Variant = Mods.game
	if not is_instance_valid(game): return null
	var inventory: Variant = (game as Node).get("inventory")
	if not is_instance_valid(inventory): return null
	var store: Variant = (inventory as Node).get("inventory")
	return store if store is Object else null

func hub() -> Node:
	return get_node_or_null(HUB)

func _centre() -> Vector2:
	return spec.centre

func _size() -> Vector2:
	return spec.size

func _activate() -> void:
	active = true
	print("[watch_party] a television is on (%s): " % ("placed in a house" if _placed() else "set down outside a house"), spec.kind, " ", variant)
	body.set_meta("watch_tv", self)
	add_to_group("watch_tvs")
	speaker = AudioStreamPlayer3D.new(); speaker.name = "TvSpeaker"
	speaker.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	# Sound from the set itself, fading with distance (a quieter room two doors away).
	speaker.unit_size = 3.0
	speaker.max_distance = 30.0
	speaker.position = spec.speaker
	add_child(speaker)
	_apply_volume()
	player = PLAYER.new(); player.name = "MediaPlayer"
	player.speaker = speaker
	var pixels: Vector2i = spec.picture
	player.width = pixels.x; player.height = pixels.y
	var settings: RefCounted = _settings()
	if settings != null: player.fill = bool(settings.fill)
	player.picture.connect(_on_picture)
	player.finished.connect(_on_finished)
	player.problem.connect(_on_problem)
	add_child(player)
	slides = SLIDES.new(); slides.name = "Slideshow"
	slides.size = pixels
	slides.picture.connect(_on_slide)
	slides.problem.connect(_note)
	slides.animated.connect(_on_moving)
	add_child(slides)
	var top := _centre().y + _size().y * 0.5
	var bottom := _centre().y - _size().y * 0.5
	var text_scale := _size().y / 0.63
	caption = _screen_label("TvCaption", 22, Vector3(_centre().x, top - 0.07 * text_scale, float(spec.text_z)), text_scale)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	subtitle_label = _screen_label("TvSubtitles", 26, Vector3(_centre().x, bottom + 0.055 * text_scale, float(spec.text_z)), text_scale)
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	subtitle_label.outline_size = 10
	subtitle_label.outline_modulate = Color(0, 0, 0, 0.9)
	subtitle_label.modulate = Color("fffbe8")
	_glow = SpotLight3D.new(); _glow.name = "TvGlow"
	_glow.position = Vector3(_centre().x, _centre().y, float(spec.glow_z))
	# A spotlight shines along its -Z; the screen faces +Z.
	_glow.rotation = Vector3(0, PI, 0)
	_glow.spot_range = GLOW_RANGE
	_glow.spot_angle = 70.0 if spec.kind == "crt" else 78.0
	_glow.spot_attenuation = 1.2
	_glow.light_energy = 0.0
	_glow.light_specular = 0.25
	_glow.shadow_enabled = false
	_glow.visible = false
	add_child(_glow)
	gaze_point = Node3D.new(); gaze_point.name = "TvGazePoint"
	gaze_point.position = Vector3(_centre().x, _centre().y, float(spec.z))
	add_child(gaze_point)
	_idle = 0.0
	_show_caption()
	var hub_node := hub()
	if hub_node != null and hub_node.has_method("tv_working"): hub_node.tv_working(self)

func _screen_label(node_name: String, font_size: int, at: Vector3, text_scale: float) -> Label3D:
	var label := Label3D.new(); label.name = node_name
	label.font_size = font_size; label.pixel_size = 0.0015 * text_scale; label.outline_size = 6
	label.modulate = Color("f2f2e8"); label.width = _size().x * 0.92 / label.pixel_size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = at
	add_child(label)
	return label

func _deactivate() -> void:
	if not active: return
	_armed = false
	_end_wake(false)
	_keep_place(true)
	active = false
	print("[watch_party] a television is off (picked up or unloaded)")
	if is_instance_valid(body) and body.get_meta("watch_tv", null) == self: body.remove_meta("watch_tv")
	remove_from_group("watch_tvs")
	var hub_node := hub()
	if hub_node != null and hub_node.has_method("tv_gone"): hub_node.tv_gone(self)
	subtitles.stop()
	pony_lines.stop()
	pony_ocr.stop()
	_close_web()
	# Only queue_free: this also runs from _exit_tree, when the tree is busy removing us.
	if is_instance_valid(player): player.stop()
	if is_instance_valid(slides): slides.stop()
	for node: Node in [player, slides, speaker, caption, subtitle_label, _glow, gaze_point]:
		if is_instance_valid(node): node.queue_free()
	player = null; slides = null; speaker = null; caption = null; subtitle_label = null; _glow = null; gaze_point = null
	source = ""
	_power_off(false)
	_update_power_light()

# --- the remote ---------------------------------------------------------------------------------

## A remote button: play, power, next, previous, louder, quieter, forward, back. On a web page the
## channel buttons go back and forward through its pages and the skip buttons scroll it.
func press(action: String) -> void:
	if not active: return
	touched()
	if _armed:
		# Switched on for the very first time, after the spell (a doomed one: magic_quest.gd blows it up).
		if action in ["power", "play"]:
			if doomed:
				_armed = false
				blown = true
			else: power_up()
		return
	if _waking > 0.0:
		# The first use after the spell clears the wake-up picture; volume just changes it.
		if action in ["louder", "quieter"]:
			change_volume(VOLUME_STEP if action == "louder" else -VOLUME_STEP)
			if is_instance_valid(_hiss) and _settings() != null: _hiss.volume_db = float(_settings().volume_db) + HISS_DB
			return
		_end_wake(true)
		if action == "power": return
	if source == "slides" and action in ["forward", "back", "next", "previous"]:
		# The wheel and Left/Right page through the pictures.
		slides.step(1 if action in ["forward", "next"] else -1)
		return
	if source == "slides" and action not in ["louder", "quieter"]:
		# Any use of the set ends the slideshow; the power button then turns it off as well.
		stop_slides()
		if action == "power": _switch_off()
		_show_caption()
		return
	if source == "web":
		match action:
			"power": _switch_off()
			"next": web.call("forward")
			"previous": web.call("back")
			"forward": web.call("scroll", 3.0)
			"back": web.call("scroll", -3.0)
			"louder": change_volume(VOLUME_STEP)
			"quieter": change_volume(-VOLUME_STEP)
		_show_caption()
		return
	match action:
		"play": toggle_play()
		"power": power()
		"next": channel(1)
		"previous": channel(-1)
		"louder": change_volume(VOLUME_STEP)
		"quieter": change_volume(-VOLUME_STEP)
		"forward": skip(SKIP_SECONDS)
		"back": skip(-SKIP_SECONDS)
	_show_caption()

## Anything done with the set: the idle clock starts again.
func touched() -> void:
	_idle = 0.0

func toggle_play() -> void:
	if not active or not is_instance_valid(player): return
	if source == "" and _probe == null and player.state in ["idle", "ended"] and _resume_last(): return
	_switched_off = false
	if source == "video" and player.state == "playing":
		player.pause()
		_keep_place(true)
	elif source == "video" and player.state == "paused": player.resume()
	elif not current.is_empty(): play_file(current)
	else: channel(1)

## The power button (holding the remote's button): a set that is on (tuning in, playing, paused,
## a slideshow or a page) turns off, keeping its place; one that is off comes back on with what
## was on last.
func power() -> void:
	if not active or not is_instance_valid(player): return
	if source in ["slides", "web"] or _probe != null or player.state in ["playing", "paused"]:
		_switch_off()
	else:
		toggle_play()

func _switch_off() -> void:
	_remember_on(source if source in ["web", "slides"] else "video")
	# A probe still running is dropped when it reports (_probed checks _probe_for).
	_probe_for = ""
	stop()
	_switched_off = true

## What a set that is off comes back with: kept whenever a video, the browser or a slideshow Anon
## chose starts, not only at the power button (playtest 2026-11-06: a film was on, the set was
## picked up or the game closed, and it came back on the browser from an earlier power-off).
func _remember_on(kind: String) -> void:
	var settings: RefCounted = _settings()
	if settings == null or str(settings.last_on) == kind: return
	settings.last_on = kind
	settings.save()

## A set that is off comes back with what was on last: the browser (its tabs), the slideshow, else
## (false) the video, the one watched last when this set has none yet, from where it was left.
func _resume_last() -> bool:
	var settings: RefCounted = _settings()
	if settings == null: return false
	match str(settings.last_on):
		"web": if open_web(): return true
		"slides": if start_slides(): return true
	if current.is_empty(): current = str(settings.last_watched())
	return false

## The next (or previous) file in the library, from where it was left.
func channel(step: int) -> void:
	var settings: RefCounted = _settings()
	if settings == null: return
	var library: PackedStringArray = settings.library
	if library.is_empty():
		settings.scan()
		library = settings.library
	if library.is_empty():
		_note("No videos yet. Add a folder in the TV menu (right click with the remote).")
		return
	var at := library.find(current)
	var next := 0 if at < 0 and step > 0 else (library.size() - 1 if at < 0 else posmod(at + step, library.size()))
	play_file(library[next])

func skip(seconds: float) -> void:
	if source != "video" or not is_instance_valid(player) or player.state in ["idle", "ended"]: return
	seek_to(player.position() + seconds)

func seek_to(seconds: float) -> void:
	if source != "video" or not is_instance_valid(player) or player.state in ["idle", "ended"]: return
	var length: float = float(info.get("duration", 0.0))
	player.seek(clampf(seconds, 0.0, length - 1.0) if length > 0.0 else maxf(0.0, seconds))
	_restart_subtitles()

## Up or down a step; down from the quietest mutes, up from muted is the quietest again.
func change_volume(step: float) -> void:
	var settings: RefCounted = _settings()
	if settings == null: return
	var now := float(settings.volume_db)
	var next := clampf(now + step, VOLUME_MIN, VOLUME_MAX)
	if step < 0.0 and now <= VOLUME_MIN: next = MUTED_DB
	elif step > 0.0 and now <= MUTED_DB: next = VOLUME_MIN
	_store_volume(next)

## A volume from the menu's slider (MUTED_DB or below mutes).
func set_volume(db: float) -> void:
	_store_volume(MUTED_DB if db < VOLUME_MIN else minf(db, VOLUME_MAX))

func _store_volume(db: float) -> void:
	var settings: RefCounted = _settings()
	if settings == null: return
	settings.volume_db = db
	settings.save()
	for tv: Node in get_tree().get_nodes_in_group("watch_tvs"):
		if tv.has_method("_apply_volume"): tv._apply_volume()

## Whatever is on stops and the screen goes dark.
func stop() -> void:
	if not is_instance_valid(player): return
	_keep_place(true)
	player.stop()
	subtitles.stop()
	pony_lines.stop()
	pony_ocr.stop()
	if is_instance_valid(slides): slides.stop()
	_moving = ""
	_close_web()
	source = ""
	_power_off(true)
	_show_caption()

# --- the photo slideshow ------------------------------------------------------------------------

## Starts the slideshow of the folder in the settings (TV menu, or on its own when idle: then it is
## not what the set comes back with).
func start_slides(chosen := true) -> bool:
	if not active: return false
	_end_wake(true)
	var settings: RefCounted = _settings()
	if settings == null: return false
	if source == "video" or source == "web": stop()
	# Silent, so it leaves the other sets alone (hub tv_playing is for sound).
	_switched_off = false
	source = "slides"
	if not slides.start(str(settings.slides_folder), float(settings.slides_seconds)):
		source = ""
		return false
	if chosen: _remember_on("slides")
	_slides_run += 1
	_slides_started = Time.get_ticks_msec()
	_slide_count = 0
	_slide_shown = null
	print("[watch_party] slideshow: %d pictures from %s" % [slides.files.size(), str(settings.slides_folder)])
	_show_caption()
	return true

func stop_slides() -> void:
	if source != "slides": return
	slides.stop()
	_stop_moving()
	source = ""
	_power_off(true)

func _on_slide(texture: ImageTexture, average: Color) -> void:
	if source != "slides" or _material == null: return
	_stop_moving()
	_slide_average = average
	_slide_shown = texture
	_slide_count += 1
	_slide_in(texture)

## A new picture fades in over the last one (the first just appears).
func _slide_in(texture: Texture2D) -> void:
	var first := not _powered
	_show_texture(texture)
	if first:
		_material.set_shader_parameter("fade", 1.0)
		return
	# Crossfade: the last picture stays as `previous` while the new one fades in over it.
	if _fade_tween != null: _fade_tween.kill()
	_set_fade(0.0)
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, 0.0, 1.0, SLIDE_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## A GIF or WebM from the slideshow: played by ffmpeg like a film, fitted, with its sound if it
## has any (looked up once per WebM on a thread: a film started with sound but none in the file
## would stand still, since its sound is its clock).
func _on_moving(path: String) -> void:
	if source != "slides" or not is_instance_valid(player): return
	var hub_node := hub()
	var ffmpeg: String = str(hub_node.get("ffmpeg")) if hub_node != null else ""
	if ffmpeg.is_empty():
		# No ffmpeg: skip moving pictures.
		slides.playing_moving = false
		slides.step(1)
		return
	_moving = path
	_moving_since = Time.get_ticks_msec() / 1000.0
	_moving_fresh = true
	if path.get_extension().to_lower() == "webm" and not _moving_sound.has(path):
		_finish_moving_probe()
		_moving_probe = Thread.new()
		_moving_probe.start(_probe_moving.bind(TOOLS.ffprobe_for(ffmpeg), path))
		return
	_play_moving()

func _probe_moving(ffprobe: String, path: String) -> void:
	var info := TOOLS.probe(ffprobe, path)
	# probe() guesses one sound track when ffprobe says nothing; a known length means it answered.
	var sound := bool(info.get("ok", false)) and float(info.get("duration", 0.0)) > 0.0 and not (info.get("audio", []) as Array).is_empty()
	_moving_probed.call_deferred(path, sound)

func _moving_probed(path: String, sound: bool) -> void:
	_finish_moving_probe()
	_moving_sound[path] = sound
	if path == _moving and source == "slides": _play_moving()

func _finish_moving_probe() -> void:
	if _moving_probe != null and _moving_probe.is_started(): _moving_probe.wait_to_finish()
	_moving_probe = null

func _play_moving() -> void:
	player.ffmpeg = str(hub().get("ffmpeg"))
	player.fill = false
	player.tonemap = false
	player.burn_subtitle = -1
	if not player.play(_moving, 0.0, 0.0, bool(_moving_sound.get(_moving, false)), 0):
		print("[watch_party] slideshow: could not play ", _moving)
		_moving_done()

## One time through: again while the picture's seconds last, else the next picture.
func _moving_done() -> void:
	if source != "slides" or _moving.is_empty(): return
	var shown := Time.get_ticks_msec() / 1000.0 - _moving_since
	if shown < float(slides.seconds) and player.error.is_empty():
		_play_moving()
		return
	_moving = ""
	slides.playing_moving = false
	slides.step(1)

func _stop_moving() -> void:
	if _moving.is_empty(): return
	_moving = ""
	if is_instance_valid(player): player.stop()

func _set_fade(amount: float) -> void:
	if _material != null: _material.set_shader_parameter("fade", amount)

func _update_idle(delta: float) -> void:
	var dark: bool = source == "" and _probe == null and _waking <= 0.0 and not _armed and (not is_instance_valid(player) or player.state in ["idle", "ended"])
	if not dark:
		_idle = 0.0
		return
	if _idle < IDLE_SECONDS:
		_idle += delta
		return
	# Off long enough: it waits (the time kept full) until it may start.
	_idle_check -= delta
	if _idle_check > 0.0: return
	_idle_check = IDLE_CHECK
	var settings: RefCounted = _settings()
	if settings == null or str(settings.slides_folder).is_empty() or not bool(settings.slides_when_idle): return
	# A picture frame for the room Anon is in: not in an empty house, and never while another set
	# has something on (playtest 2026-11-03: an idle set two houses away took over).
	if not _player_near(): return
	for other: Node in get_tree().get_nodes_in_group("watch_tvs"):
		if other != self and str((other.call("status") as Dictionary).get("mode", "")) != "": return
	_idle = 0.0
	start_slides(false)

# --- the web browser ----------------------------------------------------------------------------

## Opens the browser on this set at `url` (its home page when empty).
## Anon is near this set (the screen saver only runs where he can see it).
func _player_near() -> bool:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera != null and camera.global_position.distance_to(global_position) <= IDLE_NEAR

func open_web(url := "") -> bool:
	if not active: return false
	_end_wake(true)
	var hub_node := hub()
	var engine: Node = hub_node.get("web") as Node if hub_node != null else null
	if engine == null: return false
	if source == "web" and is_instance_valid(web) and bool(web.call("alive")):
		if not url.is_empty(): web.call("go", url)
		return true
	if source != "": stop()
	if hub_node.has_method("tv_playing"): hub_node.tv_playing(self)
	_switched_off = false
	web = WEB.new(); web.name = "WebPage"
	web.engine = engine
	web.speaker = speaker
	web.settings = _settings()
	# Settings → Watch Party "Page resolution": Chromium draws fewer pixels, stretched over the page.
	web.page_scale = 0.75 if web.settings != null and int(web.settings.browser_scale) == 75 else 1.0
	web.size = spec.page
	web.painted.connect(_on_web_paint)
	web.notice.connect(_note)
	add_child(web)
	# No address: the tabs open last time come back (else the home page).
	if not bool(web.call("open", url)):
		_note(str(engine.get("note")))
		web.queue_free()
		web = null
		return false
	source = "web"
	_remember_on("web")
	_web_session += 1
	_show_caption()
	return true

func _close_web() -> void:
	if is_instance_valid(web):
		web.call("close")
		web.queue_free()
	web = null
	if source == "web": source = ""
	set_cursor(Vector2(-1, -1))

func _on_web_paint(texture: Texture2D) -> void:
	if source != "web": return
	if texture != _shown or not _powered: _show_texture(texture)

## How much ponies watching along may know of the browser: "none", "words" or "pictures"
## (watch_settings.gd web_ponies).
func web_level() -> String:
	var settings: RefCounted = _settings()
	return str(settings.web_ponies) if settings != null else "none"

## The page is on and ponies may know what it is (its title, address and words).
func web_shared() -> bool:
	return source == "web" and web_level() != "none"

# --- TV mode (screen_input.gd) ------------------------------------------------------------------

## Where TV mode's pointer is on the picture (UV), or off the screen (-1, -1).
func set_cursor(uv: Vector2) -> void:
	if _material != null: _material.set_shader_parameter("cursor", uv)
	# TV mode left: scrolling by the pointer stops with it.
	if uv.x < 0.0 and source == "web" and is_instance_valid(web): web.call("end_autoscroll")

func pointer_move(uv: Vector2) -> void:
	touched()
	if source == "web": web.call("move", uv)

func pointer_button(index: int, pressed: bool) -> void:
	touched()
	if source == "slides":
		if pressed: stop_slides()
		return
	if source == "web": web.call("button", index, pressed)

## Wheel notches on the screen; with Ctrl the page zooms.
func pointer_wheel(notches: float, shift := false, ctrl := false) -> void:
	touched()
	if source == "web": web.call("wheel", notches, shift, ctrl)
	elif source == "slides": slides.step(1 if notches > 0.0 else -1)

func key(event: InputEventKey) -> void:
	touched()
	if source == "slides":
		if event.pressed: stop_slides()
		return
	if source == "web": web.call("key", event)

## A VR keyboard key: one character, or a keycode (Enter, Backspace, Tab, arrows).
func tap(character: String, keycode := KEY_NONE) -> void:
	touched()
	if source == "web": web.call("tap", character, keycode)

# --- tracks and picture -------------------------------------------------------------------------

## The current file's sound tracks: [{track, label}].
func audio_choices() -> Array:
	var out: Array = []
	for row: Variant in info.get("audio", []):
		if not row is Dictionary: continue
		var stream: Dictionary = row
		var words := PackedStringArray()
		var language := str(stream.get("language", ""))
		if not language.is_empty() and language != "und": words.append(SUBTITLES._language(language))
		var title := str(stream.get("title", ""))
		if not title.is_empty(): words.append(title)
		if words.is_empty(): words.append("Track %d" % (int(stream.get("track", 0)) + 1))
		out.append({"track": int(stream.get("track", 0)), "label": " · ".join(words)})
	return out

func audio_track() -> int:
	return int(player.audio_track()) if is_instance_valid(player) else 0

## The current file's subtitle choices (subtitles.gd choices()).
func subtitle_choices() -> Array:
	return SUBTITLES.choices(current, info) if not current.is_empty() else [{"key": "off", "label": "Off", "kind": "off"}]

func set_audio(track: int) -> void:
	if source != "video" or not is_instance_valid(player) or player.state in ["idle", "ended"]: return
	player.restart(track)
	_remember_tracks()
	_show_caption()

func set_subtitle(key_name: String) -> void:
	subtitle_key = key_name
	_apply_subtitle(true)
	_remember_tracks()

## The CRT look (scanlines, stripe mask) on the vintage sets; flatscreens never have it.
func set_crt(on: bool) -> void:
	var settings: RefCounted = _settings()
	if settings != null:
		settings.crt = on
		settings.save()
	for tv: Node in get_tree().get_nodes_in_group("watch_tvs"):
		if tv.has_method("_apply_crt"): tv._apply_crt()

func _apply_crt() -> void:
	var settings: RefCounted = _settings()
	var on: bool = (bool(settings.crt) if settings != null else true) and str(spec.kind) == "crt"
	if _material != null: _material.set_shader_parameter("crt", 1.0 if on else 0.0)

func set_fill(on: bool) -> void:
	var settings: RefCounted = _settings()
	if settings != null:
		settings.fill = on
		settings.save()
	if not is_instance_valid(player): return
	player.fill = on
	if source == "video": player.restart(audio_track())

## Starts the chosen subtitles: text ones are read here, picture ones are drawn into the picture
## by ffmpeg (which needs the picture started again).
func _apply_subtitle(restart: bool) -> void:
	var chosen: Dictionary = {}
	for row: Dictionary in subtitle_choices():
		if str(row.key) == subtitle_key: chosen = row
	if chosen.is_empty():
		subtitle_key = "off"
		chosen = {"key": "off", "kind": "off"}
	var burn := int(chosen.get("track", -1)) if str(chosen.kind) == "picture" else -1
	if is_instance_valid(player) and int(player.burn_subtitle) != burn:
		player.burn_subtitle = burn
		if restart and source == "video": player.restart(audio_track())
	_restart_subtitles()

func _restart_subtitles() -> void:
	var hub_node := hub()
	var ffmpeg: String = str(hub_node.get("ffmpeg")) if hub_node != null else ""
	var chosen: Dictionary = {}
	for row: Dictionary in subtitle_choices():
		if str(row.key) == subtitle_key: chosen = row
	var at: float = float(player.position()) if is_instance_valid(player) else 0.0
	if ffmpeg.is_empty() or chosen.is_empty(): subtitles.stop()
	else: subtitles.start(ffmpeg, current, chosen, at)
	if is_instance_valid(subtitle_label): subtitle_label.text = ""
	_restart_pony_lines(ffmpeg, at)

## What the ponies read: the shown subtitles when they are text, else the best text track, read
## on its own from `at` (nothing when the file has picture subtitles only).
func _restart_pony_lines(ffmpeg: String, at: float) -> void:
	pony_lines.stop()
	pony_ocr.stop()
	_pony_shared = str(subtitles.choice.get("kind", "off")) == "text"
	pony_track = str(subtitles.choice.get("label", "")) if _pony_shared else ""
	if _pony_shared or current.is_empty(): return
	var rows := subtitle_choices()
	var best := best_pony_choice(rows)
	if best.is_empty():
		_start_ocr(ffmpeg, rows, at)
		return
	pony_track = str(best.get("label", ""))
	if not ffmpeg.is_empty(): pony_lines.start(ffmpeg, current, best, at)

## No text subtitles: the best picture track is read with OCR (Settings → Watch Party "Read picture
## subtitles"), else the picture itself ("Read subtitles in the picture"; also a picture track
## shown on the screen when the first is off). Neither without an OCR engine (main.gd ocr).
func _start_ocr(ffmpeg: String, rows: Array, at: float) -> void:
	var hub_node := hub()
	var settings: RefCounted = _settings()
	var ocr: Variant = hub_node.get("ocr") if hub_node != null else null
	if not ocr is RefCounted or settings == null or ffmpeg.is_empty() or str((ocr as RefCounted).get("state")) == "missing": return
	var picture := best_picture_choice(rows)
	if not picture.is_empty() and bool(settings.ocr_tracks):
		pony_ocr.start_track(ffmpeg, current, picture, info, at, ocr, Mods.data_folder("watch_party"))
		pony_track = str(picture.get("label", "")).replace(" · (picture)", "").replace("(picture)", "").strip_edges() + " picture subtitles, read with OCR"
	elif bool(settings.ocr_live) and bool(info.get("video", true)):
		pony_ocr.start_live(ocr, Mods.data_folder("watch_party"))
		_live_clock = 1.0

## The picture subtitle track to read with OCR: English first, a full track (not "forced").
static func best_picture_choice(rows: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -100
	for row: Dictionary in rows:
		if str(row.get("kind", "")) != "picture": continue
		var label := str(row.get("label", "")).to_lower()
		var score := (4 if "english" in label else 0) - (6 if "forced" in label else 0)
		if score > best_score:
			best_score = score
			best = row
	return best

## Each frame: the OCR reader hears where playback is; the live way is offered the decoded frame on
## the screen every LIVE_EVERY seconds (never the camera's view). Once it has read a line, the
## ponies count as following the film.
func _update_ocr(delta: float) -> void:
	if pony_ocr.mode.is_empty() or source != "video" or not is_instance_valid(player): return
	var at := float(player.position())
	pony_ocr.set_playhead(at)
	# The track could not be drawn at all (ffmpeg's error): the ponies know only the title after all.
	if pony_ocr.mode == "track" and not pony_ocr.problem.is_empty() and not pony_track.is_empty() and not pony_ocr.found_any(): pony_track = ""
	if pony_ocr.mode != "live" or player.state != "playing": return
	_live_clock -= delta
	if _live_clock > 0.0: return
	_live_clock = PICTURE_SUBS.LIVE_EVERY
	var frame: Image = player.picture_now()
	if frame != null: pony_ocr.offer(frame, at, _film_rect(frame.get_size()))
	if pony_track.is_empty() and pony_ocr.found_any(): pony_track = "subtitles in the picture, read with OCR"

## Where the film is in a decoded frame: all of it with Fill, else fitted inside black bars
## (media_player.gd _video_arguments scales by the stored size, as here).
func _film_rect(size: Vector2i) -> Rect2i:
	var film := Vector2(float(info.get("width", 0)), float(info.get("height", 0)))
	if film.x <= 0.0 or film.y <= 0.0 or bool(player.fill): return Rect2i(Vector2i.ZERO, size)
	var fit := minf(size.x / film.x, size.y / film.y)
	var shown := Vector2i(int(film.x * fit), int(film.y * fit))
	return Rect2i((size - shown) / 2, shown)

## The TV menu's word on the OCR ("" when it is not in use).
func ocr_note() -> String:
	if source != "video" or current.is_empty(): return ""
	if pony_ocr.mode == "track":
		if not pony_ocr.problem.is_empty() and not pony_ocr.found_any(): return "The picture subtitles could not be read (%s)." % pony_ocr.problem
		return "all read" if pony_ocr.progress >= 0.99 else "%d%% read so far, ahead of where you are" % int(pony_ocr.progress * 100.0)
	if pony_ocr.mode == "live": return "Looking for subtitles in the picture with OCR every 2 seconds."
	if _pony_shared or not pony_track.is_empty(): return ""
	var rows := subtitle_choices()
	if best_picture_choice(rows).is_empty(): return ""
	var hub_node := hub()
	var ocr: Variant = hub_node.get("ocr") if hub_node != null else null
	if ocr is RefCounted and str((ocr as RefCounted).get("state")) == "missing":
		return "Only its title: its subtitles are pictures, and there is no OCR to read them. " + str((ocr as RefCounted).get("problem"))
	return ""

## Who the ponies read: the shown text track, else their own text reader, else the OCR.
func _pony_reader() -> RefCounted:
	if _pony_shared: return subtitles
	return pony_ocr if not pony_ocr.mode.is_empty() else pony_lines

## The text subtitle choice ponies follow best: English, a full track (not "forced"), a file
## beside the video before one inside it. {} when there is no text subtitle at all.
static func best_pony_choice(rows: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -100
	for row: Dictionary in rows:
		if str(row.get("kind", "")) != "text": continue
		var label := str(row.get("label", "")).to_lower()
		# A file's label is "File: " plus what follows the video's name: "en", "eng.sdh", or its whole name.
		var extra := label.trim_prefix("file: ")
		var english: bool = "english" in label or (row.has("path") and (extra in ["en", "eng"] or extra.begins_with("en.") or extra.begins_with("eng.")))
		var score := (4 if english else 0) + (2 if row.has("path") else 0) - (6 if "forced" in label else 0)
		if score > best_score:
			best_score = score
			best = row
	return best

## Subtitle lines the ponies heard between two times in the video: [[start seconds, text]]. On a
## web page: the pages opened in that time, as lines.
func heard(from: float, to: float) -> Array:
	if source == "web" and is_instance_valid(web) and not (web.get("tube") as Dictionary).is_empty():
		return web.call("tube_lines", from, to)
	if source == "web":
		var pages: Array = []
		if is_instance_valid(web):
			for row: Array in web.get("history"):
				if float(row[0]) >= from and float(row[0]) <= to: pages.append(row)
		return pages
	if source != "video": return []
	return _pony_reader().lines_between(from, to)

## Somebody in the video is talking right now (a subtitle line is up).
func talking_now() -> bool:
	if source == "web" and is_instance_valid(web): return bool(web.call("tube_talking"))
	if source != "video" or not is_instance_valid(player): return false
	return not _pony_reader().text_at(float(player.position())).is_empty()

## Video seconds of the latest cut in the picture (-1 when none since it started playing).
func last_cut() -> float:
	return float(player.last_cut) if source == "video" and is_instance_valid(player) else -1.0

## The frame a pony is shown (watch_company.gd): the last of the shot before a cut that came in the
## last `recent` seconds (the scene her lines are from), else the picture on screen now. On a web
## page, the page as it looks.
func picture_for_pony(recent: float) -> Image:
	# A page is only ever sent to a vision API when the player allows pictures of it.
	if source == "web": return web.call("image") as Image if web_shared() and web_level() == "pictures" else null
	if source == "slides":
		# A GIF or WebM playing in the slideshow is a picture from the player; a still is the slide.
		if _moving != "" and is_instance_valid(player) and str(player.state) == "playing": return player.picture_now()
		return _slide_shown.get_image() if _slide_shown != null else null
	if source != "video" or not is_instance_valid(player): return null
	var cut := float(player.last_cut)
	var before: Image = player.picture_before_cut()
	if before != null and cut >= 0.0 and float(player.position()) - cut <= recent: return before
	return player.picture_now()

## A little of the page's own words, for ponies watching along ("" off the web or when private).
func page_text() -> String:
	return str(web.get("page_text")) if web_shared() and is_instance_valid(web) else ""

func _remember_tracks() -> void:
	var settings: RefCounted = _settings()
	if settings != null: settings.remember_tracks(current, audio_track(), subtitle_key)

func _update_subtitle() -> void:
	if not is_instance_valid(subtitle_label): return
	if source != "video" or not is_instance_valid(player) or player.state not in ["playing", "paused"] or str(subtitles.choice.get("kind", "off")) != "text":
		subtitle_label.text = ""
		return
	subtitle_label.text = subtitles.text_at(float(player.position()))

# --- playing ------------------------------------------------------------------------------------

## Probes `path` on a worker thread, then plays it from where it was left (or from `at`).
func play_file(path: String, at := -1.0) -> void:
	if not active: return
	touched()
	_end_wake(true)
	var hub_node := hub()
	var ffmpeg: String = str(hub_node.get("ffmpeg")) if hub_node != null else ""
	if ffmpeg.is_empty():
		_note(str(hub_node.call("ffmpeg_note")) if hub_node != null else "Watch Party is not running.")
		return
	if source == "video" and is_instance_valid(player) and player.state in ["playing", "paused"]: _keep_place(true)
	if source in ["slides", "web"]:
		if is_instance_valid(slides): slides.stop()
		_close_web()
		source = ""
	if hub_node.has_method("tv_playing"): hub_node.tv_playing(self)
	_switched_off = false
	_finish_probe()
	subtitles.stop()
	pony_lines.stop()
	pony_ocr.stop()
	_probe_for = path; _probe_at = at
	current = path
	_remember_on("video")
	_note("Tuning in: " + path.get_file().get_basename())
	_probe = Thread.new()
	_probe.start(_run_probe.bind(TOOLS.ffprobe_for(ffmpeg), path, ffmpeg))

func _run_probe(ffprobe: String, path: String, ffmpeg: String) -> void:
	var result := TOOLS.probe(ffprobe, path)
	result.tonemap = bool(result.get("hdr", false)) and TOOLS.can_tonemap(ffmpeg)
	call_deferred("_probed", path, result)

func _probed(path: String, result: Dictionary) -> void:
	_finish_probe()
	if not active or path != _probe_for or not is_instance_valid(player): return
	if not bool(result.get("ok", false)):
		_note(str(result.get("error", "That file cannot be played.")))
		return
	info = result
	var hub_node := hub()
	player.ffmpeg = str(hub_node.get("ffmpeg")) if hub_node != null else "ffmpeg"
	player.tonemap = bool(result.get("tonemap", false))
	var settings: RefCounted = _settings()
	var length: float = float(result.get("duration", 0.0))
	var start: float = _probe_at if _probe_at >= 0.0 else (float(settings.resume_at(path, length)) if settings != null else 0.0)
	var sound := not (result.get("audio", []) as Array).is_empty()
	var chosen: Dictionary = settings.tracks_for(path) if settings != null else {"audio": 0, "subtitle": "off"}
	var audio := clampi(int(chosen.audio), 0, maxi(0, (result.get("audio", []) as Array).size() - 1))
	subtitle_key = str(chosen.subtitle)
	print("[watch_party] playing %s: %.0f s long, picture %s%s, %d sound track(s), %d subtitle track(s)" % [path.get_file(), length,
		"yes" if bool(result.get("video", true)) else "no", " (HDR, tonemapped)" if player.tonemap else (" (HDR, no tonemap: this ffmpeg lacks zscale)" if bool(result.get("hdr", false)) else ""),
		(result.get("audio", []) as Array).size(), (result.get("subtitles", []) as Array).size()])
	if settings != null: player.fill = bool(settings.fill)
	source = "video"
	_apply_subtitle(false)
	if not player.play(path, start, length, sound, audio):
		source = ""
		_note(str(player.error))
		return
	_restart_subtitles()
	_remember = REMEMBER_EVERY
	_show_caption()

func _finish_probe() -> void:
	if _probe != null and _probe.is_started(): _probe.wait_to_finish()
	_probe = null

func _on_picture(texture: ImageTexture) -> void:
	if _material == null: return
	if source == "slides" and not _moving.is_empty():
		_slide_average = player.average
		if _moving_fresh:
			# Its first frame fades in like a still; a loop starting again just carries on.
			_moving_fresh = false
			_slide_in(texture)
			return
		_show_texture(texture)
		return
	if source != "video": return
	_material.set_shader_parameter("lines", float(player.height))
	_material.set_shader_parameter("columns", float(player.width))
	_show_texture(texture)

## Puts `texture` on the screen (the last one becomes `previous`, for a crossfade) and powers the
## screen on if it was dark.
func _show_texture(texture: Texture2D) -> void:
	if _material == null: return
	if texture != _shown:
		if _shown != null: _material.set_shader_parameter("previous", _shown)
		_material.set_shader_parameter("picture", texture)
		_shown = texture
	if source != "slides": _material.set_shader_parameter("fade", 1.0)
	if source != "video":
		# The scanlines follow the set's own picture size (a video sets them from its frames).
		var pixels: Vector2i = spec.picture
		_material.set_shader_parameter("lines", float(pixels.y))
		_material.set_shader_parameter("columns", float(pixels.x))
	_apply_crt()
	if not _powered: _power_on()

func _power_on() -> void:
	_powered = true
	if _material == null: return
	if _power_tween != null: _power_tween.kill()
	_material.set_shader_parameter("has_picture", 1.0)
	if str(spec.power) != "crt":
		# A flatscreen's panel simply fades up.
		_power_tween = create_tween()
		_power_tween.tween_method(_set_level, 0.0, 1.0, FADE_ON_SECONDS).set_ease(Tween.EASE_OUT)
		return
	# The tube warms up: a bright line across the middle opens out into the picture.
	_material.set_shader_parameter("aperture", Vector2(0.0, 0.004))
	_material.set_shader_parameter("flash", 2.0)
	_power_tween = create_tween()
	_power_tween.tween_method(_set_aperture_width, 0.0, 0.5, POWER_ON_SECONDS * 0.3)
	_power_tween.tween_method(_set_aperture_height, 0.004, 0.5, POWER_ON_SECONDS * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_power_tween.parallel().tween_method(_set_flash, 2.0, 0.0, POWER_ON_SECONDS * 0.8)

## The vintage picture collapses to a line, then to a fading dot; a flatscreen fades out. Without
## `animate` (the set is being put away) it is dark at once.
func _power_off(animate: bool) -> void:
	if not _powered and animate: return
	_powered = false
	_shown = null
	if _material == null: return
	if _power_tween != null: _power_tween.kill()
	if not animate or not is_inside_tree():
		_material.set_shader_parameter("has_picture", 0.0)
		_material.set_shader_parameter("flash", 0.0)
		_material.set_shader_parameter("level", 0.0)
		return
	_power_tween = create_tween()
	if str(spec.power) != "crt":
		_power_tween.tween_method(_set_level, 1.0, 0.0, FADE_OFF_SECONDS).set_ease(Tween.EASE_IN)
		_power_tween.tween_callback(_dark)
		return
	_power_tween.tween_method(_set_flash, 0.0, 1.2, POWER_OFF_SECONDS * 0.3)
	_power_tween.parallel().tween_method(_set_aperture_height, 0.5, 0.004, POWER_OFF_SECONDS * 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_power_tween.tween_method(_set_line_width, 0.5, 0.004, POWER_OFF_SECONDS * 0.3)
	_power_tween.tween_method(_set_flash, 1.2, 0.0, POWER_OFF_SECONDS * 0.25)
	_power_tween.tween_callback(_dark)

func _dark() -> void:
	if _material != null and not _powered: _material.set_shader_parameter("has_picture", 0.0)

func _set_level(amount: float) -> void:
	if _material != null: _material.set_shader_parameter("level", amount)

## The power-on line growing across (it is thin while it does).
func _set_aperture_width(width: float) -> void:
	if _material != null: _material.set_shader_parameter("aperture", Vector2(width, 0.004))

## The power-off line shrinking to a dot.
func _set_line_width(width: float) -> void:
	if _material != null: _material.set_shader_parameter("aperture", Vector2(width, 0.004))

func _set_aperture_height(height: float) -> void:
	if _material != null: _material.set_shader_parameter("aperture", Vector2(0.5, height))

func _set_flash(amount: float) -> void:
	if _material != null: _material.set_shader_parameter("flash", amount)

## The colour of what is on screen now.
func _picture_average(delta: float) -> Color:
	if _waking > 0.0: return Color(0.42, 0.42, 0.44) if str(spec.kind) == "crt" else Color(0.03, 0.04, 0.12)
	match source:
		"video": return player.average if is_instance_valid(player) else Color.BLACK
		"slides": return _slide_average
		"web":
			_web_sample -= delta
			if _web_sample <= 0.0 and is_instance_valid(web):
				_web_sample = WEB_AVERAGE_EVERY
				_web_average = web.call("average")
			return _web_average
	return Color.BLACK

## The set's light follows the picture's average colour and brightness, softly flickering;
## it fades out when nothing is showing.
func _update_glow(delta: float) -> void:
	if not is_instance_valid(_glow): return
	if _light_mode == "off":
		_glow_energy = 0.0
		_glow.visible = false
		return
	# "near" lights only what is close in front of the set (the ponies on the floor before it,
	# not the whole room): fewer lit pixels for slower graphics cards.
	_glow.spot_range = GLOW_NEAR_RANGE if _light_mode == "near" else GLOW_RANGE
	var showing: bool = _powered and (_waking > 0.0 or source in ["slides", "web"] or (is_instance_valid(player) and player.state in ["playing", "paused"]))
	var target_energy := 0.0
	if showing:
		var picture: Color = _picture_average(delta)
		var bright := clampf(picture.get_luminance(), 0.0, 1.0)
		# A little more colour than the average, so a blue scene reads as blue on the walls. The
		# colour is kept at full strength and the brightness goes only into the energy: dimming
		# both squared it, so only very bright scenes lit the room (playtest 2026-11-03).
		var tint := Color.from_hsv(picture.h, clampf(picture.s * 1.25, 0.0, 0.85), 1.0)
		_glow_colour = _glow_colour.lerp(tint, clampf(delta * GLOW_FOLLOW, 0.0, 1.0))
		# Films are mostly mid to dark: lift the middle (0.2 gives 0.43, 0.6 gives 0.9) and keep
		# dark scenes dim. A flatscreen is a bigger, brighter panel.
		var lift := 1.0 - pow(1.0 - bright, GLOW_LIFT)
		target_energy = GLOW_ENERGY * (0.05 + 0.95 * lift) * (1.0 if str(spec.kind) == "crt" else 1.35)
	_glow_energy = lerpf(_glow_energy, target_energy, clampf(delta * GLOW_FOLLOW, 0.0, 1.0))
	if _glow_energy < 0.01:
		_glow.visible = false
		return
	_glow_time += delta
	# A tube flickers a little; a panel holds steady.
	var flicker := 1.0 + 0.035 * sin(_glow_time * 23.0) + 0.025 * sin(_glow_time * 61.0 + 1.3) if str(spec.kind) == "crt" else 1.0
	_glow.visible = true
	_glow.light_color = _glow_colour
	_glow.light_energy = _glow_energy * flicker

func _update_power_light() -> void:
	if not is_instance_valid(_power_light): return
	var on: bool = active and (_waking > 0.0 or _probe != null or source in ["slides", "web"] or (is_instance_valid(player) and player.state in ["playing", "paused"]))
	if on == _power_light_on: return
	_power_light_on = on
	_power_light.material_override = model.call("power_light_material", on)

func _on_problem(text: String) -> void:
	_note("No picture: " + text)

func _on_finished() -> void:
	if source == "slides":
		_moving_done()
		return
	var settings: RefCounted = _settings()
	if settings != null and not current.is_empty():
		settings.remember(current, 0.0)
		settings.save()
	subtitles.stop()
	pony_lines.stop()
	pony_ocr.stop()
	source = ""
	_power_off(true)
	if is_instance_valid(player) and not str(player.error).is_empty(): _note("Could not play: " + str(player.error))
	else: _show_caption()

## Saves where the current file is; `write` also writes the settings file now.
func _keep_place(write: bool) -> void:
	var settings: RefCounted = _settings()
	if settings == null or source != "video" or current.is_empty() or not is_instance_valid(player) or player.state in ["idle", "ended"]: return
	settings.remember(current, float(player.position()))
	if write: settings.save()

## "muted" or the volume in dB, for captions and the remote's card.
static func volume_text(db: float) -> String:
	return "muted" if db <= MUTED_DB else str(roundi(db))

func _apply_volume() -> void:
	var settings: RefCounted = _settings()
	if is_instance_valid(speaker) and settings != null: speaker.volume_db = float(settings.volume_db) + duck_db

func set_duck(db: float) -> void:
	duck_db = db
	_apply_volume()

func _settings() -> RefCounted:
	var hub_node := hub()
	return hub_node.get("settings") as RefCounted if hub_node != null else null

## What is on, for the menu, the remote and the ponies: {title, state, position, duration,
## volume_db, path, mode}. mode is "video", "slides", "web" or "". A web page the ponies may see
## is "playing", its path "web:<n>" (one per time the browser opened) and its position the
## seconds since; one they may not see is "private". A slideshow is "slides".
func status() -> Dictionary:
	var settings: RefCounted = _settings()
	var volume := float(settings.volume_db) if settings != null else 0.0
	if source == "web" and is_instance_valid(web):
		# A YouTube video the ponies may see: like a video of the library, captions as subtitles.
		var tube: Dictionary = web.get("tube")
		if web_shared() and not tube.is_empty():
			return {"title": str(tube.title), "channel": str(tube.channel), "path": "yt:" + str(tube.id), "url": str(web.call("url")), "mode": "web",
				"youtube": true, "ad": bool(tube.ad), "captions": bool(tube.captions), "state": "playing" if bool(tube.playing) else "paused",
				"position": float(tube.time), "duration": float(tube.length), "volume_db": volume}
		return {"title": str(web.call("title")), "path": "web:%d" % _web_session, "url": str(web.call("url")), "mode": "web",
			"state": "playing" if web_shared() else "private", "position": float(web.call("position")), "duration": 0.0, "volume_db": volume}
	if source == "slides":
		return {"title": "Photo slideshow", "path": "slides:%d" % _slides_run, "mode": "slides", "state": "slides", "pictures": _slide_count,
			"position": (Time.get_ticks_msec() - _slides_started) / 1000.0, "duration": 0.0, "volume_db": volume}
	var state := "idle"
	var position := 0.0
	if is_instance_valid(player):
		state = str(player.state)
		position = float(player.position())
	if _probe != null: state = "tuning"
	return {"title": current.get_file().get_basename(), "path": current, "mode": "video" if source == "video" else "", "state": state, "position": position,
		"duration": float(info.get("duration", 0.0)), "volume_db": volume}

# --- caption ------------------------------------------------------------------------------------

func _note(text: String) -> void:
	if not is_instance_valid(caption): return
	caption.text = text
	caption.visible = true
	_caption_until = Time.get_ticks_msec() / 1000.0 + CAPTION_SECONDS * 1.5

func _show_caption() -> void:
	_caption_until = Time.get_ticks_msec() / 1000.0 + CAPTION_SECONDS
	_update_caption(true)

func _update_caption(force := false) -> void:
	if not is_instance_valid(caption): return
	if _waking > 0.0 or _armed:
		caption.visible = false
		return
	var now := Time.get_ticks_msec() / 1000.0
	var hub_node := hub()
	if source in ["slides", "web"]:
		# A page or the slideshow has the whole screen; a caption only for a moment after a change.
		if now >= _caption_until and not force:
			caption.visible = false
			return
		if not force: return
		caption.visible = true
		var settings: RefCounted = _settings()
		caption.text = ("Photo slideshow · any button stops it" if source == "slides" else "Web · click the screen to use it") + " · vol " + volume_text(float(settings.volume_db) if settings != null else 0.0)
		return
	var state := str(player.state) if is_instance_valid(player) else "idle"
	var idle := state in ["idle", "ended"] and _probe == null
	if idle:
		# An idle set always says how to start it.
		if now < _caption_until and not force: return
		var ready := hub_node != null and not str(hub_node.get("ffmpeg")).is_empty()
		caption.text = ("No signal\nUse the TV remote to watch" if ready else
			(str(hub_node.call("ffmpeg_note")) if hub_node != null else "Watch Party is off."))
		caption.visible = true
		return
	if now >= _caption_until and not force:
		caption.visible = false
		return
	if not force and now < _caption_until and caption.visible and state != "playing" and state != "paused": return
	caption.visible = true
	var status_now := status()
	var line := "%s %s" % ["||" if state == "paused" else ">", status_now.title]
	var time := clock(float(status_now.position))
	if float(status_now.duration) > 0.0: time += " / " + clock(float(status_now.duration))
	caption.text = "%s\n%s · vol %s" % [line, time, volume_text(float(status_now.volume_db))]

static func clock(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	var hours := total / 3600
	var minutes := (total / 60) % 60
	var secs := total % 60
	return "%d:%02d:%02d" % [hours, minutes, secs] if hours > 0 else "%d:%02d" % [minutes, secs]
