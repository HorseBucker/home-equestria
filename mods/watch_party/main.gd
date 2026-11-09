extends Node
## Watch Party: a television to buy at the market, place at home and watch your own videos on
## (ffmpeg plays them), with ponies you invite watching along. This entry node is the hub every set
## talks to (tv_set.gd HUB): the player's settings and library (watch_settings.gd), where ffmpeg is,
## the remote's controls added to each world (tv_controls.gd), the desktop TV menu (tv_menu.gd) and
## the ponies watching along (watch_company.gd; watch_invite.gd brings them). Only one set plays at
## a time.
## The story (finds.gd): the sets lie in the Everfree for the first days (forest_finds.gd), then
## sell at the market, and work once somepony has woken one of their kind with magic (magic_quest.gd;
## Trixie may blow one up instead: tv_blast.gd). The
## setup panel (setup_panel.gd) says what is still to download.

const SETTINGS := preload("res://mods/watch_party/watch_settings.gd")
const TOOLS := preload("res://mods/watch_party/ffmpeg_tools.gd")
const CONTROLS := preload("res://mods/watch_party/tv_controls.gd")
## Loaded only once ext_loader.gd has extended the game scripts: tv_menu.gd and watch_company.gd
## reach some of them through their own preloads, and a game script loaded before its extension
## keeps the game's version.
const MENU := "res://mods/watch_party/tv_menu.gd"
const COMPANY := "res://mods/watch_party/watch_company.gd"
const FOREST := "res://mods/watch_party/forest_finds.gd"
const QUEST := "res://mods/watch_party/magic_quest.gd"
const BLAST := "res://mods/watch_party/tv_blast.gd"
const SETUP := "res://mods/watch_party/setup_panel.gd"
## Settings → Watch Party (the game's settings page, patched).
const SETTINGS_TAB := "res://mods/watch_party/settings_tab.gd"
## The once-per-world card saying where the sets are.
const WELCOME := "res://mods/watch_party/welcome.gd"
## The setup panel opens by itself this long after the first set works, if something is missing.
const SETUP_DELAY := 6.0
## Applies the mod's script extensions (ext/); preloads no game script itself.
const EXTENSIONS := preload("res://mods/watch_party/ext_loader.gd")
const WEB := preload("res://mods/watch_party/web_engine.gd")
const CATALOG := preload("res://mods/watch_party/catalog.gd")
## Reads subtitles off pictures (picture_subs.gd): Windows' own OCR, or Tesseract.
const OCR := preload("res://mods/watch_party/ocr_engine.gd")
const OCR_TIDY_SECONDS := 10.0
const ID := "watch_party"

var settings: RefCounted
## The ffmpeg in use, or "" while none was found.
var ffmpeg := ""
var _searching := false
var _search: Thread
var _controls: Node
var _menu: CanvasLayer
var company: Node
## The sets' web browser engine (web_engine.gd; Chromium starts on first use).
var web: Node
var forest: Node
var quest: Node
var blast: Node
var settings_tab: Node
var welcome: Node
var _setup: CanvasLayer
## The OCR every set shares (ocr_engine.gd); checked on a worker thread at start (check_ocr).
var ocr: RefCounted
var _ocr_check: Thread
var _ocr_tidy := OCR_TIDY_SECONDS

## The Mods autoload makes this node before the title screen, ahead of every game script the
## extensions change (ext_loader.gd).
func _init() -> void:
	EXTENSIONS.apply(Mods.data_folder(ID).path_join("ext"))

func _ready() -> void:
	settings = SETTINGS.new()
	settings.open(Mods.data_folder(ID))
	company = load(COMPANY).new()
	company.name = "WatchCompany"
	company.hub = self
	add_child(company)
	web = WEB.new()
	web.name = "WebEngine"
	web.hub = self
	add_child(web)
	forest = _part(FOREST, "ForestFinds")
	quest = _part(QUEST, "MagicQuest")
	blast = _part(BLAST, "TvBlast")
	settings_tab = _part(SETTINGS_TAB, "SettingsTab")
	welcome = _part(WELCOME, "Welcome")
	find_ffmpeg()
	ocr = OCR.new()
	check_ocr()
	Mods.world_ready.connect(_on_world)
	Mods.world_closed.connect(_on_world_closed)
	if is_instance_valid(Mods.game): _on_world(Mods.game)

## One of the story's nodes; null (and a warning) when its script does not load, so the rest of
## the mod still runs (playtest 2026-11-05: a parse error in the quest stopped the hub).
func _part(path: String, node_name: String) -> Node:
	var script := load(path) as Script
	var node: Variant = script.new() if script != null and script.can_instantiate() else null
	if not node is Node:
		push_warning("[watch_party] %s did not load; that part of the mod is off" % path)
		return null
	(node as Node).name = node_name
	(node as Node).set("hub", self)
	add_child(node as Node)
	return node as Node

func _exit_tree() -> void:
	_close_menu()
	if is_instance_valid(_controls): _controls.queue_free()
	for tv: Node in get_tree().get_nodes_in_group("watch_tvs"):
		if tv.has_method("stop"): tv.stop()
	if _search != null and _search.is_started(): _search.wait_to_finish()
	if _ocr_check != null and _ocr_check.is_started(): _ocr_check.wait_to_finish()
	if ocr != null: ocr.call("close")

func _on_world(game: Node) -> void:
	CATALOG.paint_icons()
	if is_instance_valid(forest): forest.call("world", game)
	if is_instance_valid(quest): quest.call("world", game)
	if is_instance_valid(blast): blast.call("world", game)
	if is_instance_valid(welcome): welcome.call("world")
	if is_instance_valid(_controls): _controls.queue_free()
	_controls = CONTROLS.new()
	_controls.name = "WatchPartyControls"
	_controls.hub = self
	# The root's last child hears keys first (tv_controls.gd), ahead of the briefcase.
	game.get_tree().root.add_child.call_deferred(_controls)

func _on_world_closed(_game: Node) -> void:
	_close_menu()
	if is_instance_valid(_controls): _controls.queue_free()
	_controls = null
	settings.save()

## Looks for ffmpeg on a worker thread (each candidate runs `ffmpeg -version`).
func find_ffmpeg() -> void:
	if _searching: return
	_searching = true
	if _search != null and _search.is_started(): _search.wait_to_finish()
	_search = Thread.new()
	_search.start(_run_search.bind(str(settings.ffmpeg_path), Mods.data_folder(ID)))

func _run_search(configured: String, data_dir: String) -> void:
	var found := TOOLS.find(configured, data_dir)
	call_deferred("_found", found)

func _found(found: String) -> void:
	if _search != null and _search.is_started(): _search.wait_to_finish()
	_search = null
	_searching = false
	ffmpeg = found
	print("[watch_party] ffmpeg: ", found if not found.is_empty() else "not found")

## Looks for an OCR engine on a worker thread (Windows: starts its OCR once through PowerShell).
func check_ocr() -> void:
	if _ocr_check != null:
		if _ocr_check.is_alive(): return
		_ocr_check.wait_to_finish()
	_ocr_check = Thread.new()
	_ocr_check.start(func() -> void:
		ocr.call("check")
		print("[watch_party] OCR: ", str(ocr.get("engine")) if str(ocr.get("state")) == "ready" else "none (%s)" % str(ocr.get("problem"))))

## Now and then: an idle OCR process is closed.
func _process(delta: float) -> void:
	_ocr_tidy -= delta
	if _ocr_tidy > 0.0: return
	_ocr_tidy = OCR_TIDY_SECONDS
	if ocr != null and (_ocr_check == null or not _ocr_check.is_alive()): ocr.call("tidy")

## Why the TV cannot play yet, or "" when it can.
func ffmpeg_note() -> String:
	if not ffmpeg.is_empty(): return ""
	if _searching: return "Looking for ffmpeg…"
	return "The TV needs ffmpeg to play videos: put its unzipped folder next to HomeEquestria.exe (TV menu → Setup)."

func open_menu(tv: Node3D) -> void:
	if not is_instance_valid(_menu):
		_menu = load(MENU).new()
		_menu.name = "WatchPartyMenu"
		_menu.hub = self
		# Last child of the root: it hears Escape before the game's own menus do.
		get_tree().root.add_child(_menu)
	_menu.open(tv)

func _close_menu() -> void:
	if is_instance_valid(_menu):
		_menu.close()
		_menu.queue_free()
	_menu = null
	if is_instance_valid(_setup):
		_setup.close()
		_setup.queue_free()
	_setup = null

## The setup panel (the TV remote's right click, or two trigger pulls in VR, where no set is on).
func open_setup(by_itself := false) -> void:
	if not is_instance_valid(_setup):
		_setup = load(SETUP).new()
		_setup.name = "WatchPartySetup"
		_setup.hub = self
		get_tree().root.add_child(_setup)
	_setup.open(by_itself)

## A text field on a TV screen has the focus in TV mode (a page's box, the address bar): T is a
## letter there, not push to talk (ext/speech_input.gd).
func typing_on_tv() -> bool:
	var screen: Variant = _controls.get("screen_input") if is_instance_valid(_controls) else null
	if not is_instance_valid(screen) or not bool((screen as Node).call("active")): return false
	var tv: Variant = (screen as Node).get("tv")
	var web: Variant = (tv as Node).get("web") if is_instance_valid(tv) and str((tv as Node).get("source")) == "web" else null
	return is_instance_valid(web) and (web as Node).has_method("wants_text") and bool((web as Node).call("wants_text"))

## The TV menu or the setup is open (the remote's buttons wait meanwhile, tv_controls.gd).
func menu_open() -> bool:
	return (is_instance_valid(_menu) and _menu.visible) or (is_instance_valid(_setup) and _setup.visible)

func _desktop() -> bool:
	var inventory: Variant = Mods.game.get("inventory") if is_instance_valid(Mods.game) else null
	return is_instance_valid(inventory) and bool((inventory as Node).get("_desktop"))

## A set works (tv_set.gd _activate). The first time with the quest skipped also counts as the
## first set working.
func tv_working(_tv: Node) -> void:
	if bool(settings.skip_quest): after_power_up()

## The first set works now (woken with magic, magic_quest.gd): once, if ffmpeg or gdCEF is
## missing, the setup panel opens a few seconds later, after her words.
func after_power_up() -> void:
	if bool(settings.setup_shown): return
	var browser := str(web.call("artifacts_folder")) if is_instance_valid(web) else ""
	if not ffmpeg.is_empty() and not browser.is_empty(): return
	settings.setup_shown = true
	settings.save()
	get_tree().create_timer(SETUP_DELAY).timeout.connect(open_setup.bind(true))

## A set started playing: the others stop, so only one set is heard.
func tv_playing(tv: Node) -> void:
	for other: Node in get_tree().get_nodes_in_group("watch_tvs"):
		# A silent slideshow elsewhere keeps going.
		if other != tv and other.has_method("stop") and str(other.get("source")) != "slides": other.stop()

func tv_gone(tv: Node) -> void:
	if is_instance_valid(_menu) and _menu.get("tv") == tv: _menu.close()
