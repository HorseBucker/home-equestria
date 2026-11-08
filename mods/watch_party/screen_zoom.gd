extends Node
## Desktop: Home zooms the view right up to a television's screen (the one in TV mode, else the one on
## that Anon is looking toward), so it can be watched from the couch or the bed across the room.
## Home again or Escape goes back. It works over anything on the screen: a film, the slideshow, a
## web page (in TV mode Home zooms unless a text box on the page has the keys: web_view.gd
## wants_text; Escape there leaves TV mode first, a second Escape the zoom). Zoomed in, a left
## click uses the screen wherever the crosshair was (tv_controls.gd _use_screen: TV mode on a page,
## the slideshow stops), and the game's corner map is hidden.
## The view only: a second camera eases in front of the screen (ZOOM_SECONDS) while an
## AudioListener3D stays on Anon's own head, so every sound stays where it was (a pony beside him
## still sounds beside him, the set across the room still sounds across the room). Walking and
## looking around are held while zoomed (the body's controls_locked, as in TV mode); the remote
## still works (tv_controls.gd). VR has no zoom: lean in.
## Zoomed in, a pony's words always go to the caption at the bottom of the view (playtest
## 2026-11-07: she was looked at when he zoomed, so her words stayed over her head, out of sight):
## the game's speech (world/ai/overhead_dialogue.gd, under the voice HUD) is set to "caption" while
## zoomed and given back its own setting after.
## A child of tv_controls.gd, so its _input comes before the game's.

## Home (dev 2026-11-06: Page Up and Page Down size the ponies, world/game.gd). The game uses Home
## only to recentre a headset in the desktop headset view (player/desktop_player.gd), and the zoom
## leaves it alone there. Taken only when there is a screen to zoom to; Y is left to other mods (unfplap).
## Home (dev 2026-11-07: Home only, no choice).
func zoom_key() -> int:
	return KEY_HOME

## Its name on the key cap, for the hints.
func key_name() -> String:
	return "Home"
## How much of the view's height (or width, whichever is tighter) the screen fills.
const FILL := 0.86
const ZOOM_SECONDS := 0.35
## A set this far away at most, within this angle of where Anon is looking, can be zoomed to.
const REACH := 20.0
const LOOK_DOT := 0.6
const OVERHEAD := preload("res://world/ai/overhead_dialogue.gd")
const SPEECH_META := "watch_party_speech_text"
const CAMERA_PROPERTIES := ["environment", "attributes", "compositor", "cull_mask", "fov", "far", "keep_aspect", "projection"]

var controls: Node
## The set zoomed to, or null.
var tv: Node3D
var _camera: Camera3D
var _listener: AudioListener3D
var _main: Camera3D
## 0 at Anon's eye, 1 at the screen; _going is where it is heading.
var _amount := 0.0
var _going := 0.0
var _locked_body: Node
var _hint: CanvasLayer
## The game's corner map, hidden while zoomed in (screen_input.gd hides it in TV mode too).
var hidden_map: CanvasLayer
## The pony speech set to the caption while zoomed (weak refs), to give back its own setting.
var _captioned: Array = []

func _ready() -> void:
	_hint = CanvasLayer.new(); _hint.name = "TvZoomHint"
	_hint.layer = 30
	var label := Label.new(); label.name = "Text"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position = Vector2(-240, 40)
	label.size = Vector2(480, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(label)
	_hint.visible = false
	add_child(_hint)

func _exit_tree() -> void:
	_end()

## Zoomed in (or on the way in).
func on() -> bool:
	return is_instance_valid(tv) and _going > 0.0

## This node holds the body's controls (the remote keeps working then: tv_controls.gd).
func holding() -> bool:
	return is_instance_valid(_locked_body)

func _inventory() -> Node:
	return controls.call("_inventory") if is_instance_valid(controls) else null

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo: return
	var screen: Variant = controls.get("screen_input") if is_instance_valid(controls) else null
	if is_instance_valid(screen) and bool((screen as Node).call("active")): return   # screen_input.gd asks key()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	if _headset_view(): return
	if key.physical_keycode == KEY_ESCAPE and on():
		zoom_out()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == zoom_key() and _plain(key):
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit: return
		if on(): zoom_out()
		elif not zoom_in(_looked_at()): return
		get_viewport().set_input_as_handled()

## In TV mode (screen_input.gd, before the key goes to the page): true when it was the zoom key.
func key(event: InputEventKey, target: Node3D) -> bool:
	if not event.pressed or event.echo or event.physical_keycode != zoom_key() or not _plain(event): return false
	var web: Variant = target.get("web") if is_instance_valid(target) and str(target.get("source")) == "web" else null
	# A real text field only: a page whose focus is in a video frame still zooms (playtest
	# 2026-11-07: Home did nothing in TV mode).
	if is_instance_valid(web) and (web as Node).has_method("typing_text") and bool((web as Node).call("typing_text")): return false
	if on(): zoom_out()
	else: zoom_in(target)
	return true

## The desktop headset view: there Home recentres the headset (player/desktop_player.gd).
func _headset_view() -> bool:
	var inventory := _inventory()
	var body: Variant = inventory.get("player_body") if inventory != null else null
	return is_instance_valid(body) and bool((body as Node).get("headset_view"))

static func _plain(key: InputEventKey) -> bool:
	return not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed and not key.shift_pressed

## The set that is on that Anon is looking toward, its screen facing him; null when none.
func _looked_at() -> Node3D:
	var inventory := _inventory()
	var camera: Camera3D = inventory.get("camera") as Camera3D if inventory != null else null
	if not is_instance_valid(camera) or not bool(inventory.get("_desktop")): return null
	var forward := -camera.global_basis.z.normalized()
	var best: Node3D = null
	var best_dot := LOOK_DOT
	for node: Node in get_tree().get_nodes_in_group("watch_tvs"):
		var set_node := node as Node3D
		if set_node == null or not bool(set_node.get("active")) or not set_node.is_inside_tree(): continue
		var centre := _centre(set_node)
		var to := centre - camera.global_position
		if to.length() > REACH or to.length() < 0.05: continue
		if set_node.global_basis.z.dot(-to) <= 0.0: continue   # its back to him
		var dot := forward.dot(to.normalized())
		if dot > best_dot:
			best_dot = dot
			best = set_node
	return best

static func _centre(set_node: Node3D) -> Vector3:
	var spec: Dictionary = set_node.get("spec")
	var centre: Vector2 = spec.centre
	return set_node.to_global(Vector3(centre.x, centre.y, float(spec.z)))

func zoom_in(target: Node3D) -> bool:
	var inventory := _inventory()
	var main: Camera3D = inventory.get("camera") as Camera3D if inventory != null else null
	if not is_instance_valid(target) or not is_instance_valid(main) or not main.is_inside_tree(): return false
	tv = target
	_main = main
	if not is_instance_valid(_camera):
		_camera = Camera3D.new(); _camera.name = "WatchPartyZoomCamera"
		_camera.top_level = true
		add_child(_camera)
		_listener = AudioListener3D.new(); _listener.name = "WatchPartyZoomListener"
		_listener.top_level = true
		add_child(_listener)
	for property: String in CAMERA_PROPERTIES:
		var value: Variant = main.get(property)
		if value != null: _camera.set(property, value)
	_camera.near = 0.02
	_listener.global_transform = main.global_transform
	_listener.make_current()
	_camera.global_transform = main.global_transform
	_camera.make_current()
	_going = 1.0
	(_hint.get_node("Text") as Label).text = "Zoomed in · %s or Esc steps back · Click to use a web page" % key_name()
	_hint.visible = true
	_hide_map()
	print("[watch_party] zoomed in on the screen")
	return true

func zoom_out() -> void:
	if not is_instance_valid(tv): return
	_going = 0.0
	_hint.visible = false

func _process(delta: float) -> void:
	if not is_instance_valid(tv): return
	if not is_instance_valid(_main) or not _main.is_inside_tree() or not tv.is_inside_tree() or not bool(tv.get("active")):
		_end()
		return
	_amount = move_toward(_amount, _going, delta / ZOOM_SECONDS)
	_listener.global_transform = _main.global_transform
	if _going > 0.0:
		_hold_body()
		_speech_to_caption()
	if _amount <= 0.0 and _going <= 0.0:
		_end()
		return
	var eased := ease(_amount, -2.0)
	_camera.global_transform = _main.global_transform.interpolate_with(_close_view(), eased)

## Where the camera stands to have the screen fill the view: straight out in front of its centre.
func _close_view() -> Transform3D:
	var spec: Dictionary = tv.get("spec")
	var size: Vector2 = spec.size
	var centre := _centre(tv)
	var normal := tv.global_basis.z.normalized()
	var half_v := deg_to_rad(_camera.fov) * 0.5
	var view := get_viewport().get_visible_rect().size
	var aspect := view.x / maxf(view.y, 1.0)
	var half_h := atan(tan(half_v) * aspect)
	var scale := tv.global_basis.get_scale()
	var distance := maxf(size.y * scale.y / FILL * 0.5 / tan(half_v), size.x * scale.x / FILL * 0.5 / tan(half_h))
	return Transform3D(Basis.IDENTITY, centre + normal * distance).looking_at(centre, tv.global_basis.y.normalized())

## Walking and looking around wait while zoomed (unless TV mode already holds them).
func _hold_body() -> void:
	if is_instance_valid(_locked_body): return
	var inventory := _inventory()
	var body: Variant = inventory.get("player_body") if inventory != null else null
	if is_instance_valid(body) and not bool((body as Node).get("controls_locked")):
		(body as Node).set("controls_locked", true)
		_locked_body = body

## Back to Anon's own eyes and ears.
func _end() -> void:
	var was := is_instance_valid(tv) or _amount > 0.0
	tv = null
	_going = 0.0
	_amount = 0.0
	if is_instance_valid(_hint): _hint.visible = false
	_show_map()
	if is_instance_valid(_main) and _main.is_inside_tree(): _main.make_current()
	if is_instance_valid(_camera): _camera.clear_current(false)
	if is_instance_valid(_listener): _listener.clear_current()
	if is_instance_valid(_locked_body): _locked_body.set("controls_locked", false)
	_locked_body = null
	_speech_back()
	if was: print("[watch_party] zoomed back out")

## Whatever a pony says now shows in the caption at the bottom (each new line is a new node, so
## this is checked every frame while zoomed).
func _speech_to_caption() -> void:
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var hud: Variant = director.get("hud") if is_instance_valid(director) else null
	if not hud is Node or not is_instance_valid(hud): return
	for child: Node in (hud as Node).get_children():
		if child is OVERHEAD and str(child.get("speech_text")) != "caption":
			child.set_meta(SPEECH_META, child.get("speech_text"))
			child.set("speech_text", "caption")
			_captioned.append(weakref(child))

func _speech_back() -> void:
	for ref: WeakRef in _captioned:
		var node: Variant = ref.get_ref()
		if is_instance_valid(node) and (node as Node).has_meta(SPEECH_META):
			(node as Node).set("speech_text", (node as Node).get_meta(SPEECH_META))
			(node as Node).remove_meta(SPEECH_META)
	_captioned.clear()

func _hide_map() -> void:
	var game: Variant = Mods.game
	var map: Variant = (game as Node).get("world_map") if is_instance_valid(game) else null
	if map is CanvasLayer and (map as CanvasLayer).visible:
		(map as CanvasLayer).visible = false
		hidden_map = map

## Back on, unless TV mode still wants it hidden (screen_input.gd takes it over then).
func _show_map() -> void:
	var screen: Variant = controls.get("screen_input") if is_instance_valid(controls) else null
	if is_instance_valid(hidden_map):
		if is_instance_valid(screen) and bool((screen as Node).call("active")) and (screen as Node).get("_hidden_map") == null:
			(screen as Node).set("_hidden_map", hidden_map)
		else:
			hidden_map.visible = true
	hidden_map = null
