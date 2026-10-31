extends CanvasLayer
## First desktop launch (dev 2026-10-31): "Check this computer for the best graphics settings?"
## Opt-in. Yes runs Quality.pick_for_this_machine() (High, Medium, Low or Very Low, never Ultra)
## and shows the tier it picked; No keeps the default (High). Asked once (Settings
## setup/quality_asked, world/ui/title_screen.gd _ask_quality). Same look as play_mode_prompt.gd.
## `chosen` carries the tier to apply, or "" to keep the current one.
signal chosen(tier: String)

const PLAY := preload("res://world/ui/play_mode_prompt.gd")
const CARD := preload("res://world/ui/menu_card.gd")
var _box: VBoxContainer


func _ready() -> void:
	layer = 100
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var back := Control.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.theme = preload("res://world/ui/menu_style.gd").theme()
	add_child(back)
	var sky := CARD.new(); sky.radius = 0.0; sky.inset = 0.0; sky.glow = 0.0
	sky.set_anchors_preset(Control.PRESET_FULL_RECT); back.add_child(sky)
	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_box.add_theme_constant_override("separation", 28)
	back.add_child(_box)
	_box.add_child(_label("Check this computer for the best graphics settings?", 44, PLAY.WHITE))
	_box.add_child(_label("Looks at your graphics card and memory and picks High, Medium, Low or Very Low.\nNo keeps High. You can change it any time in Settings, Graphics.", 24, PLAY.PINK))
	var yes := _button("Yes, check my computer")
	yes.pressed.connect(_check)
	_box.add_child(yes)
	var no := _button("No, keep High")
	no.pressed.connect(func() -> void: chosen.emit(""))
	_box.add_child(no)
	yes.grab_focus()


func _check() -> void:
	var tier: String = get_tree().root.get_node("Quality").pick_for_this_machine()
	for child in _box.get_children(): child.queue_free()
	_box.add_child(_label("Picked: %s" % tier, 48, PLAY.WHITE))
	_box.add_child(_label("For %s. You can change it any time in Settings, Graphics." % RenderingServer.get_video_adapter_name(), 24, PLAY.PINK))
	var go := _button("Continue")
	go.pressed.connect(func() -> void: chosen.emit(tier))
	_box.add_child(go)
	go.grab_focus.call_deferred()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", PLAY.FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(560, 96)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_override("font", PLAY.FONT)
	button.add_theme_font_size_override("font_size", 34)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, PLAY.WHITE)
	button.add_theme_stylebox_override("normal", _style(PLAY.LILAC))
	button.add_theme_stylebox_override("hover", _style(PLAY.PINK))
	button.add_theme_stylebox_override("focus", _style(PLAY.PINK))
	button.add_theme_stylebox_override("pressed", _style(PLAY.LILAC.darkened(0.12)))
	return button


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = PLAY.WHITE
	style.set_border_width_all(4)
	style.set_corner_radius_all(38)
	return style
