extends RefCounted
## Subtitles for one television. choices() lists what a file offers: subtitle streams inside it
## (ffprobe) and subtitle files beside it with the same name. Text subtitles (SRT, ASS, WebVTT…)
## are read here as timed lines, which the set draws on its screen and which part 2 hands the
## ponies; picture subtitles (Blu-ray PGS, DVD) have no text, so media_player.gd has ffmpeg draw
## them into the picture instead.
## A text stream is pulled out by ffmpeg as SRT on a worker thread, from where playback starts and
## at eight times normal speed (-readrate 8), so it stays ahead of the film without reading the
## whole file at once; a seek starts it again there.

const TEXT_CODECS := ["subrip", "srt", "ass", "ssa", "mov_text", "webvtt", "text", "microdvd", "jacosub", "sami", "realtext", "subviewer", "subviewer1", "stl", "mpl2", "vplayer", "pjs"]
const PICTURE_CODECS := ["hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle", "xsub", "dvb_teletext"]
const FILE_TYPES := ["srt", "ass", "ssa", "vtt"]
const READ_CHUNK := 4096
const STOP_WAIT_MS := 300

## [[start seconds, end seconds, text]], in start order.
var cues: Array = []
var choice: Dictionary = {}
var _mutex := Mutex.new()
var _session := 0
var _thread: Thread
var _pid := -1
var _lingering: Array[Thread] = []
var _cursor := 0

## Every subtitle choice for `file`: {key, label, kind: "off" | "text" | "picture", track, path}.
static func choices(file: String, info: Dictionary) -> Array:
	var out: Array = [{"key": "off", "label": "Off", "kind": "off"}]
	var embedded: Array = info.get("subtitles", []) if info.get("subtitles") is Array else []
	for row: Variant in embedded:
		if not row is Dictionary: continue
		var stream: Dictionary = row
		var codec := str(stream.get("codec", ""))
		var kind := "picture" if codec in PICTURE_CODECS else "text"
		var words := PackedStringArray()
		var language := str(stream.get("language", ""))
		if not language.is_empty() and language != "und": words.append(_language(language))
		var title := str(stream.get("title", ""))
		if not title.is_empty() and title.to_lower() != language.to_lower(): words.append(title)
		if words.is_empty(): words.append("Track %d" % (int(stream.get("track", 0)) + 1))
		if kind == "picture": words.append("(picture)")
		out.append({"key": "embedded:%d" % int(stream.get("track", 0)), "label": " · ".join(words), "kind": kind, "track": int(stream.get("track", 0))})
	var folder := file.get_base_dir()
	var stem := file.get_file().get_basename().to_lower()
	if DirAccess.dir_exists_absolute(folder):
		for name: String in DirAccess.get_files_at(folder):
			if name.get_extension().to_lower() not in FILE_TYPES or not name.to_lower().begins_with(stem): continue
			var extra := name.get_basename().substr(stem.length()).trim_prefix(".").trim_prefix(" ")
			out.append({"key": "file:" + name, "label": "File: " + (extra if not extra.is_empty() else name), "kind": "text", "path": folder.path_join(name)})
	return out

static func _language(code: String) -> String:
	var names := {"eng": "English", "en": "English", "spa": "Spanish", "es": "Spanish", "fre": "French", "fra": "French", "fr": "French",
		"ger": "German", "deu": "German", "de": "German", "ita": "Italian", "it": "Italian", "jpn": "Japanese", "ja": "Japanese",
		"por": "Portuguese", "pt": "Portuguese", "rus": "Russian", "ru": "Russian", "chi": "Chinese", "zho": "Chinese", "zh": "Chinese",
		"kor": "Korean", "ko": "Korean", "dut": "Dutch", "nld": "Dutch", "swe": "Swedish", "nor": "Norwegian", "dan": "Danish",
		"fin": "Finnish", "pol": "Polish", "cze": "Czech", "ces": "Czech", "hun": "Hungarian", "gre": "Greek", "ell": "Greek",
		"tur": "Turkish", "ara": "Arabic", "heb": "Hebrew", "hin": "Hindi", "tha": "Thai", "vie": "Vietnamese", "ind": "Indonesian"}
	return str(names.get(code.to_lower(), code.to_upper()))

## Starts reading the text of `chosen` (a choices() row) from `at` seconds. Picture and "off"
## choices read nothing.
func start(ffmpeg: String, file: String, chosen: Dictionary, at: float) -> void:
	stop()
	choice = chosen
	if str(chosen.get("kind", "off")) != "text": return
	var arguments := PackedStringArray(["-nostdin", "-hide_banner", "-loglevel", "error"])
	if chosen.has("path"):
		arguments.append_array(["-i", str(chosen.path), "-f", "srt", "pipe:1"])
	else:
		var from := maxf(0.0, at - 10.0)
		arguments.append_array(["-readrate", "8", "-ss", "%.3f" % from, "-copyts", "-i", file, "-map", "0:s:%d" % int(chosen.get("track", 0)), "-f", "srt", "pipe:1"])
	var process := OS.execute_with_pipe(ffmpeg, arguments)
	if process.is_empty(): return
	_pid = int(process.get("pid", -1))
	_thread = Thread.new()
	_thread.start(_read.bind(_session, process))

func stop() -> void:
	_mutex.lock()
	_session += 1
	cues.clear()
	_cursor = 0
	_mutex.unlock()
	if _pid > 0 and OS.is_process_running(_pid): OS.kill(_pid)
	_pid = -1
	if _thread != null and _thread.is_started():
		var waited := 0
		while _thread.is_alive() and waited < STOP_WAIT_MS:
			OS.delay_msec(10); waited += 10
		if _thread.is_alive(): _lingering.append(_thread)
		else: _thread.wait_to_finish()
	_thread = null
	for i in range(_lingering.size() - 1, -1, -1):
		if not _lingering[i].is_alive():
			_lingering[i].wait_to_finish()
			_lingering.remove_at(i)

## The line (or lines) on screen at `seconds`, "" when none.
func text_at(seconds: float) -> String:
	_mutex.lock()
	var count := cues.size()
	if count == 0:
		_mutex.unlock(); return ""
	# Playback mostly moves forward: start from the last answer and walk.
	_cursor = clampi(_cursor, 0, count - 1)
	if float(cues[_cursor][0]) > seconds:
		_cursor = maxi(0, cues.bsearch_custom(seconds, func(cue: Array, t: float) -> bool: return float(cue[0]) < t) - 1)
	while _cursor + 1 < count and float(cues[_cursor + 1][0]) <= seconds: _cursor += 1
	var lines := PackedStringArray()
	for i in range(_cursor, maxi(-1, _cursor - 6), -1):
		var cue: Array = cues[i]
		if float(cue[0]) <= seconds and seconds < float(cue[1]): lines.insert(0, str(cue[2]))
	_mutex.unlock()
	return "\n".join(lines)

## The lines heard between two times (part 2: what the ponies follow).
func lines_between(from: float, to: float) -> Array:
	var out: Array = []
	_mutex.lock()
	for cue: Array in cues:
		if float(cue[0]) >= to: break
		if float(cue[1]) > from: out.append([float(cue[0]), str(cue[2])])
	_mutex.unlock()
	return out

func _read(session: int, process: Dictionary) -> void:
	var pipe: FileAccess = process.get("stdio")
	var pending := ""
	while pipe != null and _current(session):
		var part := pipe.get_buffer(READ_CHUNK)
		if part.is_empty(): break
		pending += part.get_string_from_utf8().replace("\r\n", "\n").replace("\r", "\n")
		var cut := pending.rfind("\n\n")
		if cut < 0: continue
		var blocks := pending.substr(0, cut)
		pending = pending.substr(cut + 2)
		_add(session, blocks)
	if not pending.strip_edges().is_empty(): _add(session, pending)

func _current(session: int) -> bool:
	_mutex.lock()
	var same := session == _session
	_mutex.unlock()
	return same

## SRT blocks ("1\n00:00:01,000 --> 00:00:02,500\nWords") into cues.
func _add(session: int, text: String) -> void:
	var found: Array = []
	for block: String in text.split("\n\n", false):
		var rows := block.strip_edges().split("\n")
		var timing := -1
		for i in rows.size():
			if " --> " in rows[i]:
				timing = i
				break
		if timing < 0: continue
		var times := rows[timing].split(" --> ")
		var start := _seconds(times[0])
		var end := _seconds(times[1].get_slice(" ", 0)) if times.size() > 1 else start + 2.0
		if start < 0.0 or end <= start: continue
		var words := clean("\n".join(rows.slice(timing + 1)))
		if not words.is_empty(): found.append([start, end, words])
	if found.is_empty(): return
	_mutex.lock()
	if session == _session: cues.append_array(found)
	_mutex.unlock()

## Spoken words only: no ASS overrides ({\i1}), no HTML tags (<i>), no stray markup.
static func clean(text: String) -> String:
	var out := RegEx.create_from_string("\\{[^}]*\\}").sub(text, "", true)
	out = RegEx.create_from_string("<[^>]*>").sub(out, "", true)
	return out.replace("\\N", "\n").replace("\\n", "\n").strip_edges()

static func _seconds(stamp: String) -> float:
	var parts := stamp.strip_edges().replace(",", ".").split(":")
	if parts.size() != 3: return -1.0
	return float(parts[0]) * 3600.0 + float(parts[1]) * 60.0 + float(parts[2])
