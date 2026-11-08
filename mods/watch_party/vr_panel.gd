extends Node3D
## A Watch Party menu in VR (the TV menu, tv_menu.gd; the setup, setup_panel.gd), shown the way the
## game shows its own settings in a headset (world/ui/settings_menu.gd): the menu's controls drawn
## into a panel floating in front of the player (world/ui/spatial_menu_panel.gd), a laser from the
## hand holding the TV remote (else the right hand) with its gold dot (world/ui/controller_pointer.gd),
## the trigger clicks, the stick scrolls what is under the laser. A text field that has the focus
## brings up the game's on-panel keyboard under the menu (world/ui/panel_keyboard.gd). While open,
## both hands and the briefcase are held, as the game's settings panel holds them.

const PANEL := preload("res://world/ui/spatial_menu_panel.gd")
const POINTER := preload("res://world/ui/controller_pointer.gd")
const KEYBOARD := preload("res://world/ui/panel_keyboard.gd")
## The panel this far in front of the eyes, this much smaller than the game's metres per pixel (the
## TV menu is wider than the settings card).
const DISTANCE := 1.35
const SHRINK := 0.8
const KEYBOARD_WIDTH := 880.0
const KEYBOARD_HEIGHT := 330
const SCROLL_EVERY := 0.12
const REDRAW := 1.0 / 20.0

var panel: Node3D
var pointer: Node3D
var keyboard: Control
var content: Control
var opened := false
var _size := Vector2i(1180, 780)
var _ui: Node
var _armed := false
var _scroll_wait := 0.0
var _old_lock := false
var _old_physics := true
var _input_states: Dictionary = {}

## `size`: the menu's own size in pixels; the keyboard goes under it.
func setup(size: Vector2i) -> void:
	_size = size
	name = "WatchPartyVrPanel"
	panel = PANEL.new()
	add_child(panel)
	panel.scale = Vector3.ONE * SHRINK
	panel.call("resize", Vector2i(size.x, size.y + KEYBOARD_HEIGHT + 12))
	var viewport: SubViewport = panel.get("viewport")
	viewport.gui_embed_subwindows = true
	content = panel.get("content")
	pointer = POINTER.new()
	add_child(pointer)
	keyboard = KEYBOARD.new()
	keyboard.call("setup", panel, KEYBOARD_WIDTH, 20)
	keyboard.position = Vector2((size.x - KEYBOARD_WIDTH) * 0.5, size.y + 12)
	content.add_child(keyboard)
	_plain_keyboard()
	keyboard.hide()
	panel.hide()
	pointer.hide()

## The game's keyboard is made for its API key: here it is only a keyboard.
func _plain_keyboard() -> void:
	for child: Node in keyboard.get_children():
		if child is Label: (child as Label).text = "Typing into the field above."
	_hide_buttons(keyboard, "Load key file")

func _hide_buttons(node: Node, text: String) -> void:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text.begins_with(text): (child as Button).hide()
		_hide_buttons(child, text)

## The menu's controls go on the panel: `root` (laid out at the menu's size, top left).
func take(root: Control) -> void:
	if root.get_parent() != null: root.reparent(content, false)
	else: content.add_child(root)
	content.move_child(root, 0)
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	root.size = Vector2(_size)

func refresh() -> void:
	if is_instance_valid(panel): panel.call("refresh")

func open(inventory: Node) -> void:
	_ui = inventory
	if opened: return
	opened = true
	_armed = false
	var body: Variant = inventory.get("player_body")
	if is_instance_valid(body):
		_old_lock = bool((body as Node).get("controls_locked"))
		(body as Node).set("controls_locked", true)
	_old_physics = inventory.is_physics_processing()
	for node: Variant in [inventory, inventory.get("inspector"), inventory.get("map_menu")]:
		if not is_instance_valid(node): continue
		_input_states[node] = (node as Node).is_processing_input()
		(node as Node).set_process_input(false)
	if inventory.has_method("_claim"):
		inventory.call("_claim", "right", true)
		inventory.call("_claim", "left", true)
	inventory.set_physics_process(false)
	var camera: Variant = inventory.get("camera")
	if camera is Node3D:
		var eye: Node3D = camera
		var ahead := -eye.global_basis.z
		ahead.y = 0.0
		ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
		global_position = eye.global_position + ahead * DISTANCE + Vector3.DOWN * 0.1
		look_at(eye.global_position, Vector3.UP, true)
	panel.show()
	panel.set("tick", REDRAW)
	refresh()

func close() -> void:
	if not opened: return
	opened = false
	panel.call("press", false)
	panel.hide()
	panel.set("tick", 0.0)
	pointer.hide()
	keyboard.hide()
	if not is_instance_valid(_ui): return
	if _ui.has_method("_claim"):
		_ui.call("_claim", "right", false)
		_ui.call("_claim", "left", false)
	_ui.set_physics_process(_old_physics)
	var body: Variant = _ui.get("player_body")
	if is_instance_valid(body): (body as Node).set("controls_locked", _old_lock)
	for node: Variant in _input_states:
		if is_instance_valid(node): (node as Node).set_process_input(_input_states[node])
	_input_states.clear()

func _exit_tree() -> void:
	close()

## The hand the laser comes from: the one holding the remote, else the right.
func _side() -> String:
	var held: Variant = _ui.get("held")
	if held is Dictionary:
		for side: String in ["right", "left"]:
			var item: Variant = (held as Dictionary).get(side)
			if is_instance_valid(item) and str((item as Node).get_meta("item_id", "")) == "goods:watch-tv-remote": return side
	return "right"

func _process(delta: float) -> void:
	if not opened or not is_instance_valid(_ui): return
	var side := _side()
	var sample: Dictionary = _ui.call("hand_sample", side)
	var pose: Variant = sample.get("aim")
	if not bool(sample.get("active", false)) or not pose is Transform3D or not (pose as Transform3D).is_finite():
		_armed = false
		panel.call("press", false)
		pointer.hide()
		return
	var aim: Transform3D = pose
	var pressed: bool = float(sample.get("trigger", 0.0)) > 0.6
	if not pressed: _armed = true
	var pixel: Vector2 = panel.call("ray_to_pixel", aim.origin, -aim.basis.z)
	panel.call("point_at", pixel)
	panel.call("press", pressed and _armed and pixel.x >= 0)
	pointer.show()
	pointer.call("aim", aim.origin, panel.call("pixel_to_world", pixel) if pixel.x >= 0 else aim.origin - aim.basis.z * 2.0)
	_scroll(side, pixel, delta)
	_tend_keyboard()

## The stick up or down scrolls whatever is under the laser (a list, a page).
func _scroll(side: String, pixel: Vector2, delta: float) -> void:
	_scroll_wait -= delta
	if pixel.x < 0 or _scroll_wait > 0.0: return
	var controllers: Variant = _ui.get("controllers")
	var controller: Variant = (controllers as Dictionary).get(side) if controllers is Dictionary else null
	if not controller is XRController3D: return
	var stick: Vector2 = (controller as XRController3D).get_vector2("primary")
	if absf(stick.y) < 0.5: return
	_scroll_wait = SCROLL_EVERY
	var wheel := InputEventMouseButton.new()
	wheel.position = pixel
	wheel.global_position = pixel
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP if stick.y > 0.0 else MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 1.0
	var viewport: SubViewport = panel.get("viewport")
	viewport.push_input(wheel, true)
	var release := wheel.duplicate() as InputEventMouseButton
	release.pressed = false
	viewport.push_input(release, true)
	refresh()

## The keyboard shows while a text field on the menu has the focus.
func _tend_keyboard() -> void:
	var viewport: SubViewport = panel.get("viewport")
	var focused: Control = viewport.gui_get_focus_owner()
	var wanted: bool = focused is LineEdit or focused is TextEdit
	if wanted == keyboard.visible: return
	keyboard.visible = wanted
	refresh()
