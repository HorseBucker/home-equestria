extends VBoxContainer
## Watch Party setup, the page itself: whether the two downloads the mod needs are found, with
## buttons for their download pages and the game folder, and the switch that skips the magic
## (watch_settings.gd skip_quest). Shown as the TV menu's Setup tab (tv_menu.gd) and, where no set
## works yet, in a panel of its own (setup_panel.gd).
## - ffmpeg plays the videos (ffmpeg_tools.gd looks in the game folder, also in an unzipped
##   "ffmpeg..." folder there, and in the mod's data folder).
## - gdCEF runs the web browser, optional (web_engine.gd: its cef_artifacts folder in the game folder).
## - OCR reads picture subtitles for the ponies (ocr_engine.gd): built into Windows; Tesseract on Linux.

const FFMPEG_PAGE := "https://www.gyan.dev/ffmpeg/builds/"
const GDCEF_PAGE := "https://github.com/Lecrapouille/gdcef/releases/tag/v0.20.0-godot4"

var hub: Node
var _ffmpeg: Label
var _browser: Label
var _ocr: Label
var _skip: CheckButton
## The magic's section (Settings → Watch Party has its own row for it, so it leaves it out).
var show_magic := true
## The colour of a download found (dev 2026-11-07: green, not red).
const FOUND := Color(0.5, 0.88, 0.55)
## Where to find this again: only when the setup opened by itself (dev 2026-11-07).
var _again: Label
var _refresh := 0.0

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_text("The televisions need two free downloads to do everything. Put both in the game folder, next to HomeEquestria.exe."))
	add_child(_label("Videos: ffmpeg", "Subheading"))
	_ffmpeg = _label("")
	_ffmpeg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_ffmpeg)
	add_child(_text("On the download page, under \"release builds\", get ffmpeg-release-essentials.zip. Unzip it and put the whole folder in the game folder (or just ffmpeg.exe and ffprobe.exe from its bin folder)."))
	add_child(_row([_button("Open download page", _open.bind(FFMPEG_PAGE)), _button("Open game folder", _open_game_folder), _button("Check again", _check_ffmpeg)]))
	add_child(_label("Web browser: gdCEF (optional)", "Subheading"))
	_browser = _label("")
	_browser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_browser)
	add_child(_text("Only needed for the browser on the screen. On the download page get gdcef-0.20.0_godot-4.5.zip (about 1 GB; newer versions will not load in this game). Unzip it and put its cef_artifacts folder in the game folder."))
	add_child(_row([_button("Open download page", _open.bind(GDCEF_PAGE)), _button("Open game folder", _open_game_folder), _button("Check again", _check_browser)]))
	add_child(_label("Picture subtitles: OCR", "Subheading"))
	_ocr = _label("")
	_ocr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_ocr)
	if OS.get_name() == "Windows": add_child(_text("Reads Blu-ray and DVD subtitles so ponies can follow films without a subtitle file. Built into Windows: nothing to download."))
	else: add_child(_text("Reads Blu-ray and DVD subtitles so ponies can follow films without a subtitle file. Install Tesseract with your package manager (tesseract-ocr, with its English data), then press Check again."))
	add_child(_row([_button("Check again", _check_ocr)]))
	_skip = CheckButton.new()
	_skip.text = "Ozone-powered TVs"
	_skip.toggled.connect(_skip_toggled)
	if show_magic:
		add_child(_label("Skip the quest", "Subheading"))
		add_child(_text("Skips the quest to get the TVs working: every TV works as soon as you set it down. Why? Because Equestria's air is thick with ozone, that's why."))
		add_child(_skip)
	_again = _text("Open this again any time: hold the TV remote, right click (VR: pull its trigger twice) and pick the Setup tab. More settings: the game's Settings → Watch Party.")
	_again.visible = false
	add_child(_again)

func _label(text: String, variation := "") -> Label:
	var label := Label.new(); label.text = text
	if not variation.is_empty(): label.theme_type_variation = variation
	return label

func _text(text: String) -> Label:
	var label := _label(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300, 0)
	return label

func _button(text: String, pressed: Callable, variation := "") -> Button:
	var button := Button.new(); button.text = text
	if not variation.is_empty(): button.theme_type_variation = variation
	button.pressed.connect(pressed)
	return button

func _row(children: Array) -> Control:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8)
	for child: Variant in children: row.add_child(child as Control)
	return row

## Filled from the settings (the page shown or the panel opened); `by_itself`: the setup opened on
## its own after the first set worked (main.gd after_power_up), so it says where to find it again.
func open(by_itself := false) -> void:
	_again.visible = by_itself
	var settings: RefCounted = hub.get("settings") as RefCounted
	_skip.set_pressed_no_signal(bool(settings.skip_quest))
	_show_status()

## Nothing unsaved: every change saves at once (tv_menu.gd calls this for each page).
func flush() -> void:
	pass

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_refresh -= delta
	if _refresh > 0.0: return
	_refresh = 0.5
	_show_status()

func _show_status() -> void:
	var ffmpeg := str(hub.get("ffmpeg"))
	if bool(hub.get("_searching")): _ffmpeg.text = "Looking for ffmpeg…"
	elif ffmpeg.is_empty(): _ffmpeg.text = "Not found yet: videos will not play."
	else: _ffmpeg.text = "Found: " + ffmpeg
	var web: Node = hub.get("web") as Node
	var folder := str(web.call("artifacts_folder")) if web != null else ""
	_browser.text = "Not found: the browser will not open." if folder.is_empty() else "Found: " + folder
	_ffmpeg.theme_type_variation = "Warn" if ffmpeg.is_empty() and not bool(hub.get("_searching")) else ""
	_browser.theme_type_variation = "Warn" if folder.is_empty() else ""
	var ocr: Variant = hub.get("ocr")
	var ocr_state := str((ocr as RefCounted).get("state")) if ocr is RefCounted else "missing"
	if ocr_state == "ready": _ocr.text = "Found: " + str((ocr as RefCounted).get("engine"))
	elif ocr_state == "unknown": _ocr.text = "Checking…"
	else: _ocr.text = "Not found: " + str((ocr as RefCounted).get("problem") if ocr is RefCounted else "")
	_ocr.theme_type_variation = "Warn" if ocr_state == "missing" else ""
	for pair: Array in [[_ffmpeg, not ffmpeg.is_empty()], [_browser, not folder.is_empty()], [_ocr, ocr_state == "ready"]]:
		if bool(pair[1]): (pair[0] as Label).add_theme_color_override("font_color", FOUND)
		else: (pair[0] as Label).remove_theme_color_override("font_color")

func _open(url: String) -> void:
	OS.shell_open(url)

func _open_game_folder() -> void:
	OS.shell_open(OS.get_executable_path().get_base_dir())

func _check_ffmpeg() -> void:
	hub.call("find_ffmpeg")
	_show_status()

func _check_browser() -> void:
	var web: Node = hub.get("web") as Node
	if web != null: web.call("retry")
	_show_status()

func _check_ocr() -> void:
	hub.call("check_ocr")
	_show_status()

func _skip_toggled(on: bool) -> void:
	var settings: RefCounted = hub.get("settings") as RefCounted
	settings.skip_quest = on
	settings.save()
	print("[watch_party] ozone-powered TVs %s" % ("on: the magic quest is skipped, every set works" if on else "off: the magic quest is on"))
