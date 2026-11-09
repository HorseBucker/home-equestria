extends RefCounted
## Finding ffmpeg and asking ffprobe what a file holds. Every call here blocks while a process runs,
## so callers run them on a worker thread.
## ffmpeg is looked for, in order: the path set in the TV menu, the mod's data folder
## (user://mods/data/watch_party/, also its bin/ folder), the game's folder (also an unzipped
## ffmpeg folder in it), then PATH.

static func executable(name: String) -> String:
	return name + ".exe" if OS.get_name() == "Windows" else name

## Places to try for ffmpeg, best first. The configured path may be the exe or a folder holding it
## (or its bin\ folder); a downloaded build's whole folder may sit in the data folder as it unzips.
static func candidates(configured: String, data_dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var name := executable("ffmpeg")
	var chosen := configured.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if not chosen.is_empty():
		if DirAccess.dir_exists_absolute(chosen):
			out.append(chosen.path_join(name))
			out.append(chosen.path_join("bin").path_join(name))
		else:
			out.append(chosen)
	var data := ProjectSettings.globalize_path(data_dir)
	out.append(data.path_join(name))
	out.append(data.path_join("bin").path_join(name))
	if DirAccess.dir_exists_absolute(data):
		for sub: String in DirAccess.get_directories_at(data):
			out.append(data.path_join(sub).path_join("bin").path_join(name))
			out.append(data.path_join(sub).path_join(name))
	if OS.has_feature("template"):
		# The game folder (the setup panel's advice): ffmpeg.exe there, or the whole unzipped
		# "ffmpeg-...-essentials_build" folder with its bin\ inside.
		var game_dir := OS.get_executable_path().get_base_dir()
		out.append(game_dir.path_join(name))
		for sub: String in DirAccess.get_directories_at(game_dir):
			if not sub.to_lower().begins_with("ffmpeg"): continue
			out.append(game_dir.path_join(sub).path_join("bin").path_join(name))
			out.append(game_dir.path_join(sub).path_join(name))
	out.append("ffmpeg")
	return out

## The first candidate that runs, or "".
static func find(configured: String, data_dir: String) -> String:
	for candidate: String in candidates(configured, data_dir):
		if candidate != "ffmpeg" and not FileAccess.file_exists(candidate): continue
		var output: Array = []
		if OS.execute(candidate, PackedStringArray(["-hide_banner", "-version"]), output, false, false) == 0: return candidate
	return ""

## ffprobe beside the ffmpeg in use ("ffprobe" when ffmpeg came from PATH).
static func ffprobe_for(ffmpeg: String) -> String:
	if ffmpeg == "ffmpeg" or ffmpeg.get_base_dir().is_empty(): return "ffprobe"
	return ffmpeg.get_base_dir().path_join(executable("ffprobe"))

## {ok, duration, video, width, height (the first picture's), audio: [{track, language, title}],
## subtitles: [{track, language, title, codec, width, height (a picture track's canvas)}], error}.
## Without ffprobe the file is assumed to have a picture and sound of unknown length.
static func probe(ffprobe: String, file: String) -> Dictionary:
	var info := {"ok": true, "hdr": false, "duration": 0.0, "video": true, "audio": [{"track": 0, "language": "", "title": ""}], "subtitles": [], "error": ""}
	var output: Array = []
	var code := OS.execute(ffprobe, PackedStringArray(["-v", "error", "-print_format", "json", "-show_format", "-show_streams", file]), output, false, false)
	if code != 0 or output.is_empty():
		if not FileAccess.file_exists(file): return {"ok": false, "error": "The file is gone: " + file.get_file()}
		return info
	var parsed: Variant = JSON.parse_string(str(output[0]))
	if not parsed is Dictionary: return info
	var doc: Dictionary = parsed
	var format: Variant = doc.get("format")
	if format is Dictionary: info.duration = str((format as Dictionary).get("duration", "0")).to_float()
	var audio: Array = []
	var subtitles: Array = []
	var video := false
	var streams: Variant = doc.get("streams")
	if streams is Array:
		for stream: Variant in streams:
			if not stream is Dictionary: continue
			var row: Dictionary = stream
			var tags: Dictionary = row.get("tags", {}) if row.get("tags") is Dictionary else {}
			var kind := str(row.get("codec_type", ""))
			var disposition: Dictionary = row.get("disposition", {}) if row.get("disposition") is Dictionary else {}
			if kind == "video" and int(disposition.get("attached_pic", 0)) == 0:
				if not video:
					info.hdr = str(row.get("color_transfer", "")) in ["smpte2084", "arib-std-b67"]
					info.width = int(row.get("width", 0)); info.height = int(row.get("height", 0))
				video = true
			elif kind == "audio": audio.append({"track": audio.size(), "language": str(tags.get("language", "")), "title": str(tags.get("title", ""))})
			elif kind == "subtitle": subtitles.append({"track": subtitles.size(), "language": str(tags.get("language", "")), "title": str(tags.get("title", "")), "codec": str(row.get("codec_name", "")),
					"width": int(row.get("width", 0)), "height": int(row.get("height", 0))})
	info.video = video
	info.audio = audio
	info.subtitles = subtitles
	return info

static var _tonemap_checked := {}

## Whether `ffmpeg` has the zscale and tonemap filters (HDR films; media_player.gd). Asked once.
static func can_tonemap(ffmpeg: String) -> bool:
	if _tonemap_checked.has(ffmpeg): return bool(_tonemap_checked[ffmpeg])
	var output: Array = []
	var code := OS.execute(ffmpeg, PackedStringArray(["-hide_banner", "-filters"]), output, false, false)
	var text := str(output[0]) if not output.is_empty() else ""
	var ok := code == 0 and " zscale " in text and " tonemap " in text
	_tonemap_checked[ffmpeg] = ok
	return ok
