extends CanvasLayer
## Watch Party setup on its own (in VR on a panel in front of the player: vr_panel.gd), in the game's menu look like the TV menu (tv_menu.gd):
## the setup page (setup_page.gd) in a card with a Close button. For when no set works yet, so
## there is no TV menu: opens by itself once, after the first set works while something is missing
## (main.gd after_power_up), and any time with the TV remote: right click where no set is on
## (tv_controls.gd). Where a set is on, the same page is the TV menu's Setup tab.

const STYLE := preload("res://world/ui/menu_style.gd")
const CARD := preload("res://world/ui/menu_card.gd")
const PAGE := preload("res://mods/watch_party/setup_page.gd")
const MOST := Vector2(900, 720)
const VR_PANEL := preload("res://mods/watch_party/vr_panel.gd")

var hub: Node
var _mouse_before := Input.MOUSE_MODE_CAPTURED
var _lock_owned := false
var _body: Node
var _root: Control
var _card: Control
var _page: Control
var _dim: ColorRect
var _vr: Node3D
var _in_vr := false

func _ready() -> void:
	layer = 41
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = STYLE.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.06, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)
	_dim = dim
	_card = CARD.new()
	_root.add_child(_card)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 46)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 36)
	_card.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var head := HBoxContainer.new()
	var heading := Label.new(); heading.text = "Watch Party setup"; heading.theme_type_variation = "Heading"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	var close_button := Button.new(); close_button.text = "Close"; close_button.theme_type_variation = "Ghost"
	close_button.pressed.connect(close)
	head.add_child(close_button)
	column.add_child(head)
	_page = PAGE.new()
	_page.set("hub", hub)
	column.add_child(_page)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false

func _layout() -> void:
	if not is_instance_valid(_card) or _in_vr: return
	var window := get_viewport().get_visible_rect().size
	var size := STYLE.fit_card(window, MOST)
	_card.position = (window - size) * 0.5
	_card.size = size

func open(by_itself := false) -> void:
	if not visible:
		var inventory: Variant = Mods.game.get("inventory") if is_instance_valid(Mods.game) else null
		_in_vr = is_instance_valid(inventory) and not bool((inventory as Node).get("_desktop"))
		if _in_vr:
			if not is_instance_valid(_vr):
				_vr = VR_PANEL.new()
				(Mods.game as Node).add_child(_vr)
				_vr.call("setup", Vector2i(MOST))
				_vr.call("take", _root)
				_dim.visible = false
				_card.position = Vector2.ZERO
				_card.size = MOST
			_vr.call("open", inventory)
		else:
			_body = (inventory as Node).get("player_body") as Node if is_instance_valid(inventory) else null
			if is_instance_valid(_body) and "controls_locked" in _body:
				_lock_owned = not bool(_body.get("controls_locked"))
				_body.set("controls_locked", true)
			_mouse_before = Input.mouse_mode
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		visible = true
	_layout()
	_page.call("open", by_itself)

func close() -> void:
	if not visible: return
	visible = false
	if _in_vr:
		if is_instance_valid(_vr): _vr.call("close")
		return
	if _lock_owned and is_instance_valid(_body): _body.set("controls_locked", false)
	_lock_owned = false
	Input.mouse_mode = _mouse_before

func _exit_tree() -> void:
	close()
	if is_instance_valid(_vr): _vr.queue_free()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
