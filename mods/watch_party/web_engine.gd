extends Node
## The televisions' web browser engine: gdCEF (Chromium Embedded Framework for Godot 4, MIT,
## github.com/Lecrapouille/gdcef), loaded at run time from its prebuilt `cef_artifacts` folder.
## Chromium is far too big to ship in a mod pack, so the player downloads gdCEF's Windows build
## for Godot 4.5 (v0.20.0: gdcef-0.20.0_godot-4.5.zip) and puts its `cef_artifacts` folder beside
## HomeEquestria.exe, or types its path in the TV menu. Nothing here runs until the first set
## opens the browser.
## One engine for the whole game (Chromium starts once per process); each set showing a page has
## its own browser view (web_view.gd). Logins and cookies live in a profile of their own,
## user://mods/data/watch_party/browser_profile, kept between sessions.

const FOLDER := "cef_artifacts"
## gdCEF 0.20's node class is "GdCEF" (its demos call it GDCEF); any spelling is taken.
const CLASS_LOWER := "gdcef"
## Chromium features switched off in gdCEF 0.20.0's libcef.dll (CEF 151.3.18, by its size) before
## it loads: [file offset of the base::Feature, its name pointer]. Its default state (the int after
## the pointer) goes from 1 (on) to 0. Every browser crash in playtests (2026-11-03/04: YouTube
## search, Google sign-in...) was Chrome's reading mode (ImmersiveReadAnything) looking up the tab
## of a page that changed its address by script (a "soft navigation", SoftNavigationDetection):
## an off-screen browser has no tab and Chromium read a null pointer (tabs::TabInterface::
## GetFromContents, fixed upstream later with MaybeGetFromContents). gdCEF passes Chromium no
## --disable-features, so the defaults are changed in the file; the original is kept beside it.
const LIBCEF_SIZE := 285378560
const LIBCEF_FEATURES := [[0x105a8300, 0x18f798ac8], [0x10549b10, 0x18ee884d8]]

var hub: Node
## The GDCEF node once started, else null.
var cef: Node
## Why the browser cannot open ("" once it can).
var note := "The web browser has not been started yet."
var _tried := false

## True when Chromium is up (starting it on the first call).
func ready() -> bool:
	if is_instance_valid(cef): return true
	if _tried: return false
	_tried = true
	var folder := artifacts_folder()
	if folder.is_empty():
		note = "The web browser needs gdCEF. Download gdcef-0.20.0_godot-4.5.zip (github.com/Lecrapouille/gdcef, release v0.20.0-godot4), unzip it and put its cef_artifacts folder beside HomeEquestria.exe, or type that folder's path in the TV menu."
		return false
	if _class_name().is_empty(): _switch_off_features(folder)
	if not _class_name().is_empty() or _load_extension(folder): return _start()
	return false

## LIBCEF_FEATURES off in the folder's libcef.dll when it is the known build (not loaded yet).
static func _switch_off_features(folder: String) -> void:
	var path := folder.path_join("windows").path_join("libcef.dll")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != LIBCEF_SIZE: return
	var wanted: Array = []
	for pair: Array in LIBCEF_FEATURES:
		file.seek(int(pair[0]))
		var pointer := file.get_64()
		var state := file.get_32()
		if pointer != int(pair[1]): return
		if state == 1: wanted.append(pair)
	file.close()
	if wanted.is_empty(): return
	var backup := path + ".original"
	if not FileAccess.file_exists(backup) and DirAccess.copy_absolute(path, backup) != OK:
		print("[watch_party] browser: could not keep a copy of libcef.dll, left as it is")
		return
	file = FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		print("[watch_party] browser: libcef.dll cannot be written (%d); the browser may crash on some sites" % FileAccess.get_open_error())
		return
	for pair: Array in wanted:
		file.seek(int(pair[0]) + 8)
		file.store_32(0)
	file.close()
	print("[watch_party] browser: switched off %d Chromium feature(s) in libcef.dll (the original is libcef.dll.original)" % wanted.size())

## Lets ready() try again (a folder typed in the menu).
func retry() -> void:
	if not is_instance_valid(cef): _tried = false

## The cef_artifacts folder: the one set in the menu, else beside the game, else "".
func artifacts_folder() -> String:
	var settings: RefCounted = hub.get("settings") as RefCounted if hub != null else null
	var candidates: Array[String] = []
	if settings != null and not str(settings.browser_folder).is_empty(): candidates.append(str(settings.browser_folder))
	var game_dir := OS.get_executable_path().get_base_dir()
	candidates.append(game_dir.path_join(FOLDER))
	candidates.append(game_dir.path_join("mods").path_join(FOLDER))
	for candidate: String in candidates:
		if not _extension_file(candidate).is_empty(): return candidate
	return ""

static func _extension_file(folder: String) -> String:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder): return ""
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() == "gdextension": return folder.path_join(file)
	return ""

static func _class_name() -> String:
	for candidate: String in ClassDB.get_class_list():
		if candidate.to_lower() == CLASS_LOWER: return candidate
	return ""

## Loads gdCEF's GDExtension. Its .gdextension names the library under res://cef_artifacts/,
## which an exported game reads beside its executable; a folder elsewhere gets a copy of the
## file with those paths made absolute (in the mod's data folder).
func _load_extension(folder: String) -> bool:
	var source := _extension_file(folder)
	var game_dir := OS.get_executable_path().get_base_dir().simplify_path()
	var path := source
	if folder.simplify_path() == game_dir.path_join(FOLDER).simplify_path():
		path = "res://%s/%s" % [FOLDER, source.get_file()]
	else:
		var text := FileAccess.get_file_as_string(source)
		var local := Mods.data_folder("watch_party").path_join("gdcef_here.gdextension")
		var file := FileAccess.open(local, FileAccess.WRITE)
		if file != null:
			file.store_string(text.replace("res://%s/" % FOLDER, folder.replace("\\", "/").trim_suffix("/") + "/"))
			file.close()
			path = local
	var status := GDExtensionManager.load_extension(path)
	if status != GDExtensionManager.LOAD_STATUS_OK and status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED and path != source:
		status = GDExtensionManager.load_extension(source)
	print("[watch_party] browser: loading gdCEF from %s: status %d" % [path, status])
	if _class_name().is_empty():
		note = "gdCEF in %s did not load (status %d). It must be the build for Godot 4.5 (gdcef-0.20.0_godot-4.5.zip); see the game's log." % [folder, status]
		return false
	return true

func _start() -> bool:
	var kind := _class_name()
	var node: Variant = ClassDB.instantiate(kind)
	if not node is Node:
		note = "gdCEF loaded, but its %s node could not be made." % kind
		return false
	cef = node
	cef.name = "WatchPartyCef"
	add_child(cef)
	var profile := ProjectSettings.globalize_path(Mods.data_folder("watch_party").path_join("browser_profile"))
	DirAccess.make_dir_recursive_absolute(profile)
	var config := {"incognito": false, "cache_path": profile, "root_cache_path": profile, "locale": "en-US",
		"enable_media_stream": false, "log_severity": "warning", "log_file": profile.path_join("cef.log"),
		# gdCEF opens a remote debugging port (7777) unless told not to: any program on the PC could
		# drive the browser with the player's logins through it.
		"remote_debugging_port": 0}
	if not bool(cef.call("initialize", config)):
		note = "Chromium did not start: " + str(cef.call("get_error"))
		print("[watch_party] browser: ", note)
		cef.queue_free()
		cef = null
		return false
	note = ""
	print("[watch_party] browser: Chromium %s ready, profile %s" % [str(cef.call("get_full_version")), profile])
	return true

func _exit_tree() -> void:
	if is_instance_valid(cef) and cef.has_method("shutdown"): cef.call("shutdown")
