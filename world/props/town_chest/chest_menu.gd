extends Node3D
## The Town Hall chest's page (2026-11-18): what the chest holds beside what the briefcase holds, to move things
## either way or throw them away. Desktop: a card on its own layer (Esc or Close shuts it). VR: a World Panel in
## front of the player, pointed at with the right controller. Built like the saved games panel (save_menu.gd).
## "Discard all" asks once more ("Sure?") before it throws a whole stack away.

const STORE := preload("res://world/props/town_chest/chest_store.gd")
const CATALOG := preload("res://world/inventory/item_catalog.gd")
const DESKTOP_OWNER := preload("res://player/desktop_action_owner.gd")
const SOUNDS := preload("res://world/audio/interaction_sounds.gd")
const VIEW := preload("res://world/player_view.gd")
const CARD := preload("res://world/ui/menu_card.gd")
const STYLE := preload("res://world/ui/menu_style.gd")
const DESKTOP_SIZE := Vector2(1360, 800)
const TEXT := 22
const CONFIRM_SECONDS := 3.0

var game: Node
var ui: Node
var chest: Node3D
var panel: Node3D
var pointer: Node3D
var content: Control
var canvas: CanvasLayer
var opened := false
var _armed := false
var _mouse_mode: int
var _old_lock := false
var _old_physics := true
var _input_states: Dictionary = {}
var _page: Control
var _chest_list: VBoxContainer
var _case_list: VBoxContainer
var _message: Label
var _chest_title: Label
var _confirm := ""          # the "Discard all" button waiting for its second press ("chest:3", "case:5")
var _confirm_until := 0.0
var _built_size := Vector2.ZERO


func setup(host: Node, inventory_ui: Node, owner_chest: Node3D) -> void:
	game = host; ui = inventory_ui; chest = owner_chest
	if ui._desktop:
		canvas = CanvasLayer.new(); canvas.layer = 150; add_child(canvas)
		var shade := ColorRect.new(); shade.color = Color(0.04, 0.01, 0.07, 0.5); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		canvas.add_child(shade)
		content = Control.new(); canvas.add_child(content); canvas.hide()
		get_viewport().size_changed.connect(func() -> void: if opened: _place_desktop())
	else:
		panel = preload("res://world/ui/spatial_menu_panel.gd").new(); add_child(panel); panel.hide(); content = panel.content
		pointer = preload("res://world/ui/controller_pointer.gd").new(); add_child(pointer)


func _build(card_size: Vector2) -> void:
	if card_size == _built_size and _page != null: return
	_built_size = card_size
	for child in content.get_children(): child.queue_free()
	content.size = card_size
	var card := CARD.new(); card.size = card_size; content.add_child(card)
	_page = VBoxContainer.new(); _page.theme = STYLE.theme()
	_page.position = Vector2(34, 28); _page.size = card_size - Vector2(68, 56)
	_page.add_theme_constant_override("separation", 12)
	content.add_child(_page)
	var head := HBoxContainer.new(); head.add_theme_constant_override("separation", 16); _page.add_child(head)
	var title := STYLE.label("Town Hall chest", "Heading", TEXT + 14); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_button := Button.new(); close_button.text = "Close"; close_button.theme_type_variation = "Primary"
	close_button.add_theme_font_size_override("font_size", TEXT); close_button.custom_minimum_size = Vector2(140, 52)
	close_button.pressed.connect(close); head.add_child(close_button)
	_message = STYLE.label("", "Muted", TEXT - 2); _message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(_message)
	var columns := HBoxContainer.new(); columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24); _page.add_child(columns)
	_chest_list = _column(columns, "In the chest", true)
	_case_list = _column(columns, "In your briefcase", false)


func _column(parent: Control, heading: String, is_chest: bool) -> VBoxContainer:
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	var label := STYLE.label(heading, "Subheading", TEXT + 2); box.add_child(label)
	if is_chest: _chest_title = label
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list


func _place_desktop() -> void:
	var screen := Vector2(get_viewport().get_visible_rect().size)
	var scale := STYLE.window_scale(screen)
	_build(STYLE.fit_card(screen, DESKTOP_SIZE))
	content.scale = Vector2.ONE * scale; STYLE.sharpen(get_viewport(), scale)
	content.position = ((screen - content.size * scale) * 0.5).floor()


# ---- the lists ----

func refresh() -> void:
	if _page == null: return
	for child in _chest_list.get_children(): child.queue_free()
	for child in _case_list.get_children(): child.queue_free()
	var rows := STORE.listing(game)
	_chest_title.text = "In the chest (%d)" % rows.size()
	if rows.is_empty(): _chest_list.add_child(STYLE.label("Nothing yet.", "Muted", TEXT - 2))
	for i in rows.size():
		var row: Dictionary = rows[i]
		if row.has("token"):
			# a mod's item, kept in the chest as one of the briefcase's loans (chest_store.gd)
			var token := str(row.token)
			_row(_chest_list, str(row.id), 1, 0, "chest:" + token,
				[["Take", func() -> void: _say(STORE.take_mod(game, token))]],
				func(_all: bool) -> void: _say(STORE.discard_mod(game, token)))
			continue
		_row(_chest_list, str(row.id), int(row.count), int(row.get("bites", 0)), "chest:%d" % i,
			[["Take", func() -> void: _say(STORE.take(game, i, 1))], ["Take all", func() -> void: _say(STORE.take(game, i, -1))]],
			func(all: bool) -> void: _say(STORE.discard(game, i, -1 if all else 1)))
	var store := STORE.briefcase(game)
	var slots: Array = store.get("slots") if store != null else []
	var any := false
	for i in slots.size():
		var slot: Dictionary = slots[i]
		if slot.is_empty(): continue
		any = true
		var moves: Array = [["Store", func() -> void: _say(STORE.store_slot(game, i, 1))], ["Store all", func() -> void: _say(STORE.store_slot(game, i, -1))]]
		_row(_case_list, str(slot.id), int(slot.count), int(slot.get("bites", 0)), "case:%d" % i, moves,
			func(all: bool) -> void: _say(STORE.discard_slot(game, i, -1 if all else 1)))
	if not any: _case_list.add_child(STYLE.label("Empty.", "Muted", TEXT - 2))
	if panel != null: panel.refresh()


func _row(list: VBoxContainer, id: String, count: int, bites: int, key: String, moves: Array, discard: Callable) -> void:
	var line := HBoxContainer.new(); line.add_theme_constant_override("separation", 8); list.add_child(line)
	var icon := TextureRect.new(); icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if CATALOG.has(CATALOG.canonical(id)): icon.texture = CATALOG.icon(CATALOG.canonical(id))
	line.add_child(icon)
	var name := STORE.name_of(id) + (" × %d" % count if count > 1 else "") + (" (bitten)" if bites > 0 else "")
	var label := STYLE.label(name, "", TEXT - 2); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true; label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(label)
	for move: Array in moves:
		if str(move[0]).ends_with("all") and count <= 1: continue
		_small(line, str(move[0]), "Chip", move[1])
	_small(line, "Discard 1" if count > 1 else "Discard", "Ghost", func() -> void: discard.call(false))
	if count > 1:
		var sure := _confirm == key and Time.get_ticks_msec() / 1000.0 < _confirm_until
		_small(line, "Sure?" if sure else "Discard all", "Danger", func() -> void:
			if _confirm == key and Time.get_ticks_msec() / 1000.0 < _confirm_until:
				_confirm = ""; discard.call(true)
			else:
				_confirm = key; _confirm_until = Time.get_ticks_msec() / 1000.0 + CONFIRM_SECONDS; refresh())


func _small(parent: Control, text: String, variation: String, action: Callable) -> void:
	var button := Button.new(); button.text = text; button.theme_type_variation = variation
	button.add_theme_font_size_override("font_size", TEXT - 4); button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(action)
	parent.add_child(button)


func _say(text: String) -> void:
	if _message != null and text != "": _message.text = text
	_menu_sound("prop_select")
	refresh.call_deferred()


# ---- opening and closing ----

func open() -> bool:
	if opened: return false
	if ui.customizer.opened: return false
	if ui.hand_busy("right") or ui.hand_busy("left"): return false
	if ui._desktop: DESKTOP_OWNER.cancel_current(ui)
	if is_instance_valid(ui.inspector): ui.inspector.close()
	ui._close_map(); ui._release_case(); ui.case.close(); ui.wrist.hide()
	opened = true; _armed = false; _old_lock = ui.player_body.controls_locked; ui.player_body.controls_locked = true
	_old_physics = ui.is_physics_processing()
	for node in [ui, ui.inspector, ui.map_menu]:
		if not is_instance_valid(node): continue
		_input_states[node] = node.is_processing_input(); node.set_process_input(false)
	ui._claim("right", true); ui._claim("left", true); ui.set_physics_process(false)
	if ui._desktop:
		_mouse_mode = Input.mouse_mode; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_place_desktop(); canvas.show()
	else:
		_build(Vector2(panel.PIXELS))
		panel.global_position = ui.camera.global_position - ui.camera.global_basis.z * 1.4
		panel.look_at(ui.camera.global_position, Vector3.UP, true); panel.show(); panel.tick = 1.0 / 20.0
	_message.text = "Things kept here are safe; the briefcase can take them back any time."
	refresh()
	_menu_sound("prop_ui_confirm")
	return true


func close() -> void:
	if not opened: return
	_menu_sound("prop_ui_back")
	opened = false; _confirm = ""
	ui._claim("right", false); ui._claim("left", false); ui.set_physics_process(_old_physics); ui.player_body.controls_locked = _old_lock
	for node in _input_states:
		if is_instance_valid(node): node.set_process_input(_input_states[node])
	_input_states.clear()
	if ui._desktop: canvas.hide(); Input.mouse_mode = _mouse_mode; STYLE.sharpen(get_viewport(), 1.0)
	else: panel.press(false); panel.hide(); panel.tick = 0.0; pointer.hide()
	if is_instance_valid(chest): chest.set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if opened and ui._desktop and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled(); close()


func _menu_sound(event: String) -> void:
	var camera: Camera3D = VIEW.camera(self)
	if camera != null: SOUNDS.play_at(camera, event, camera.global_position)


func _process(_delta: float) -> void:
	if not opened: return
	if _confirm != "" and Time.get_ticks_msec() / 1000.0 >= _confirm_until: _confirm = ""; refresh()
	if ui._desktop: return
	var sample: Dictionary = ui.hand_sample("right")
	if not sample.get("active", false): _armed = false; panel.press(false); pointer.hide(); return
	var pose: Transform3D = sample.aim
	if not pose.is_finite(): _armed = false; panel.press(false); pointer.hide(); return
	var pressed: bool = sample.trigger > 0.6
	if not pressed: _armed = true
	var pixel: Vector2 = panel.ray_to_pixel(pose.origin, -pose.basis.z)
	panel.point_at(pixel); panel.press(pressed and _armed and pixel.x >= 0)
	pointer.aim(pose.origin, panel.pixel_to_world(pixel) if pixel.x >= 0 else pose.origin - pose.basis.z * 2.0)
