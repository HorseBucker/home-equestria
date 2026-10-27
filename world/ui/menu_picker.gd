extends VBoxContainer
## A dropdown that opens inside the page instead of a popup window (an OptionButton's popup
## left a SubViewport panel as a bare desktop window: dev 2026-10-27, the model list filling half
## the screen; a headset cannot reach it at all). Pressing it unfolds a list under it, with a
## search field once the list is long and group headers for "vendor/model" names; picking an
## entry folds it again. Speaks enough of OptionButton's language (add_item, metadata, selected,
## item_selected) for the pages that used one.
signal item_selected(index: int)
signal toggled_open(open: bool)
## The unfolded list's entries (`controls`) were rebuilt (unfolding, a search): hosts that copy them
## into a focus order take the new ones.
signal entries_changed
const STYLE := preload("res://world/ui/menu_style.gd")
const ICON := preload("res://world/ui/menu_icon.gd")
## Above this many entries the list gets a search field.
const SEARCH_FROM := 9
## The one unfolded picker: opening another folds it.
static var _unfolded: WeakRef

## Called after anything visible changes (a SubViewport panel's refresh()).
var redraw := Callable()
## Accepted for OptionButton compatibility; the shown entry always clips.
var fit_to_longest_item := false
var clip_text := true
var placeholder := "Choose…"
## Height of the unfolded list.
var list_height := 300.0
var font_size := 20:
	set(value):
		font_size = value
		if _head != null: _head.add_theme_font_size_override("font_size", value)
var selected := -1:
	set(value):
		selected = clampi(value, -1, _items.size() - 1)
		_show_selected()
var item_count: int:
	get: return _items.size()

var _items: Array[Dictionary] = []   # {"text", "meta"}
var _head: Button
var _drop: VBoxContainer
var _search: LineEdit
var _scroll: ScrollContainer
var _list: VBoxContainer
var _open := false
## Focusable controls of the unfolded list, for pages that step focus with a stick.
var controls: Array[Control] = []


func _init() -> void:
	add_theme_constant_override("separation", 6)
	_head = Button.new(); _head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_head.icon = STYLE.icon("chevron_down"); _head.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_head.custom_minimum_size.y = 48
	_head.pressed.connect(func() -> void: set_open(not _open))
	_watch(_head)
	add_child(_head)
	_drop = VBoxContainer.new(); _drop.add_theme_constant_override("separation", 6); _drop.hide()
	add_child(_drop)
	_search = LineEdit.new(); _search.placeholder_text = "Search…"; _search.clear_button_enabled = true
	_search.custom_minimum_size.y = 42
	_search.text_changed.connect(func(_text: String) -> void: _fill(); _redraw())
	_drop.add_child(_search)
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", STYLE.box(Color(0.05, 0.02, 0.09, 0.55), Color(STYLE.PINK, 0.35), 1, 14, 6, 6))
	_drop.add_child(well)
	_scroll = ScrollContainer.new(); _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _redraw())
	well.add_child(_scroll)
	_list = VBoxContainer.new(); _list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_show_selected()


func clear() -> void:
	_items.clear(); selected = -1
	if _open: _fill()


func add_item(text: String, _id := -1) -> void:
	_items.append({"text": text, "meta": null})
	if _open: _fill()


func set_item_metadata(index: int, meta: Variant) -> void:
	if index >= 0 and index < _items.size(): _items[index].meta = meta


func get_item_metadata(index: int) -> Variant:
	return _items[index].meta if index >= 0 and index < _items.size() else null


func set_item_text(index: int, text: String) -> void:
	if index < 0 or index >= _items.size() or str(_items[index].text) == text: return
	_items[index].text = text
	if index == selected: _show_selected()
	if _open: _fill()


## Moves the face into `parent` (a settings row's line): the list then unfolds under the whole
## row, where this picker itself stands.
func detach_head(parent: Control) -> void:
	_head.reparent(parent)


func get_item_text(index: int) -> String:
	return str(_items[index].text) if index >= 0 and index < _items.size() else ""


func select(index: int) -> void:
	selected = index


func is_open() -> bool:
	return _open


func set_open(open: bool) -> void:
	if open == _open: return
	_open = open and not _items.is_empty()
	if _open:
		var other: Object = _unfolded.get_ref() if _unfolded != null else null
		if other != null and other != self and is_instance_valid(other): (other as Control).call("set_open", false)
		_unfolded = weakref(self)
	_drop.visible = _open
	_head.icon = STYLE.icon("chevron_down")
	if _open:
		_search.visible = _items.size() >= SEARCH_FROM
		_search.text = ""
		_fill()
	else:
		controls.clear()
		for child in _list.get_children(): child.queue_free()
	toggled_open.emit(_open)
	_redraw()


func head() -> Button:
	return _head


func _show_selected() -> void:
	if _head == null: return
	_head.text = get_item_text(selected) if selected >= 0 else placeholder
	_head.add_theme_color_override("font_color", STYLE.CREAM if selected >= 0 else STYLE.MUTED)


func _fill() -> void:
	for child in _list.get_children(): child.free()
	controls.clear()
	if _search.visible: controls.append(_search)
	var words := _search.text.strip_edges().to_lower().split(" ", false)
	var group := ""
	var shown := 0
	for index in _items.size():
		var text := str(_items[index].text)
		var low := text.to_lower()
		var matches := true
		for word in words:
			if not low.contains(word): matches = false; break
		if not matches: continue
		# "vendor/model" lists read as groups: a small header whenever the vendor changes.
		var vendor := text.get_slice("/", 0) if text.contains("/") else ""
		if vendor != group and not vendor.is_empty():
			group = vendor
			var header := STYLE.label(vendor.capitalize(), "Faint", maxi(13, font_size - 5))
			header.add_theme_constant_override("line_spacing", 0)
			_list.add_child(header)
		var entry := Button.new(); entry.theme_type_variation = "Ghost"
		entry.text = text.substr(vendor.length() + 1) if not vendor.is_empty() else text
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		entry.add_theme_font_size_override("font_size", maxi(14, font_size - 2))
		entry.custom_minimum_size.y = font_size * 1.7
		entry.set_meta("no_sparkle", true)
		if index == selected:
			entry.add_theme_color_override("font_color", STYLE.PINK)
			entry.icon = ICON.texture("check", maxi(14, font_size - 4))
			entry.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			entry.add_theme_color_override("icon_normal_color", STYLE.PINK)
		entry.pressed.connect(_pick.bind(index))
		_watch(entry)
		_list.add_child(entry); controls.append(entry)
		shown += 1
	if shown == 0: _list.add_child(STYLE.label("Nothing matches.", "Muted"))
	_scroll.custom_minimum_size.y = minf(list_height, maxf(48.0, shown * (font_size * 1.7 + 2.0) + 30.0))
	entries_changed.emit()


func _watch(button: Button) -> void:
	button.mouse_entered.connect(_redraw); button.mouse_exited.connect(_redraw); button.focus_entered.connect(_redraw)


func _redraw() -> void:
	if redraw.is_valid(): redraw.call()


func _pick(index: int) -> void:
	selected = index
	set_open(false)
	item_selected.emit(index)
