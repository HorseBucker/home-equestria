extends RefCounted
## The player's TV settings, kept outside any world in user://mods/data/watch_party/settings.json:
## library folders, an ffmpeg path, the volume, the picture (CRT look, fit or fill), where each
## file was left off and which sound and subtitle track it plays with, and how often ponies watching
## along talk (watch_company.gd PACES).

const FILE := "settings.json"
const MEDIA := ["mp4", "mkv", "avi", "mov", "webm", "m4v", "wmv", "flv", "mpg", "mpeg", "ts", "m2ts", "ogv", "mp3", "flac", "ogg", "wav", "m4a"]
const MAX_RESUME := 300
const MAX_FILES := 3000
const MAX_DEPTH := 5

var folder := ""
var folders: PackedStringArray = PackedStringArray()
var ffmpeg_path := ""
var volume_db := -6.0
var crt := true
var fill := false
var pace := "normal"
## The photo slideshow (slideshow.gd): its folder, seconds per picture, and whether it starts by
## itself on a set that has been off a while (tv_set.gd IDLE_SECONDS; off by default).
var slides_folder := ""
var slides_seconds := 8.0
var slides_when_idle := false
## The web browser (web_engine.gd, web_view.gd): its first page, where gdCEF's cef_artifacts folder
## is when it is not beside the game, and whether ponies watching along may see the pages.
var browser_home := ""
var browser_folder := ""
## How much of the browser ponies watching along may know (dev 2026-11-06): "none" (only that he
## is busy with something of his own), "words" (the page's title, address and some of its text;
## YouTube titles and captions) or "pictures" (also the page itself, through pony vision).
var web_ponies := "none"
const WEB_LEVELS := ["none", "words", "pictures"]
## The browser's zoom in percent (web_view.gd ZOOMS), and the folder its file dialog opens in.
var browser_zoom := 125
var pick_folder := ""
## The folder the browser's Save as last saved to.
var save_folder := ""
## The browser's tabs when it was last used (their addresses) and which one was showing.
var browser_tabs: Array = []
var browser_tab := 0
## What was on when a set was last switched off ("video", "web", "slides"): it comes back on with it.
var last_on := ""
## Pony vision (vision_pool.gd): {enabled, order ("turns" or "in_order"), next (whose turn), apis: [
## {id, name, source ("own", "dialogue" or "preset"), preset, provider, base_url, api_key, model,
## daily (0 = no limit), best, best_turns}]}. Keys are kept here in plain text, like the game's own.
var vision: Dictionary = {"enabled": false, "order": "turns", "next": 0, "apis": []}
## Calls made today per API id: {"date": Pacific date, "counts": {id: n}}.
var vision_usage: Dictionary = {"date": "", "counts": {}}
## The magic (magic_quest.gd): skipped, every set works as soon as it is placed. Set in
## the setup panel (setup_panel.gd), for every world.
var skip_quest := false
## The light a set casts on the room from its picture (tv_set.gd _update_glow): "full", "near"
## (a short reach, for slower graphics cards) or "off". Settings > Watch Party (settings_tab.gd).
var room_light := "full"
## The browser's load on the computer (Settings > Watch Party, dev 2026-11-06): frames a second each
## page draws (30 or 15), the page's pixels as a share of the set's own (100 or 75, the zoom
## scaled to match so pages look the same, only softer), whether a video or sound on a tab you
## leave is paused, and whether the tabs open last time come back when the browser opens.
var browser_fps := 30
var browser_scale := 100
var browser_pause_hidden := false
var browser_restore := true
## The setup panel opened by itself once already (main.gd after_power_up).
var setup_shown := false
var resume: Dictionary = {}          # absolute file path -> seconds
var tracks: Dictionary = {}          # absolute file path -> {"audio": int, "subtitle": choice key}
var library: PackedStringArray = PackedStringArray()

func open(data_folder: String) -> void:
	folder = data_folder
	var path := folder.path_join(FILE)
	if not FileAccess.file_exists(path): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return
	var doc: Dictionary = parsed
	if doc.get("folders") is Array:
		for entry: Variant in doc.folders:
			if entry is String and not (entry as String).is_empty(): folders.append(entry)
	ffmpeg_path = str(doc.get("ffmpeg", ""))
	var volume: Variant = doc.get("volume_db", -6.0)
	# -80 is muted (tv_set.gd MUTED_DB); otherwise -40 to +6 dB.
	if volume is float or volume is int: volume_db = -80.0 if float(volume) <= -80.0 else clampf(float(volume), -40.0, 6.0)
	crt = bool(doc.get("crt", true))
	fill = bool(doc.get("fill", false))
	pace = str(doc.get("pace", "normal"))
	slides_folder = str(doc.get("slides_folder", ""))
	var every: Variant = doc.get("slides_seconds", 8.0)
	if every is float or every is int: slides_seconds = clampf(float(every), 2.0, 600.0)
	slides_when_idle = bool(doc.get("slides_when_idle", false))
	browser_home = str(doc.get("browser_home", ""))
	browser_folder = str(doc.get("browser_folder", ""))
	# Before 0.9.4 it was one switch, ponies_see_web (on: words, and pictures with vision on).
	web_ponies = str(doc.get("web_ponies", "pictures" if bool(doc.get("ponies_see_web", false)) else "none"))
	if web_ponies not in WEB_LEVELS: web_ponies = "none"
	var zoom: Variant = doc.get("browser_zoom", 125)
	if zoom is float or zoom is int: browser_zoom = clampi(int(zoom), 25, 500)
	pick_folder = str(doc.get("pick_folder", ""))
	save_folder = str(doc.get("save_folder", ""))
	last_on = str(doc.get("last_on", ""))
	skip_quest = bool(doc.get("skip_quest", false))
	room_light = str(doc.get("room_light", "full"))
	if room_light not in ["full", "near", "off"]: room_light = "full"
	browser_fps = 15 if int(doc.get("browser_fps", 30)) == 15 else 30
	browser_scale = 75 if int(doc.get("browser_scale", 100)) == 75 else 100
	browser_pause_hidden = bool(doc.get("browser_pause_hidden", false))
	browser_restore = bool(doc.get("browser_restore", true))
	setup_shown = bool(doc.get("setup_shown", false))
	browser_tabs.clear()
	var tabs: Variant = doc.get("browser_tabs", [])
	if tabs is Array:
		for address: Variant in tabs:
			if address is String and (address as String).begins_with("http"): browser_tabs.append(address)
	browser_tab = int(doc.get("browser_tab", 0)) if doc.get("browser_tab", 0) is float or doc.get("browser_tab", 0) is int else 0
	if doc.get("vision") is Dictionary:
		var saved: Dictionary = doc.vision
		vision.enabled = bool(saved.get("enabled", false))
		vision.order = "in_order" if str(saved.get("order", "turns")) == "in_order" else "turns"
		vision.next = int(saved.get("next", 0))
		if saved.get("apis") is Array:
			for entry: Variant in saved.apis:
				if entry is Dictionary: vision.apis.append((entry as Dictionary).duplicate())
	if doc.get("vision_usage") is Dictionary and (doc.vision_usage as Dictionary).get("counts") is Dictionary:
		vision_usage = {"date": str(doc.vision_usage.get("date", "")), "counts": (doc.vision_usage.counts as Dictionary).duplicate()}
	if doc.get("tracks") is Dictionary:
		for key: Variant in doc.tracks:
			if key is String and doc.tracks[key] is Dictionary: tracks[key] = (doc.tracks[key] as Dictionary).duplicate()
	if doc.get("resume") is Dictionary:
		for key: Variant in doc.resume:
			var seconds: Variant = doc.resume[key]
			if key is String and (seconds is float or seconds is int): resume[key] = float(seconds)

func save() -> void:
	if folder.is_empty(): return
	while resume.size() > MAX_RESUME: resume.erase(resume.keys()[0])
	while tracks.size() > MAX_RESUME: tracks.erase(tracks.keys()[0])
	var file := FileAccess.open(folder.path_join(FILE), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"version": 1, "folders": Array(folders), "ffmpeg": ffmpeg_path, "volume_db": volume_db, "crt": crt, "fill": fill, "pace": pace, "slides_folder": slides_folder, "slides_seconds": slides_seconds, "slides_when_idle": slides_when_idle,
		"browser_home": browser_home, "browser_folder": browser_folder, "web_ponies": web_ponies, "browser_zoom": browser_zoom, "pick_folder": pick_folder, "save_folder": save_folder, "browser_tabs": browser_tabs, "browser_tab": browser_tab, "last_on": last_on, "skip_quest": skip_quest, "room_light": room_light, "browser_fps": browser_fps, "browser_scale": browser_scale, "browser_pause_hidden": browser_pause_hidden, "browser_restore": browser_restore, "setup_shown": setup_shown, "vision": vision, "vision_usage": vision_usage, "resume": resume, "tracks": tracks}, "\t"))
	file.close()

func add_folder(path: String) -> void:
	if path.is_empty() or path in folders: return
	folders.append(path)
	save()
	scan()

func clear_folders() -> void:
	folders = PackedStringArray()
	library = PackedStringArray()
	save()

## Every media file under the library folders, sorted by name.
func scan() -> void:
	var found: Array[String] = []
	for root: String in folders: _scan(root, 0, found)
	found.sort_custom(func(a: String, b: String) -> bool: return a.get_file().naturalnocasecmp_to(b.get_file()) < 0)
	library = PackedStringArray(found)

func _scan(dir: String, depth: int, found: Array[String]) -> void:
	if depth > MAX_DEPTH or found.size() >= MAX_FILES or not DirAccess.dir_exists_absolute(dir): return
	for name: String in DirAccess.get_files_at(dir):
		if name.get_extension().to_lower() in MEDIA:
			found.append(dir.path_join(name))
			if found.size() >= MAX_FILES: return
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."): _scan(dir.path_join(sub), depth + 1, found)

## Where to start `path`: where it was left, unless that was within a minute of its end.
func resume_at(path: String, duration: float) -> float:
	var at: float = float(resume.get(path, 0.0))
	if duration > 0.0 and at > duration - 60.0: return 0.0
	return at

func remember(path: String, seconds: float) -> void:
	if path.is_empty(): return
	resume.erase(path)
	resume[path] = snappedf(seconds, 0.1)

## The video watched last that is still there ("" when none): remember() keeps it at the end.
func last_watched() -> String:
	var paths: Array = resume.keys()
	for i in range(paths.size() - 1, -1, -1):
		if FileAccess.file_exists(str(paths[i])): return str(paths[i])
	return ""

## The sound track and subtitle choice key last used with `path`.
func tracks_for(path: String) -> Dictionary:
	var row: Variant = tracks.get(path, {})
	var chosen: Dictionary = row if row is Dictionary else {}
	return {"audio": int(chosen.get("audio", 0)), "subtitle": str(chosen.get("subtitle", "off"))}

func remember_tracks(path: String, audio: int, subtitle: String) -> void:
	if path.is_empty(): return
	tracks.erase(path)
	tracks[path] = {"audio": audio, "subtitle": subtitle}
	save()
