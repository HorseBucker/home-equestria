extends HBoxContainer
## The TV menu's "Photos & web" page (tv_menu.gd): the photo slideshow (its folder, seconds per
## picture, whether it starts by itself on an idle set, start it now) and the web browser (open it
## as it was left, where gdCEF is, the home page, and whether ponies watching along may see the
## pages; going about the web is done on the screen's own toolbar). Settings are saved as they change.

var hub: Node
var menu: Node
var _slides_folder: LineEdit
var _seconds: SpinBox
var _when_idle: CheckButton
var _slides_note: Label
var _web_note: Label
var _cef_folder: LineEdit
var _home: LineEdit
var _ponies: OptionButton
## What ponies watching along may know of the browser (watch_settings.gd web_ponies), in menu order.
const WEB_CHOICES := [["none", "Nothing"], ["words", "Page & words"], ["pictures", "Also pictures"]]
var _filling := false
var _dialog: FileDialog

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_slides_panel())
	add_child(_web_panel())

func _slides_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(470, 0)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(_heading("Photo slideshow", "The pictures in a folder of yours (subfolders too), in a random order with a soft fade. GIFs and WebMs play too (a WebM with its sound), looping until the seconds per picture are up and always at least once to the end. With the remote, the mouse wheel (or Left/Right) goes to the next or previous picture; in VR point at the screen and use the thumbstick. Any other button, or a click on the screen, stops it."))
	var folder_row := HBoxContainer.new(); folder_row.add_theme_constant_override("separation", 8)
	_slides_folder = LineEdit.new(); _slides_folder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slides_folder.placeholder_text = "A folder of pictures, e.g. E:\\Photos"
	_slides_folder.text_submitted.connect(_folder_typed)
	_slides_folder.focus_exited.connect(_folder_left)
	folder_row.add_child(_slides_folder)
	folder_row.add_child(_button("Browse…", _pick_folder, "Ghost"))
	column.add_child(folder_row)
	var seconds_row := HBoxContainer.new(); seconds_row.add_theme_constant_override("separation", 8)
	seconds_row.add_child(_label("Seconds per picture", "Muted"))
	_seconds = SpinBox.new(); _seconds.min_value = 2; _seconds.max_value = 600; _seconds.step = 1
	_seconds.value_changed.connect(_seconds_changed)
	seconds_row.add_child(_seconds)
	column.add_child(seconds_row)
	_when_idle = CheckButton.new(); _when_idle.text = "Start by itself after the set has been off 5 minutes"
	_when_idle.toggled.connect(_when_idle_toggled)
	column.add_child(_when_idle)
	column.add_child(_button("Start the slideshow", _start_slides, "Primary"))
	_slides_note = _wrapped("", "Faint")
	column.add_child(_slides_note)
	return panel

func _web_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(_heading("Web browser", "Desktop: click the screen to use it (the mouse moves a pointer, the keyboard types; Esc gives you back the game). The toolbar on the screen has back, forward, reload, the address, tabs (the wheel over them scrolls) and the zoom (Ctrl + wheel); the mouse's side buttons go back and forward. Right click a link or picture for open, new tab, save and copy; a middle click opens a link in a new tab, and elsewhere scrolls as you move the pointer (click to stop). Downloads go to your Downloads folder. A page asking for a file opens Windows' file dialog. Ads from known ad servers are blocked. A video gone full screen hides the toolbar. The browser opens as you left it, and a set switched off on a page comes back on with it. VR: point at the screen; the trigger clicks, the stick scrolls, B/Y shows the keyboard. Logins and cookies are kept between sessions."))
	# The pages open last time come back (the home page the first time).
	column.add_child(_button("Open the browser", _open_browser, "Primary"))
	var home_row := HBoxContainer.new(); home_row.add_theme_constant_override("separation", 8)
	home_row.add_child(_label("Home page", "Muted"))
	_home = LineEdit.new(); _home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home.placeholder_text = "empty: duckduckgo.com"
	_home.text_changed.connect(_home_changed)
	home_row.add_child(_home)
	column.add_child(home_row)
	# The label above, the choice under it: side by side, the longest choice pushed the page past
	# the card (playtest 2026-11-07).
	column.add_child(_label("Ponies watching along know", "Muted"))
	var ponies_row := HBoxContainer.new(); ponies_row.add_theme_constant_override("separation", 8)
	_ponies = OptionButton.new(); _ponies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ponies.fit_to_longest_item = false
	_ponies.clip_text = true
	_ponies.custom_minimum_size.x = 120
	for choice: Array in WEB_CHOICES: _ponies.add_item(str(choice[1]))
	_ponies.item_selected.connect(_ponies_chosen)
	ponies_row.add_child(_ponies)
	ponies_row.add_child(_tip("Nothing: they only know the television shows something of yours, and nothing about it leaves your computer. The page and some of its words: they are told the pages you open (title and address) and a little of their text, and a YouTube video they watch like one of your films, reading its captions (turned on but hidden unless you show them: the CC button or C shows or hides them); they know an ad is an ad. How it looks: with Pony vision on, they also see the page now and then (a picture of it is sent to your vision API)."))
	column.add_child(ponies_row)
	column.add_child(HSeparator.new())
	var cef_row := HBoxContainer.new(); cef_row.add_theme_constant_override("separation", 8)
	cef_row.add_child(_label("gdCEF", "Muted"))
	_cef_folder = LineEdit.new(); _cef_folder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cef_folder.placeholder_text = "its cef_artifacts folder (empty: beside HomeEquestria.exe)"
	cef_row.add_child(_cef_folder)
	cef_row.add_child(_button("Check", _check_cef))
	column.add_child(cef_row)
	_web_note = _wrapped("", "Faint")
	column.add_child(_web_note)
	return panel

func _label(text: String, variation := "") -> Label:
	var label := Label.new(); label.text = text
	if not variation.is_empty(): label.theme_type_variation = variation
	return label

## A heading with a "?" beside it that shows `tip` when the pointer rests on it.
func _heading(text: String, tip: String) -> Control:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8)
	row.add_child(_label(text, "Subheading"))
	row.add_child(_tip(tip))
	return row

func _tip(text: String) -> Label:
	var mark := _label("?", "Muted")
	mark.tooltip_text = _lines(text, 64)
	mark.mouse_filter = Control.MOUSE_FILTER_STOP
	mark.mouse_default_cursor_shape = Control.CURSOR_HELP
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return mark

## Tooltips do not wrap on their own: break `text` into lines of about `width` characters.
static func _lines(text: String, width: int) -> String:
	var out := PackedStringArray()
	var line := ""
	for word: String in text.split(" ", false):
		if not line.is_empty() and line.length() + 1 + word.length() > width:
			out.append(line)
			line = word
		else:
			line = word if line.is_empty() else line + " " + word
	if not line.is_empty(): out.append(line)
	return "\n".join(out)

func _wrapped(text: String, variation := "") -> Label:
	var label := _label(text, variation)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text: String, pressed: Callable, variation := "") -> Button:
	var button := Button.new(); button.text = text
	if not variation.is_empty(): button.theme_type_variation = variation
	button.pressed.connect(pressed)
	return button

func _settings() -> RefCounted:
	return hub.get("settings") as RefCounted

func _tv() -> Node3D:
	var tv: Variant = menu.get("tv") if menu != null else null
	return tv as Node3D if is_instance_valid(tv) else null

## Fills the page from the settings (the menu opened or this page was shown).
func open() -> void:
	var settings := _settings()
	_filling = true
	_slides_folder.text = str(settings.slides_folder)
	_seconds.value = float(settings.slides_seconds)
	_when_idle.button_pressed = bool(settings.slides_when_idle)
	_home.text = str(settings.browser_home)
	_ponies.select(maxi(0, WEB_CHOICES.map(func(choice: Array) -> String: return str(choice[0])).find(str(settings.web_ponies))))
	_cef_folder.text = str(settings.browser_folder)
	_filling = false
	_slides_note.text = "%d pictures in that folder." % preload("res://mods/watch_party/slideshow.gd").list(str(settings.slides_folder)).size() if not str(settings.slides_folder).is_empty() else "No folder yet."
	_show_web_note()

func _show_web_note() -> void:
	var engine: Node = hub.get("web") as Node
	var note := str(engine.get("note")) if engine != null else ""
	if engine != null and not is_instance_valid(engine.get("cef")):
		var folder := str(engine.call("artifacts_folder"))
		note = ("gdCEF found in %s; Chromium starts when you open a page." % folder) if not folder.is_empty() else note
		if folder.is_empty() and note.begins_with("The web browser has not"): note = "gdCEF not found. Download gdcef-0.20.0_godot-4.5.zip (release v0.20.0-godot4 at github.com/Lecrapouille/gdcef), unzip it, and put its cef_artifacts folder beside HomeEquestria.exe, or type its path above and press Check."
	_web_note.text = note if not note.is_empty() else "The browser is running."

func flush() -> void:
	_settings().save()

# --- slideshow ----------------------------------------------------------------------------------

func _folder_typed(_text: String) -> void:
	_folder_left()

func _folder_left() -> void:
	if _filling: return
	var settings := _settings()
	settings.slides_folder = _slides_folder.text.strip_edges()
	settings.save()
	open()

func _pick_folder() -> void:
	if not is_instance_valid(_dialog):
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.dir_selected.connect(_folder_picked)
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)

func _folder_picked(path: String) -> void:
	_slides_folder.text = path
	_folder_left()

func _seconds_changed(value: float) -> void:
	if _filling: return
	_settings().slides_seconds = value
	_settings().save()

func _when_idle_toggled(on: bool) -> void:
	if _filling: return
	_settings().slides_when_idle = on
	_settings().save()

func _start_slides() -> void:
	_folder_left()
	var tv := _tv()
	if tv == null: return
	if bool(tv.call("start_slides")) and menu != null: menu.call("close")
	else: _slides_note.text = "No pictures found in that folder."

# --- web ----------------------------------------------------------------------------------------

func _open_browser() -> void:
	var tv := _tv()
	if tv == null: return
	if not bool(tv.call("open_web")):
		_show_web_note()
		return
	if menu != null: menu.call("close")

func _home_changed(text: String) -> void:
	if _filling: return
	_settings().browser_home = text.strip_edges()

func _ponies_chosen(index: int) -> void:
	if _filling: return
	_settings().web_ponies = str(WEB_CHOICES[index][0])
	_settings().save()

func _check_cef() -> void:
	var settings := _settings()
	settings.browser_folder = _cef_folder.text.strip_edges()
	settings.save()
	var engine: Node = hub.get("web") as Node
	if engine != null: engine.call("retry")
	_show_web_note()
