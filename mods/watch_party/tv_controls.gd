extends Node
## Working the televisions. The set itself has no controls (dev 2026-11-01); the TV remote
## (catalog.gd REMOTE), held, works the nearest set that is on, from anywhere in the room:
## - Desktop: click play/pause, hold the click to turn the set off or on, right click the TV menu, mouse wheel skips, the arrow keys change
##   the video (left/right) and the volume (up/down); a card in the bottom right corner lists them
##   (remote_card.gd). With the remote in hand nothing is picked up or stored.
## - VR: the trigger plays and pauses; held, it turns the set off or on; pulled twice quickly, the TV
##   menu (or the setup, where no set is on) opens on a panel in front of you (vr_panel.gd). The
##   remote's notes ("No television on nearby") show on a card in front of the view (vr_notice.gd).
## Clicking a screen that shows a web page enters TV mode (screen_input.gd, a child of this node,
## so its _input comes first); a click on the slideshow stops it. In VR a laser does the same.
## The set's front never picks it up (E and clicks there do nothing and show no prompt), and its
## top, sides and back only from close by (PICK_UP_REACH), not from the briefcase's 2.5 m.
## Desktop keys are read in _input, ahead of the briefcase: its own _input takes a placed set into
## the briefcase on E, and its click picks it up (first in-game test, 2026-11-01). Godot hands
## _input to the last node in the tree first, so main.gd adds this node as the root's last child
## after each world loads.

const COMMON := preload("res://mods/watch_party/screen_common.gd")
const SCREEN_INPUT := preload("res://mods/watch_party/screen_input.gd")
const SCREEN_ZOOM := preload("res://mods/watch_party/screen_zoom.gd")
const GOODS := preload("res://mods/watch_party/catalog.gd")
const CARD := preload("res://mods/watch_party/remote_card.gd")
const DESK_REACH := 3.0
const ITEM_LAYER := 1 << 17
## The remote reaches a set this far away.
const REMOTE_RANGE := 15.0
## A set is picked up (E on its top or sides) only from this close, in metres from the eye.
const PICK_UP_REACH := 1.3

## Holding the remote's button (left click, VR trigger) this long is the power button.
const HOLD_SECONDS := 0.6
## VR: a second trigger pull this soon after the first opens the TV menu.
const DOUBLE_SECONDS := 0.4
const VR_NOTICE := preload("res://mods/watch_party/vr_notice.gd")
const VR_NOTE_SECONDS := 2.5
## The note that a set will not turn on stays this long (playtest 2026-11-07: too quick to read).
const DORMANT_NOTE_SECONDS := 7.0
## The desktop centre dot fades out over this long while the view rests on a screen (and back).
const RETICLE_FADE := 0.2
## How far away a screen still hides the dot (watching from across the room).
const SCREEN_LOOK_REACH := 12.0

var hub: Node
var _remote_trigger: Dictionary = {"left": true, "right": true}
## When the trigger went down (msec, -1: not held) and whether the hold already powered the set.
var _trigger_started: Dictionary = {"left": -1, "right": -1}
var _trigger_fired: Dictionary = {"left": false, "right": false}
## When the last plain trigger pull ended (msec, -1: none lately), for the double pull.
var _last_pull: Dictionary = {"left": -1, "right": -1}
var _vr_note: Node3D
var _hold_started := -1
var _hold_fired := false
## The game's desktop crosshair (world/ui/desktop_crosshair.gd under game.gd's InteractionHints).
## The game sets its `visible` every physics frame; only its modulate alpha is ours.
var _crosshair: CanvasItem
var _crosshair_alpha := 1.0
var _card: CanvasLayer
var screen_input: Node
## Home: the view up close to a screen (screen_zoom.gd).
var zoom: Node

func _ready() -> void:
	add_to_group("interaction_hint_sources")
	process_physics_priority = -45
	screen_input = SCREEN_INPUT.new()
	screen_input.name = "WatchPartyScreenInput"
	screen_input.controls = self
	add_child(screen_input)
	zoom = SCREEN_ZOOM.new()
	zoom.name = "WatchPartyScreenZoom"
	zoom.controls = self
	add_child(zoom)
	_card = CARD.new()
	_card.name = "WatchPartyRemoteCard"
	add_child(_card)

func _inventory() -> Node:
	var game: Variant = Mods.game
	if not is_instance_valid(game): return null
	var inventory: Variant = (game as Node).get("inventory")
	return inventory as Node if is_instance_valid(inventory) else null

func _desktop(inventory: Node) -> bool:
	return bool(inventory.get("_desktop"))

func _input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	var key := event as InputEventKey
	var button := event as InputEventMouseButton
	var pressed_key: bool = key != null and key.pressed and not key.echo
	var pressed_button: bool = button != null and button.pressed
	var released_left: bool = button != null and not button.pressed and button.button_index == MOUSE_BUTTON_LEFT and _hold_started >= 0
	if not pressed_key and not pressed_button and not released_left: return
	var inventory := _inventory()
	if inventory == null or not _desktop(inventory): return
	if released_left:
		# Let go before HOLD_SECONDS: a plain click, play / pause.
		var was_held := _hold_fired
		_hold_started = -1
		if not was_held: _remote_action(inventory, "play")
		get_viewport().set_input_as_handled()
		return
	var body: Variant = inventory.get("player_body")
	# Held by the zoom (screen_zoom.gd), the remote still works; held by anything else, nothing here does.
	var zoomed: bool = is_instance_valid(zoom) and bool(zoom.call("holding"))
	if is_instance_valid(body) and bool((body as Node).get("controls_locked")) and not zoomed: return
	if pressed_button and button.button_index == MOUSE_BUTTON_LEFT and _use_screen(inventory):
		get_viewport().set_input_as_handled()
		return
	var remote := _holding_remote(inventory, "desktop")
	if remote and _remote_desktop(inventory, key if pressed_key else null, button if pressed_button else null):
		get_viewport().set_input_as_handled()
		return
	var e_key: bool = pressed_key and key.physical_keycode == KEY_E
	var click: bool = pressed_button and button.button_index == MOUSE_BUTTON_LEFT
	if not e_key and not click: return
	if _guarded(inventory) or (e_key and remote and not _pickable(inventory).is_empty()):
		# A set's front, a set too far away, or anything at all with the remote in hand.
		get_viewport().set_input_as_handled()

## A left click on a screen showing a page enters TV mode there; on the slideshow it stops it.
## True when the click was used.
func _use_screen(inventory: Node) -> bool:
	var tv: Node3D = null
	var uv := Vector2(0.5, 0.5)
	if is_instance_valid(zoom) and bool(zoom.call("on")):
		# Zoomed in (screen_zoom.gd), the screen fills the view: a click uses it wherever the
		# crosshair was before (dev 2026-11-06), the pointer starting in the middle.
		tv = zoom.get("tv") as Node3D
	else:
		var aimed := _aimed(inventory, SCREEN_LOOK_REACH)
		if aimed.is_empty() or str(aimed.part) != "screen": return false
		tv = aimed.target as Node3D
		uv = COMMON.uv_at(tv.get("spec"), tv.to_local(aimed.point))
	if not is_instance_valid(tv): return false
	match str(tv.get("source")):
		"web":
			screen_input.call("enter", tv, uv)
			return true
		"slides":
			tv.call("stop_slides")
			return true
	return false

## A key or button with the remote in the desktop hand; true when it was a remote control.
func _remote_desktop(inventory: Node, key: InputEventKey, button: InputEventMouseButton) -> bool:
	var action := ""
	if button != null:
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				# Play / pause on release, power once held (_input, _process).
				_hold_started = Time.get_ticks_msec()
				_hold_fired = false
				return true
			MOUSE_BUTTON_RIGHT: action = "menu"
			MOUSE_BUTTON_WHEEL_UP: action = "forward"
			MOUSE_BUTTON_WHEEL_DOWN: action = "back"
	elif key != null:
		match key.physical_keycode:
			KEY_RIGHT: action = "next"
			KEY_LEFT: action = "previous"
			KEY_UP: action = "louder"
			KEY_DOWN: action = "quieter"
	if action.is_empty(): return false
	_remote_action(inventory, action)
	return true

## Sends `action` to the set the remote works; false when there is none.
func _remote_action(inventory: Node, action: String) -> bool:
	var tv := remote_target(inventory)
	if tv == null:
		# With no set that works nearby, right click is the setup (setup_panel.gd); a set out of
		# the Everfree that Twilight has not woken yet does nothing (finds.gd).
		if action == "menu" and is_instance_valid(hub):
			hub.open_setup()
			return true
		var dormant := _dormant_near(inventory)
		_flash(inventory, "It won't turn on. There are no outlets to plug it into. Maybe somepony who knows magic could figure something out." if dormant else "No television on nearby", DORMANT_NOTE_SECONDS if dormant else 2.0)
		# Twilight may be watching it with her magic, waiting for him to try (magic_quest.gd tried).
		var quest: Variant = hub.get("quest") if dormant and is_instance_valid(hub) else null
		if is_instance_valid(quest) and (quest as Node).has_method("tried"): (quest as Node).call("tried")
		return false
	if action == "menu":
		if is_instance_valid(hub): hub.open_menu(tv)
	else:
		tv.call("press", action)
	return true

func _exit_tree() -> void:
	if is_instance_valid(_crosshair): _crosshair.modulate.a = 1.0
	if is_instance_valid(_vr_note): _vr_note.queue_free()

## A note from the remote: the corner card on desktop, a card in front of the view in VR.
func _flash(inventory: Node, text: String, seconds := 2.0) -> void:
	if _desktop(inventory):
		_card.flash(text, seconds)
		return
	var camera: Variant = inventory.get("camera")
	if not camera is Camera3D: return
	if not is_instance_valid(_vr_note) or _vr_note.get_parent() != camera:
		if is_instance_valid(_vr_note): _vr_note.queue_free()
		_vr_note = VR_NOTICE.new()
		_vr_note.call("setup", camera)
	_vr_note.call("show_text", "", text, maxf(VR_NOTE_SECONDS, seconds))

## Desktop: the centre dot fades out while the view is on a TV screen, so it does not sit on the film.
func _fade_crosshair(inventory: Node, delta: float) -> void:
	if not is_instance_valid(_crosshair):
		var game: Variant = Mods.game
		var hints: Node = (game as Node).get_node_or_null("InteractionHints") if is_instance_valid(game) else null
		var found: Variant = hints.get("_crosshair") if hints != null else null
		if not found is CanvasItem: return
		_crosshair = found
	var on_screen: bool = inventory != null and _desktop(inventory) and (bool(screen_input.call("active")) or str(_aimed(inventory, SCREEN_LOOK_REACH).get("part", "")) == "screen")
	_crosshair_alpha = move_toward(_crosshair_alpha, 0.0 if on_screen else 1.0, delta / RETICLE_FADE)
	_crosshair.modulate.a = _crosshair_alpha

func _process(delta: float) -> void:
	var inventory := _inventory()
	_fade_crosshair(inventory, delta)
	var shown: bool = inventory != null and _desktop(inventory) and _holding_remote(inventory, "desktop") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_card.visible = shown
	if not shown:
		# The remote put away or the mouse freed mid-hold: no click and no power.
		_hold_started = -1
		return
	if _hold_started >= 0 and not _hold_fired and Time.get_ticks_msec() - _hold_started >= HOLD_SECONDS * 1000.0:
		_hold_fired = true
		_remote_action(inventory, "power")
	_card.show_status(remote_target(inventory))
	_grip_remote(inventory)

## Desktop: the hand closes round the remote, thumb over the buttons, instead of the game's
## half-open carrying hand. desktop_anon.gd sets the hand every frame; this node is the root's
## last child, so its _process comes after and has the last word.
const REMOTE_GRIP_AMOUNT := 0.9
const REMOTE_INDEX := 0.75

func _grip_remote(inventory: Node) -> void:
	var presentation: Variant = inventory.get("desktop_presentation")
	var avatar: Variant = (presentation as Node).get("avatar") if is_instance_valid(presentation) else null
	if not is_instance_valid(avatar) or not (avatar as Node).has_method("set_grip"): return
	(avatar as Node).call("set_grip", "right", REMOTE_GRIP_AMOUNT)
	if (avatar as Node).has_method("set_trigger"): (avatar as Node).call("set_trigger", "right", REMOTE_INDEX)

## VR: the remote's trigger plays and pauses the nearest set that is on; held, it is the power button.
func _physics_process(_delta: float) -> void:
	var inventory := _inventory()
	if inventory == null or _desktop(inventory): return
	if is_instance_valid(hub) and bool(hub.call("menu_open")):
		# The menu's laser has the trigger now; the remote waits until it closes.
		for side: String in ["left", "right"]:
			_remote_trigger[side] = true
			_trigger_started[side] = -1
		return
	for side: String in ["left", "right"]:
		if not _holding_remote(inventory, side) or str(screen_input.get("pointing_side")) == side:
			# Starts "pulled", so a trigger already held when the remote is picked up does nothing.
			_remote_trigger[side] = true
			_trigger_started[side] = -1
			continue
		var sample: Dictionary = inventory.call("hand_sample", side)
		var squeeze: float = float(sample.get("trigger", 0.0))
		var pulled: bool = bool(sample.get("active", false)) and squeeze > (0.45 if _remote_trigger[side] else 0.75)
		var now := Time.get_ticks_msec()
		if pulled and not _remote_trigger[side]:
			_trigger_started[side] = now
			_trigger_fired[side] = false
			if int(_last_pull[side]) >= 0 and now - int(_last_pull[side]) <= DOUBLE_SECONDS * 1000.0:
				# The second pull: the TV menu (this pull neither plays nor powers).
				_last_pull[side] = -1
				_trigger_fired[side] = true
				_remote_action(inventory, "menu")
				if inventory.has_method("_haptic"): inventory.call("_haptic", side)
		elif pulled and int(_trigger_started[side]) >= 0 and not bool(_trigger_fired[side]) and now - int(_trigger_started[side]) >= HOLD_SECONDS * 1000.0:
			_trigger_fired[side] = true
			if _remote_action(inventory, "power") and inventory.has_method("_haptic"): inventory.call("_haptic", side)
		elif not pulled and _remote_trigger[side] and int(_trigger_started[side]) >= 0:
			if not bool(_trigger_fired[side]):
				_last_pull[side] = now
				if _remote_action(inventory, "play") and inventory.has_method("_haptic"): inventory.call("_haptic", side)
			_trigger_started[side] = -1
		_remote_trigger[side] = pulled

func _holding_remote(inventory: Node, side: String) -> bool:
	var held: Variant = inventory.get("held")
	if not held is Dictionary: return false
	var item: Variant = (held as Dictionary).get(side)
	return is_instance_valid(item) and GOODS.is_remote(str((item as Node).get_meta("item_id", "")))

## The set the remote works: the nearest one that is on within REMOTE_RANGE, a playing one first.
func remote_target(inventory: Node) -> Node3D:
	var camera: Camera3D = inventory.get("camera") as Camera3D
	if not is_instance_valid(camera): return null
	var best: Node3D = null
	var best_score := INF
	for node: Node in get_tree().get_nodes_in_group("watch_tvs"):
		var tv := node as Node3D
		if tv == null or not bool(tv.get("active")): continue
		var distance := tv.global_position.distance_to(camera.global_position)
		if distance > REMOTE_RANGE: continue
		var status: Dictionary = tv.call("status")
		var score := distance - (100.0 if str(status.get("state", "")) in ["playing", "paused"] else 0.0)
		if score < best_score:
			best_score = score
			best = tv
	return best

## A placed set that is not woken yet within the remote's reach.
func _dormant_near(inventory: Node) -> bool:
	var camera: Camera3D = inventory.get("camera") as Camera3D
	if not is_instance_valid(camera): return false
	for node: Node in get_tree().get_nodes_in_group("watch_tvs_dormant"):
		if node is Node3D and (node as Node3D).global_position.distance_to(camera.global_position) <= REMOTE_RANGE: return true
	return false

## What the briefcase would pick up or store on E now ({} when nothing).
func _pickable(inventory: Node) -> Dictionary:
	if not inventory.has_method("desktop_look_target"): return {}
	var look: Variant = inventory.call("desktop_look_target")
	if not look is Dictionary or not is_instance_valid((look as Dictionary).get("target")): return {}
	return look

## The set and where the crosshair meets it: {target, part, collider, point, distance}, or {}.
func _aimed(inventory: Node, reach := DESK_REACH) -> Dictionary:
	var camera: Camera3D = inventory.get("camera") as Camera3D
	if not is_instance_valid(camera): return {}
	var skip: Array[RID] = []
	var player_body: Variant = inventory.get("player_body")
	if player_body is CollisionObject3D: skip.append((player_body as CollisionObject3D).get_rid())
	var held: Variant = inventory.get("held")
	if held is Dictionary:
		for item: Variant in (held as Dictionary).values():
			if is_instance_valid(item) and item is CollisionObject3D: skip.append((item as CollisionObject3D).get_rid())
	var from := camera.global_position
	var ray := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * reach, 1 | ITEM_LAYER, skip)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty(): return {}
	var collider: Object = hit.collider
	if not is_instance_valid(collider) or not collider is Node or not (collider as Node).has_meta("watch_tv"): return {}
	var tv: Variant = (collider as Node).get_meta("watch_tv")
	if not is_instance_valid(tv) or not (tv as Node).is_in_group("watch_tvs"): return {}
	var set_node := tv as Node3D
	var point: Vector3 = hit.position
	var aimed := COMMON.part_on_ray(set_node, from, -camera.global_basis.z, point)
	return {"target": set_node, "part": aimed.part, "collider": collider, "point": aimed.point, "distance": from.distance_to(point)}

## Looking at a set where E must not pick it up: its front, or the rest from too far away.
func _guarded(inventory: Node) -> bool:
	var aimed := _aimed(inventory)
	if aimed.is_empty():
		# The briefcase also takes things near the crosshair (its forgiving cone): never a set.
		var look := _pickable(inventory)
		return not look.is_empty() and (look.target as Node).has_meta("watch_tv")
	return not str(aimed.part).is_empty() or float(aimed.distance) > PICK_UP_REACH

func interaction_hint() -> Dictionary:
	var inventory := _inventory()
	if inventory == null or not _desktop(inventory) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return {}
	var remote := _holding_remote(inventory, "desktop")
	var aimed := _aimed(inventory)
	# An empty text hides the prompt (world/ui/interaction_hints.gd); no outline, no glow.
	if not aimed.is_empty() and (remote or _guarded(inventory)):
		return {"target": aimed.target, "point": aimed.point, "collider": aimed.collider, "outline": null, "visible_pick": true, "text": ""}
	if remote or _guarded(inventory):
		var look := _pickable(inventory)
		if look.is_empty(): return _remote_hint(inventory) if remote else {}
		var thing := look.target as Node3D
		if thing == null: return {}
		var at: Vector3 = look.get("point", thing.global_position)
		return {"target": thing, "point": at, "outline": null, "visible_pick": true, "text": ""}
	return {}

## With the remote in hand the hint is the remote's, as a held letter's is the letter's
## (briefcase_inventory.gd): nothing else (a couch he sits on, a pony) lights up meanwhile.
func _remote_hint(inventory: Node) -> Dictionary:
	var held: Variant = inventory.get("held")
	var item: Variant = (held as Dictionary).get("desktop") if held is Dictionary else null
	if not is_instance_valid(item): return {}
	return {"target": item, "point": (item as Node3D).global_position, "outline": null, "visible_pick": true, "text": ""}
