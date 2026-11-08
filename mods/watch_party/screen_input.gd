extends Node
## Using a set's screen directly: the web browser, and stopping the slideshow.
## - Desktop "TV mode": clicking a screen that shows a page (tv_controls.gd) hands the mouse and
##   keyboard to it. The mouse moves a pointer drawn on the screen, its buttons and wheel click and
##   scroll the page, the keyboard types into it; Escape gives control straight back to the game.
##   The player cannot move or look around meanwhile (the body's controls_locked) and a small hint
##   at the top of the view says how to leave.
## - VR: a hand pointing at such a screen (empty, or holding the TV remote) shows a laser; the
##   trigger clicks, the thumbstick scrolls (walking and turning pause while the laser is on the
##   screen), and pointing away gives the controls back. A keyboard floats up in front of the
##   player when a text box on the page takes the focus (web_view.gd typing), or on B/Y; a real
##   keyboard types too while the laser is on the screen or the floating keyboard is up.
## A child of tv_controls.gd, so its _input runs before the game's (see there).

const COMMON := preload("res://mods/watch_party/screen_common.gd")
const KEYBOARD := preload("res://mods/watch_party/vr_keyboard.gd")
const ITEM_LAYER := 1 << 17
## How far the mouse moves the pointer: one pixel of mouse travel in screen heights.
const POINTER_SPEED := 1.0 / 1100.0
const LASER_REACH := 8.0
const TRIGGER_DOWN := 0.6
const TRIGGER_UP := 0.4
## Thumbstick scrolling: wheel notches per second at full tilt.
const STICK_NOTCHES := 9.0
const STICK_DEADZONE := 0.25

var controls: Node
## The set in desktop TV mode, else null.
var tv: Node3D
var _uv := Vector2(0.5, 0.5)
var _locked_body: Node
var _hint: CanvasLayer
## VR: the side whose laser is on a screen ("" when none), the set it points at, trigger state.
var pointing_side := ""
var _vr_tv: Node3D
var _vr_pressed := false
var _wheel_rest := 0.0
var _laser: MeshInstance3D
var _keyboard: Node3D
var _menu_button_was := false
var _keyboard_tv: Node3D
## The game's map in the corner, hidden while in TV mode (it sat over the page's corner).
var _hidden_map: CanvasLayer

func _ready() -> void:
	_hint = CanvasLayer.new(); _hint.name = "TvModeHint"
	_hint.layer = 30
	var label := Label.new()
	label.name = "Text"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position = Vector2(-240, 14)
	label.size = Vector2(480, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(label)
	_hint.visible = false
	add_child(_hint)

func _exit_tree() -> void:
	leave()
	_vr_release()

# --- desktop TV mode ----------------------------------------------------------------------------

func active() -> bool:
	return is_instance_valid(tv)

## Hands the mouse and keyboard to `target`'s screen, the pointer starting at `uv`.
func enter(target: Node3D, uv: Vector2) -> void:
	if not is_instance_valid(target): return
	if active() and tv != target: leave()
	tv = target
	_uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
	var body := _body()
	if is_instance_valid(body) and not bool(body.get("controls_locked")):
		body.set("controls_locked", true)
		_locked_body = body
	var zoom: Variant = controls.get("zoom") if is_instance_valid(controls) else null
	var zoom_name := str((zoom as Node).call("key_name")) if is_instance_valid(zoom) else "Home"
	(_hint.get_node("Text") as Label).text = "TV mode · Esc returns to the game · %s zooms in · Ctrl + wheel zooms the page" % zoom_name
	_hint.visible = true
	var map := _world_map()
	if map != null and map.visible:
		map.visible = false
		_hidden_map = map
	tv.call("set_cursor", _uv)
	tv.call("pointer_move", _uv)
	print("[watch_party] TV mode on")

## Back to the game at once.
func leave() -> void:
	if is_instance_valid(tv): tv.call("set_cursor", Vector2(-1, -1))
	if tv != null: print("[watch_party] TV mode off")
	tv = null
	if is_instance_valid(_locked_body): _locked_body.set("controls_locked", false)
	_locked_body = null
	if is_instance_valid(_hint): _hint.visible = false
	if is_instance_valid(_hidden_map):
		# Still zoomed in (screen_zoom.gd): the map stays hidden until the zoom ends.
		var zoom: Variant = controls.get("zoom") if is_instance_valid(controls) else null
		if is_instance_valid(zoom) and bool((zoom as Node).call("on")) and (zoom as Node).get("hidden_map") == null:
			(zoom as Node).set("hidden_map", _hidden_map)
		else:
			_hidden_map.visible = true
	_hidden_map = null

func _input(event: InputEvent) -> void:
	if not active():
		_vr_keys(event)
		return
	# The page's file dialog has the mouse and keyboard while it is open.
	if _picking(): return
	if not _still_usable():
		leave()
		return
	var key := event as InputEventKey
	if key != null:
		var zoom: Variant = controls.get("zoom") if is_instance_valid(controls) else null
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
			leave()
		elif is_instance_valid(zoom) and bool((zoom as Node).call("key", key, tv)):
			pass
		else:
			tv.call("key", key)
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var aspect: float = (tv.get("spec").size as Vector2).aspect()
		_uv = (_uv + Vector2(motion.relative.x / aspect, motion.relative.y) * POINTER_SPEED).clamp(Vector2.ZERO, Vector2.ONE)
		tv.call("set_cursor", _uv)
		tv.call("pointer_move", _uv)
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button != null:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed: tv.call("pointer_wheel", 1.0, button.shift_pressed, button.ctrl_pressed)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed: tv.call("pointer_wheel", -1.0, button.shift_pressed, button.ctrl_pressed)
			MOUSE_BUTTON_WHEEL_LEFT:
				if button.pressed: tv.call("pointer_wheel", 1.0, true)
			MOUSE_BUTTON_WHEEL_RIGHT:
				if button.pressed: tv.call("pointer_wheel", -1.0, true)
			_:
				tv.call("pointer_button", button.button_index, button.pressed)
		get_viewport().set_input_as_handled()
		return
	# Anything else (a gamepad, touch) is not the game's either while in TV mode.
	get_viewport().set_input_as_handled()

## The set still shows a page, the mouse is still captured (or free for the page's file dialog).
func _still_usable() -> bool:
	if not is_instance_valid(tv) or not bool(tv.get("active")): return false
	if str(tv.get("source")) != "web": return false
	if _picking(): return true
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

## The page's file dialog is open (web_view.gd picking).
func _picking() -> bool:
	var page: Variant = tv.get("web") if is_instance_valid(tv) else null
	return page is Node and is_instance_valid(page) and bool((page as Node).get("picking"))

func _process(_delta: float) -> void:
	if active() and not _still_usable(): leave()

# --- VR -----------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var inventory: Node = controls.call("_inventory") if is_instance_valid(controls) else null
	var hub: Variant = controls.get("hub") if is_instance_valid(controls) else null
	if inventory == null or bool(inventory.get("_desktop")) or (is_instance_valid(hub) and bool((hub as Node).call("menu_open"))):
		# Desktop, or a Watch Party menu open in VR (its own laser works it: vr_panel.gd).
		_vr_release()
		return
	var controllers: Variant = inventory.get("controllers")
	if not controllers is Dictionary:
		_vr_release()
		return
	var hit: Dictionary = {}
	var side_now := ""
	for side: String in (["right", "left"] if pointing_side != "left" else ["left", "right"]):
		var controller := (controllers as Dictionary).get(side) as XRController3D
		if controller == null or not _hand_free(inventory, side): continue
		hit = _laser_hit(controller)
		if not hit.is_empty():
			side_now = side
			break
	if side_now.is_empty():
		_vr_release()
		return
	var controller := (controllers as Dictionary)[side_now] as XRController3D
	if side_now != pointing_side:
		_vr_release()
		pointing_side = side_now
		var body := _body()
		if is_instance_valid(body) and not bool(body.get("controls_locked")):
			body.set("controls_locked", true)
			_locked_body = body
	_show_laser(controller.global_position, hit.point)
	var trigger := controller.get_float("trigger")
	var keyboard_hit := bool(hit.get("keyboard", false))
	if keyboard_hit:
		_keyboard.call("hover", hit.uv)
		if not _vr_pressed and trigger > TRIGGER_DOWN:
			_vr_pressed = true
			_keyboard.call("press", hit.uv)
			if inventory.has_method("_haptic"): inventory.call("_haptic", side_now)
		elif _vr_pressed and trigger < TRIGGER_UP:
			_vr_pressed = false
		return
	if is_instance_valid(_keyboard): _keyboard.call("hover", Vector2(-1, -1))
	var target := hit.tv as Node3D
	if target != _vr_tv:
		if is_instance_valid(_vr_tv): _vr_tv.call("set_cursor", Vector2(-1, -1))
		_vr_tv = target
		_keyboard_tv = target
		_connect_typing(target)
	var uv: Vector2 = hit.uv
	target.call("set_cursor", uv)
	target.call("pointer_move", uv)
	if not _vr_pressed and trigger > TRIGGER_DOWN:
		_vr_pressed = true
		target.call("pointer_button", MOUSE_BUTTON_LEFT, true)
	elif _vr_pressed and trigger < TRIGGER_UP:
		_vr_pressed = false
		target.call("pointer_button", MOUSE_BUTTON_LEFT, false)
	var stick := controller.get_vector2("primary")
	if absf(stick.y) > STICK_DEADZONE:
		_wheel_rest += stick.y * STICK_NOTCHES * delta
		var notches := float(int(_wheel_rest))
		if notches != 0.0:
			_wheel_rest -= notches
			target.call("pointer_wheel", notches)
	else:
		_wheel_rest = 0.0
	var menu_button := controller.is_button_pressed("by_button")
	if menu_button and not _menu_button_was: _toggle_keyboard(target, controller)
	_menu_button_was = menu_button

## A hand that holds nothing, or only the TV remote, can point.
func _hand_free(inventory: Node, side: String) -> bool:
	var held: Variant = inventory.get("held")
	if not held is Dictionary or not (held as Dictionary).has(side): return true
	var item: Variant = (held as Dictionary)[side]
	return not is_instance_valid(item) or bool(controls.call("_holding_remote", inventory, side))

## Where the controller's laser lands: the floating keyboard first, else a set's screen showing a
## page or the slideshow. {point, uv, tv} / {point, uv, keyboard: true} / {}.
func _laser_hit(controller: XRController3D) -> Dictionary:
	var from := controller.global_position
	var direction := -controller.global_basis.z.normalized()
	if is_instance_valid(_keyboard) and _keyboard.visible:
		var on_keys: Variant = _keyboard.call("ray", from, direction)
		if on_keys is Dictionary and not (on_keys as Dictionary).is_empty():
			var keys_hit: Dictionary = on_keys
			keys_hit.keyboard = true
			return keys_hit
	var ray := PhysicsRayQueryParameters3D.create(from, from + direction * LASER_REACH, 1 | ITEM_LAYER)
	var hit := controller.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or not is_instance_valid(hit.collider) or not (hit.collider as Node).has_meta("watch_tv"): return {}
	var target := (hit.collider as Node).get_meta("watch_tv") as Node3D
	if not is_instance_valid(target) or not bool(target.get("active")) or str(target.get("source")) not in ["web", "slides"]: return {}
	var spec: Dictionary = target.get("spec")
	var aimed := COMMON.part_on_ray(target, from, direction, hit.position)
	if str(aimed.part) != "screen": return {}
	return {"point": aimed.point, "uv": COMMON.uv_at(spec, target.to_local(aimed.point)), "tv": target}

func _show_laser(from: Vector3, to: Vector3) -> void:
	if not is_instance_valid(_laser):
		_laser = MeshInstance3D.new(); _laser.name = "WatchPartyLaser"
		var beam := CylinderMesh.new(); beam.top_radius = 0.0015; beam.bottom_radius = 0.0015; beam.height = 1.0; beam.radial_segments = 6; beam.rings = 1
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(0.55, 0.85, 1.0, 0.7)
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam.material = glow
		_laser.mesh = beam
		_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_laser.top_level = true
		add_child(_laser)
	var length := from.distance_to(to)
	if length < 0.01: return
	var forward := (to - from) / length
	var side := forward.cross(Vector3.UP if absf(forward.y) < 0.95 else Vector3.RIGHT).normalized()
	_laser.global_transform = Transform3D(Basis(side, forward, side.cross(forward)).scaled(Vector3(1.0, length, 1.0)), (from + to) * 0.5)
	_laser.visible = true

## The laser left the screen (or VR stopped): the cursor goes, a held click is let go, the game
## gets its controls back.
func _vr_release() -> void:
	if is_instance_valid(_vr_tv):
		if _vr_pressed: _vr_tv.call("pointer_button", MOUSE_BUTTON_LEFT, false)
		_vr_tv.call("set_cursor", Vector2(-1, -1))
	_vr_tv = null
	_vr_pressed = false
	_wheel_rest = 0.0
	if is_instance_valid(_laser): _laser.visible = false
	if not pointing_side.is_empty() and is_instance_valid(_locked_body) and not active():
		_locked_body.set("controls_locked", false)
		_locked_body = null
	pointing_side = ""

func _connect_typing(target: Node3D) -> void:
	var page: Variant = target.get("web") if is_instance_valid(target) else null
	if not page is Node or not (page as Node).has_signal("typing"): return
	if not (page as Node).is_connected("typing", _on_typing): (page as Node).connect("typing", _on_typing)

func _on_typing(on: bool) -> void:
	if not on or bool(controls.call("_inventory").get("_desktop")): return
	_open_keyboard()

func _toggle_keyboard(target: Node3D, _controller: XRController3D) -> void:
	_keyboard_tv = target
	if is_instance_valid(_keyboard) and _keyboard.visible: _keyboard.visible = false
	else: _open_keyboard()

## The keyboard floats in front of the player, a little below the eyes, facing them.
func _open_keyboard() -> void:
	var inventory: Node = controls.call("_inventory")
	var camera: Camera3D = inventory.get("camera") as Camera3D if inventory != null else null
	if camera == null: return
	if not is_instance_valid(_keyboard):
		_keyboard = KEYBOARD.new(); _keyboard.name = "WatchPartyKeyboard"
		_keyboard.top_level = true
		_keyboard.typed.connect(_keyboard_typed)
		add_child(_keyboard)
	var flat := Vector3(-camera.global_basis.z.x, 0.0, -camera.global_basis.z.z).normalized()
	var at := camera.global_position + flat * 0.55 + Vector3.DOWN * 0.38
	# Keys face +Z: toward the player, tilted up toward the eyes like a lectern.
	var facing := Basis.looking_at(flat, Vector3.UP)
	_keyboard.global_transform = Transform3D(facing.rotated(facing.x, deg_to_rad(-35.0)), at)
	_keyboard.visible = true

func _keyboard_typed(character: String, keycode: int) -> void:
	if keycode == KEY_ESCAPE:
		_keyboard.visible = false
		return
	if is_instance_valid(_keyboard_tv): _keyboard_tv.call("tap", character, keycode)

## VR with a real keyboard: keys go to the page while the laser is on it or the floating keyboard is up.
func _vr_keys(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null: return
	var target: Node3D = _vr_tv if is_instance_valid(_vr_tv) else (_keyboard_tv if is_instance_valid(_keyboard) and _keyboard.visible else null)
	if not is_instance_valid(target) or str(target.get("source")) != "web": return
	target.call("key", key)
	get_viewport().set_input_as_handled()

## The game's desktop map HUD (world_map_hud.gd, the game's world_map).
func _world_map() -> CanvasLayer:
	var game: Variant = Mods.game
	var map: Variant = (game as Node).get("world_map") if is_instance_valid(game) else null
	return map as CanvasLayer if is_instance_valid(map) else null

func _body() -> Node:
	var inventory: Node = controls.call("_inventory") if is_instance_valid(controls) else null
	var body: Variant = inventory.get("player_body") if inventory != null else null
	return body as Node if is_instance_valid(body) else null
