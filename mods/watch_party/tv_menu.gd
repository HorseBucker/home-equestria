extends CanvasLayer
## The TV menu (desktop): right click with the TV remote opens it. In the game's own look
## (world/ui/menu_style.gd theme on a world/ui/menu_card.gd twilight card): what is on with its
## seek bar, transport, volume, sound and subtitle tracks and picture settings on the left; the
## library (search, folders) and ffmpeg on the right. The header's tabs swap both for the photos and
## web page (screen_page.gd), the vision API page (vision_page.gd) or the setup (setup_page.gd).
## While open, the mouse is free and movement is locked (as world/ui/chat_box.gd does); Escape or
## Close shuts it. In VR (pull the remote's trigger twice, tv_controls.gd) the same controls are
## drawn on a panel in front of the player, worked with a laser (vr_panel.gd); Browse… is hidden
## there (Windows' folder dialog would open on the desktop), the on-panel keyboard types paths. A full-screen backdrop takes every click, so a click beside the card does not
## hand the mouse back to the game.

const TOOLS := preload("res://mods/watch_party/ffmpeg_tools.gd")
const SET := preload("res://mods/watch_party/tv_set.gd")
const COMPANY := preload("res://mods/watch_party/watch_company.gd")
const STYLE := preload("res://world/ui/menu_style.gd")
const CARD := preload("res://world/ui/menu_card.gd")
const VISION_PAGE := preload("res://mods/watch_party/vision_page.gd")
const SCREEN_PAGE := preload("res://mods/watch_party/screen_page.gd")
const SETUP_PAGE := preload("res://mods/watch_party/setup_page.gd")
const VR_PANEL := preload("res://mods/watch_party/vr_panel.gd")
const MOST := Vector2(1180, 780)

var hub: Node
var tv: Node3D
var _mouse_before := Input.MOUSE_MODE_CAPTURED
var _lock_owned := false
var _body: Node
var _refresh := 0.0
var _seeking := false
var _root: Control
var _card: Control
var _note: Label
var _title: Label
var _time: Label
var _seek: HSlider
var _play: Button
var _volume: HSlider
var _audio: OptionButton
var _subtitles: OptionButton
var _fit: Button
var _fill: Button
var _crt: CheckButton
var _crt_label: Label
var _pace: OptionButton
var _follows: Label
var _search: LineEdit
var _list: ItemList
var _shown: PackedStringArray = PackedStringArray()
var _folders: Label
var _folder_path: LineEdit
var _ffmpeg: LineEdit
var _ffmpeg_status: Label
var _dialog: FileDialog
var _tracks_for := ""
var _tracks_count := -1
var _columns: Control
var _vision_page: Control
var _watch_tab: Button
var _vision_tab: Button
var _screen_page: Control
var _screen_tab: Button
var _setup_tab: Button
## The setup page in a scroll of its own (it is taller than the menu on small windows).
var _setup_scroll: ScrollContainer
var _setup_page: Control
var _dim: ColorRect
var _browse: Button
## VR: the panel the menu is drawn on (vr_panel.gd), and whether it is open there.
var _vr: Node3D
var _in_vr := false

func _ready() -> void:
	layer = 40
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
	var page := VBoxContainer.new(); page.add_theme_constant_override("separation", 14)
	margin.add_child(page)
	page.add_child(_header())
	_note = _label("", "Warn")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_note)
	var columns := HBoxContainer.new(); columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)
	columns.add_child(_now_playing())
	columns.add_child(_library())
	_columns = columns
	_vision_page = VISION_PAGE.new()
	_vision_page.set("hub", hub)
	_vision_page.set("menu", self)
	_vision_page.visible = false
	page.add_child(_vision_page)
	_screen_page = SCREEN_PAGE.new()
	_screen_page.set("hub", hub)
	_screen_page.set("menu", self)
	_screen_page.visible = false
	page.add_child(_screen_page)
	_setup_scroll = ScrollContainer.new()
	_setup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_setup_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_setup_scroll.visible = false
	page.add_child(_setup_scroll)
	_setup_page = SETUP_PAGE.new()
	_setup_page.set("hub", hub)
	_setup_scroll.add_child(_setup_page)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false

## The watch page (now playing, library) or the pony vision page.
## The watch page (now playing, library), "screen" (photos and web) or "vision" (pony vision).
func _show_page(which: String) -> void:
	_columns.visible = which == "watch"
	_vision_page.visible = which == "vision"
	_screen_page.visible = which == "screen"
	_setup_scroll.visible = which == "setup"
	if which == "setup": _setup_page.call("open")
	if which == "vision": _vision_page.call("open")
	else: _vision_page.call("flush")
	if which == "screen": _screen_page.call("open")
	else: _screen_page.call("flush")

func _header() -> Control:
	var row := HBoxContainer.new()
	var heading := _label("Television", "Heading")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	var tabs := HBoxContainer.new(); tabs.add_theme_constant_override("separation", 0)
	tabs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var group := ButtonGroup.new()
	_watch_tab = _button("Watch", _show_page.bind("watch"), "Segment"); _watch_tab.toggle_mode = true; _watch_tab.button_group = group
	_screen_tab = _button("Photos & web", _show_page.bind("screen"), "Segment"); _screen_tab.toggle_mode = true; _screen_tab.button_group = group
	_vision_tab = _button("Pony vision", _show_page.bind("vision"), "Segment"); _vision_tab.toggle_mode = true; _vision_tab.button_group = group
	_watch_tab.set_pressed_no_signal(true)
	_setup_tab = _button("Setup", _show_page.bind("setup"), "Segment"); _setup_tab.toggle_mode = true; _setup_tab.button_group = group
	tabs.add_child(_watch_tab); tabs.add_child(_screen_tab); tabs.add_child(_vision_tab); tabs.add_child(_setup_tab)
	row.add_child(tabs)
	var gap := Control.new(); gap.custom_minimum_size = Vector2(16, 0)
	row.add_child(gap)
	var close_button := _button("Close", close, "Ghost")
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(close_button)
	return row

func _now_playing() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(470, 0)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(_label("Now playing", "Muted"))
	_title = _label("Nothing on", "Subheading")
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	column.add_child(_title)
	_time = _label("", "Faint")
	# A long web address must not widen the menu (playtest 2026-11-04).
	_time.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_time.clip_text = true
	column.add_child(_time)
	_seek = HSlider.new(); _seek.step = 1.0
	_seek.drag_started.connect(_seek_started)
	_seek.drag_ended.connect(_seek_released)
	column.add_child(_seek)
	var transport := HBoxContainer.new(); transport.add_theme_constant_override("separation", 8)
	transport.alignment = BoxContainer.ALIGNMENT_CENTER
	transport.add_child(_button("−30", _tv_call.bind("skip", [-30.0]), "Round"))
	transport.add_child(_button("−10", _tv_call.bind("skip", [-10.0]), "Round"))
	_play = _button("Play", _tv_call.bind("toggle_play", []), "Primary")
	_play.custom_minimum_size = Vector2(120, 0)
	transport.add_child(_play)
	transport.add_child(_button("+10", _tv_call.bind("skip", [10.0]), "Round"))
	transport.add_child(_button("+30", _tv_call.bind("skip", [30.0]), "Round"))
	transport.add_child(_button("Stop", _tv_call.bind("stop", []), "Ghost"))
	column.add_child(transport)
	var volume_row := HBoxContainer.new(); volume_row.add_theme_constant_override("separation", 10)
	var volume_label := _label("Volume", "Muted"); volume_label.custom_minimum_size = Vector2(110, 0)
	volume_row.add_child(volume_label)
	# All the way left (-41) is muted (tv_set.gd set_volume).
	_volume = HSlider.new(); _volume.min_value = -41.0; _volume.max_value = 6.0; _volume.step = 1.0
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume.value_changed.connect(_volume_changed)
	volume_row.add_child(_volume)
	column.add_child(volume_row)
	column.add_child(HSeparator.new())
	var grid := GridContainer.new(); grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14); grid.add_theme_constant_override("v_separation", 10)
	grid.add_child(_label("Sound", "Muted"))
	_audio = _drop(_audio_chosen)
	grid.add_child(_audio)
	grid.add_child(_label("Subtitles", "Muted"))
	_subtitles = _drop(_subtitle_chosen)
	grid.add_child(_subtitles)
	grid.add_child(_label("Picture", "Muted"))
	var shape := HBoxContainer.new(); shape.add_theme_constant_override("separation", 0)
	var shapes := ButtonGroup.new()
	_fit = _button("Fit", _shape_chosen.bind(false), "Segment"); _fit.toggle_mode = true; _fit.button_group = shapes
	_fill = _button("Fill", _shape_chosen.bind(true), "Segment"); _fill.toggle_mode = true; _fill.button_group = shapes
	_fit.tooltip_text = "The whole picture, with black bars above and below a wide film."
	_fill.tooltip_text = "Fills the screen; the sides of a wide film are cut off."
	shape.add_child(_fit); shape.add_child(_fill)
	grid.add_child(shape)
	_crt_label = _label("CRT look", "Muted")
	grid.add_child(_crt_label)
	_crt = CheckButton.new(); _crt.text = "Scanlines and a curved tube"
	_crt.toggled.connect(_crt_toggled)
	grid.add_child(_crt)
	column.add_child(grid)
	column.add_child(HSeparator.new())
	var ponies := GridContainer.new(); ponies.columns = 2
	ponies.add_theme_constant_override("h_separation", 14); ponies.add_theme_constant_override("v_separation", 10)
	ponies.add_child(_label("Ponies talk", "Muted"))
	_pace = _drop(_pace_chosen)
	for key: String in COMPANY.PACE_ORDER: _pace.add_item(str(COMPANY.PACES[key].label))
	_pace.tooltip_text = "How often a pony watching with you remarks on what is on. Ask a pony whether she wants to watch something with you to invite her."
	ponies.add_child(_pace)
	ponies.add_child(_label("They follow", "Muted"))
	_follows = _label("", "Faint"); _follows.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_follows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ponies.add_child(_follows)
	column.add_child(ponies)
	return panel

func _library() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 12)
	var heading := _label("Library", "Subheading")
	top.add_child(heading)
	_search = LineEdit.new(); _search.placeholder_text = "Search…"; _search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.text_changed.connect(_search_changed)
	top.add_child(_search)
	column.add_child(top)
	_list = ItemList.new(); _list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 220)
	_list.item_activated.connect(_play_index)
	column.add_child(_list)
	var play_row := HBoxContainer.new(); play_row.add_theme_constant_override("separation", 8)
	play_row.add_child(_button("Play selected", _play_selected, "Primary"))
	play_row.add_child(_button("Rescan", _rescan, "Ghost"))
	column.add_child(play_row)
	var folder_row := HBoxContainer.new(); folder_row.add_theme_constant_override("separation", 8)
	_folder_path = LineEdit.new(); _folder_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_path.placeholder_text = "Add a folder, e.g. E:\\Movies"
	_folder_path.text_submitted.connect(_folder_typed)
	folder_row.add_child(_folder_path)
	folder_row.add_child(_button("Add", _add_typed_folder))
	_browse = _button("Browse…", _pick_folder, "Ghost")
	folder_row.add_child(_browse)
	column.add_child(folder_row)
	var folders_row := HBoxContainer.new(); folders_row.add_theme_constant_override("separation", 8)
	_folders = _label("", "Faint"); _folders.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_folders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folders_row.add_child(_folders)
	folders_row.add_child(_button("Clear folders", _clear_folders, "Danger"))
	column.add_child(folders_row)
	column.add_child(HSeparator.new())
	var ffmpeg_row := HBoxContainer.new(); ffmpeg_row.add_theme_constant_override("separation", 8)
	ffmpeg_row.add_child(_label("ffmpeg", "Muted"))
	_ffmpeg = LineEdit.new(); _ffmpeg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ffmpeg.placeholder_text = "ffmpeg.exe or its folder (empty: the usual places)"
	ffmpeg_row.add_child(_ffmpeg)
	ffmpeg_row.add_child(_button("Check", _check_ffmpeg))
	column.add_child(ffmpeg_row)
	_ffmpeg_status = _label("", "Faint"); _ffmpeg_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_ffmpeg_status)
	return panel

func _label(text: String, variation := "") -> Label:
	var label := Label.new(); label.text = text
	if not variation.is_empty(): label.theme_type_variation = variation
	return label

func _button(text: String, pressed: Callable, variation := "") -> Button:
	var button := Button.new(); button.text = text
	if not variation.is_empty(): button.theme_type_variation = variation
	button.pressed.connect(pressed)
	return button

func _drop(chosen: Callable) -> OptionButton:
	var drop := OptionButton.new()
	drop.theme_type_variation = "Drop"
	drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop.fit_to_longest_item = false
	drop.clip_text = true
	drop.item_selected.connect(chosen)
	return drop

## The card at the game's menu size for this window, centred.
func _layout() -> void:
	if not is_instance_valid(_card) or _in_vr: return
	var window := get_viewport().get_visible_rect().size
	var size := STYLE.fit_card(window, MOST)
	_card.position = (window - size) * 0.5
	_card.size = size

func _settings() -> RefCounted:
	return hub.get("settings") as RefCounted

func open(target: Node3D) -> void:
	tv = target
	if not visible:
		var inventory: Variant = Mods.game.get("inventory") if is_instance_valid(Mods.game) else null
		_in_vr = is_instance_valid(inventory) and not bool((inventory as Node).get("_desktop"))
		if _in_vr:
			_open_vr(inventory as Node)
		else:
			_body = (inventory as Node).get("player_body") as Node if is_instance_valid(inventory) else null
			if is_instance_valid(_body) and "controls_locked" in _body:
				_lock_owned = not bool(_body.get("controls_locked"))
				_body.set("controls_locked", true)
			_mouse_before = Input.mouse_mode
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		visible = true
	_layout()
	var settings := _settings()
	_ffmpeg.text = str(settings.ffmpeg_path)
	var library: PackedStringArray = settings.library
	if library.is_empty(): settings.scan()
	_fill_library()
	_volume.set_value_no_signal(maxf(float(settings.volume_db), -41.0))
	_crt.set_pressed_no_signal(bool(settings.crt))
	# Only the vintage set has a tube: on a flatscreen the row is not there at all (playtest
	# 2026-11-07: its name stayed behind).
	_crt.visible = str((tv.get("spec") as Dictionary).get("kind", "crt")) == "crt"
	_crt_label.visible = _crt.visible
	_fit.set_pressed_no_signal(not bool(settings.fill))
	_fill.set_pressed_no_signal(bool(settings.fill))
	_pace.select(maxi(0, COMPANY.PACE_ORDER.find(str(settings.pace))))
	if _vision_page.visible: _vision_page.call("open")
	if _screen_page.visible: _screen_page.call("open")
	if _setup_scroll.visible: _setup_page.call("open")
	_tracks_for = ""
	_refresh = 0.0

func close() -> void:
	if not visible: return
	visible = false
	if is_instance_valid(_dialog): _dialog.hide()
	_vision_page.call("flush")
	_screen_page.call("flush")
	if _in_vr:
		if is_instance_valid(_vr): _vr.call("close")
		return
	if _lock_owned and is_instance_valid(_body): _body.set("controls_locked", false)
	_lock_owned = false
	Input.mouse_mode = _mouse_before

## VR: the menu moves onto its panel the first time (and stays there), in front of the player.
func _open_vr(inventory: Node) -> void:
	if not is_instance_valid(_vr):
		_vr = VR_PANEL.new()
		(Mods.game as Node).add_child(_vr)
		_vr.call("setup", Vector2i(MOST))
		_vr.call("take", _root)
		_dim.visible = false
		_card.position = Vector2.ZERO
		_card.size = MOST
		_hide_browse(_root)
	_vr.call("open", inventory)

## Every Browse… button (here and on the Photos & web page): Windows' folder dialog would open on the
## desktop, out of the headset.
func _hide_browse(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Button and (child as Button).text == "Browse…": (child as Button).visible = false
		_hide_browse(child)

func _exit_tree() -> void:
	close()
	if is_instance_valid(_vr): _vr.queue_free()


func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		if is_instance_valid(_dialog) and _dialog.visible: return
		close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible: return
	if not is_instance_valid(tv) or not tv.get("active"):
		close()
		return
	_refresh -= delta
	if _refresh > 0.0: return
	_refresh = 0.25
	var status: Dictionary = tv.call("status")
	var state := str(status.state)
	_title.text = str(status.title) if not str(status.title).is_empty() else "Nothing on"
	var mode := str(status.get("mode", ""))
	_play.text = "Pause" if state == "playing" and mode == "video" else "Play"
	var length := float(status.duration)
	_seek.editable = length > 0.0 and state in ["playing", "paused"]
	_seek.max_value = maxf(1.0, length)
	if not _seeking: _seek.set_value_no_signal(float(status.position))
	var time := SET.clock(float(status.position)) + (" / " + SET.clock(length) if length > 0.0 else "")
	var states := {"playing": time, "paused": "Paused · " + time, "tuning": "Tuning in…"}
	_time.text = str(states.get(state, "Pick something from your library"))
	if mode == "web": _time.text = "Web browser · " + str(status.get("url", "")).get_slice("://", 1).get_slice("/", 0).trim_prefix("www.")
	elif mode == "slides": _time.text = "Photo slideshow"
	_note.text = str(hub.call("ffmpeg_note"))
	_note.visible = not _note.text.is_empty()
	_show_tracks(str(status.path))
	_show_ffmpeg_status()
	_show_follows(status)

## Fills the sound and subtitle lists when the file (or what is known about it) changes.
func _show_tracks(path: String) -> void:
	var audio: Array = tv.call("audio_choices")
	if path == _tracks_for and audio.size() == _tracks_count: return
	_tracks_for = path
	_tracks_count = audio.size()
	_audio.clear()
	for row: Dictionary in audio: _audio.add_item(str(row.label), int(row.track))
	if audio.is_empty(): _audio.add_item("—", 0)
	_audio.select(maxi(0, _audio.get_item_index(int(tv.call("audio_track")))))
	_audio.disabled = audio.size() < 2
	_subtitles.clear()
	var choices: Array = tv.call("subtitle_choices")
	var key := str(tv.get("subtitle_key"))
	for i in choices.size():
		var row: Dictionary = choices[i]
		_subtitles.add_item(str(row.label), i)
		_subtitles.set_item_metadata(i, str(row.key))
		if str(row.key) == key: _subtitles.select(i)
	_subtitles.disabled = choices.size() < 2

func _audio_chosen(index: int) -> void:
	_tv_call("set_audio", [_audio.get_item_id(index)])

func _subtitle_chosen(index: int) -> void:
	_tv_call("set_subtitle", [str(_subtitles.get_item_metadata(index))])

func _pace_chosen(index: int) -> void:
	var company: Variant = hub.get("company")
	if is_instance_valid(company): (company as Node).call("set_pace", COMPANY.PACE_ORDER[index])

## Whether ponies can follow what is on: they read text subtitles, never picture ones; on the web,
## a YouTube video's captions, else the pages and a little of their words (when they may see).
func _show_follows(status: Dictionary) -> void:
	var mode := str(status.get("mode", ""))
	if mode == "web" or mode == "slides":
		if mode == "slides": _follows.text = "Only that pictures are showing."
		elif str(status.state) == "private": _follows.text = "Nothing of it: \"Ponies watching along can see what I browse\" is off (Photos & web)."
		elif bool(status.get("youtube", false)) and bool(status.get("captions", false)): _follows.text = "Yes, they read the video's captions (on for them even when hidden; CC or C shows or hides them)."
		elif bool(status.get("youtube", false)): _follows.text = "Only its title and channel: no captions found for this video yet."
		else: _follows.text = "The pages you open and a little of their words; a YouTube video with its captions."
		_follows.theme_type_variation = "Muted"
		return
	if str(status.path).is_empty() or str(status.state) in ["idle", "tuning"]:
		_follows.text = "Play something to see whether ponies can follow it."
		_follows.theme_type_variation = "Faint"
	elif str(tv.get("pony_track")).is_empty():
		_follows.text = "Only its title: it has no text subtitles. A .srt file with the same name beside it fixes that."
		_follows.theme_type_variation = "Warn"
	else:
		_follows.text = "Yes, they read the subtitles: " + str(tv.get("pony_track"))
		_follows.theme_type_variation = "Muted"

func _shape_chosen(fill: bool) -> void:
	_tv_call("set_fill", [fill])

func _crt_toggled(on: bool) -> void:
	_tv_call("set_crt", [on])

func _volume_changed(value: float) -> void:
	_tv_call("set_volume", [value])

func _seek_started() -> void:
	_seeking = true

func _seek_released(changed: bool) -> void:
	_seeking = false
	if changed: _tv_call("seek_to", [_seek.value])

func _tv_call(method: String, arguments: Array) -> void:
	if is_instance_valid(tv) and tv.has_method(method): tv.callv(method, arguments)
	_refresh = 0.0

## Always says where ffmpeg stands, so Check visibly answers.
func _show_ffmpeg_status() -> void:
	var found := str(hub.get("ffmpeg"))
	if bool(hub.get("_searching")):
		_ffmpeg_status.text = "Checking for ffmpeg…"
		_ffmpeg_status.theme_type_variation = "Faint"
	elif found.is_empty():
		_ffmpeg_status.text = "ffmpeg not found there, or it would not run."
		_ffmpeg_status.theme_type_variation = "Warn"
	else:
		var probe := found.get_base_dir().path_join("ffprobe.exe" if OS.get_name() == "Windows" else "ffprobe")
		var probe_note := "" if found == "ffmpeg" or FileAccess.file_exists(probe) else " (no ffprobe beside it: no length, seek bar or track lists)"
		_ffmpeg_status.text = "ffmpeg works: " + found + probe_note
		_ffmpeg_status.theme_type_variation = "Muted"

func _check_ffmpeg() -> void:
	var settings := _settings()
	settings.set("ffmpeg_path", _ffmpeg.text.strip_edges())
	settings.save()
	hub.find_ffmpeg()
	_refresh = 0.0

# --- library ------------------------------------------------------------------------------------

func _fill_library() -> void:
	var settings := _settings()
	var filter := _search.text.strip_edges().to_lower()
	_list.clear()
	_shown = PackedStringArray()
	var library: PackedStringArray = settings.library
	var folders: PackedStringArray = settings.folders
	for path: String in library:
		var shown_as := _display_name(path, folders)
		if not filter.is_empty() and not shown_as.to_lower().contains(filter): continue
		var at := float(settings.resume.get(path, 0.0))
		_list.add_item(shown_as + ("   · " + SET.clock(at) if at > 5.0 else ""))
		_list.set_item_tooltip(_list.item_count - 1, path)
		_shown.append(path)
	_folders.text = ("Folders: " + ", ".join(folders)) if not folders.is_empty() else "No folders yet: add the folder your videos are in."

## A file as the library shows it: its path under its library folder, without the extension
## ("Breaker Morant (1980)/Featurettes/Actor Bryan Brown").
static func _display_name(path: String, folders: PackedStringArray) -> String:
	for root: String in folders:
		if path.begins_with(root.trim_suffix("/") + "/"): return path.substr(root.trim_suffix("/").length() + 1).get_basename()
	return path.get_file().get_basename()

func _search_changed(_text: String) -> void:
	_fill_library()

func _play_selected() -> void:
	var picked := _list.get_selected_items()
	if not picked.is_empty(): _play_index(picked[0])

func _play_index(index: int) -> void:
	if index < 0 or index >= _shown.size(): return
	_tv_call("play_file", [_shown[index]])

func _rescan() -> void:
	_settings().scan()
	_fill_library()

func _clear_folders() -> void:
	_settings().clear_folders()
	_fill_library()

func _folder_typed(_text: String) -> void:
	_add_typed_folder()

func _add_typed_folder() -> void:
	var dir := _folder_path.text.strip_edges().trim_prefix("\"").trim_suffix("\"").replace("\\", "/")
	if dir.is_empty(): return
	if not DirAccess.dir_exists_absolute(dir):
		_folders.text = "No folder at %s" % dir
		return
	_folder_path.text = ""
	_folder_chosen(dir)

func _pick_folder() -> void:
	if not is_instance_valid(_dialog):
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.title = "Choose a folder with videos"
		_dialog.dir_selected.connect(_folder_chosen)
		add_child(_dialog)
	_dialog.popup_centered(Vector2i(900, 600))

func _folder_chosen(dir: String) -> void:
	_settings().add_folder(dir)
	_fill_library()
