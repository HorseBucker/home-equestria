extends VBoxContainer
## Same physical controller buttons as other settings, in desktop and VR.
var _status: Label
var _buttons: Dictionary = {}
var _refresh_button: Button
var _redraw: Callable

func setup(font_size: int, redraw: Callable) -> void:
	_redraw = redraw
	var title := Label.new()
	title.text = "Debug lighting — live, session only"
	title.add_theme_font_size_override("font_size", font_size + 2)
	add_child(title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", font_size - 2)
	add_child(_status)
	for id: String in Quality.LIGHTING_TESTS:
		var config: Dictionary = Quality.LIGHTING_TESTS[id]
		var button := Button.new()
		button.text = config.label
		button.tooltip_text = config.note
		button.toggle_mode = true
		button.custom_minimum_size.y = 46
		button.add_theme_font_size_override("font_size", font_size)
		button.pressed.connect(_select.bind(id))
		add_child(button)
		_buttons[id] = button
	_refresh_button = Button.new()
	_refresh_button.text = "Refresh this room / reflections"
	_refresh_button.custom_minimum_size.y = 46
	_refresh_button.pressed.connect(func():
		var sky := _sky()
		if sky != null: sky.debug_lighting.refresh_room()
		refresh()
	)
	add_child(_refresh_button)
	refresh()

func _sky() -> Node:
	if not is_inside_tree(): return null
	for sky: Node in get_tree().get_nodes_in_group("sky_controller"):
		if is_instance_valid(sky.get("debug_lighting")): return sky
	return null

func _select(id: String) -> void:
	var sky := _sky()
	if sky != null: sky.set_debug_lighting(id)
	refresh()

func refresh() -> void:
	var sky := _sky()
	var selected: String = sky.debug_lighting.mode if sky != null else "baseline"
	for id: String in _buttons:
		_buttons[id].disabled = sky == null
		_buttons[id].set_pressed_no_signal(id == selected)
	_refresh_button.disabled = sky == null or selected == "baseline"
	if sky == null:
		_status.text = "Enter the game to compare lighting. No baked lighting is used."
	else:
		var controls: Node = sky.debug_lighting
		var location := "Local lights and reflections inactive: no supported room at the camera."
		if is_instance_valid(controls.room):
			location = "%d room materials responding · %d fill lights · reflection %s" % [controls._materials.size(), controls._fills.size(), "active" if is_instance_valid(controls._probe) else "off"]
		if selected == "baseline": location = "Original materials and lighting restored."
		_status.text = "%s\n%s\n%s\nExperimental GPU cost; compare with F9. Nothing is saved." % [Quality.LIGHTING_TESTS[selected].label, Quality.LIGHTING_TESTS[selected].note, location]
	if _redraw.is_valid(): _redraw.call()
