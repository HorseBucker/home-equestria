extends "res://mods/watch_party/subtitles.gd"
## Subtitles the ponies could not read otherwise, read with OCR (ocr_engine.gd). The same timed lines
## as subtitles.gd (cues, text_at, lines_between), so ponies follow them like any text track.
## Two ways (tv_set.gd _start_ocr chooses, Settings → Watch Party switches each off):
## - "track": a picture subtitle track (Blu-ray PGS, DVD). ffmpeg draws only that track, on black,
##   RATE times a second, and sends the frames as grey bytes (black words on white). A frame the same
##   as the one before is skipped (a subtitle shown is the same bitmap until it changes); any other
##   ends the line up, and is cropped to its words and read (an empty one is not read). Each line keeps the time it
##   came up and went away. Read from where playback is, staying at most AHEAD seconds in front of
##   it; kept in the mod's data folder (ocr/<key>.json, with which stretches are read), so a film
##   watched again is not read again.
## - "live": no subtitle track to read, so the picture itself every LIVE_EVERY seconds (tv_set.gd
##   offers the decoded frame, never the camera's view): the bottom 35% of the film, light pixels
##   (white, light grey, yellow) kept as black on white; with almost none it skips the OCR.
## Either way: dashes made hyphens, and a line at least SAME alike to the one before
## (String.similarity) taken as the same line still up. The live way also drops lines of 3
## characters or fewer (LIVE_MIN_CHARS).

const MEDIA := preload("res://mods/watch_party/media_player.gd")
const RATE := 4
const AHEAD := 300.0
const SAVE_SECONDS := 60.0
const LIVE_EVERY := 2.0
const SAME := 0.8
## The live way drops anything shorter: a few stray light pixels (a logo, a lamp) tend to come back
## as "il" or "|.". A track's bitmaps are clean, so there "No." and "Oh!" are real lines and stay.
const LIVE_MIN_CHARS := 4
const CACHE_VERSION := 2
const CACHE_KEEP := 150
## Finding the words in a frame: a copy this many times smaller, and how dark counts as ink.
const THUMB := 4
const INK := 200
## The share of the strip's pixels that must be light for the live way to read it.
const LIVE_INK := 0.002
## Light enough to be subtitle (0..255 luminance) in the live way.
const LIVE_LIGHT := 185

## "", "track" or "live".
var mode := ""
## The share of the film read so far (track).
var progress := 0.0
## Why the track could not be read ("" when fine).
var problem := ""
var _ocr: RefCounted
var _cache := ""
var _png := ""
var _covered: Array = []
var _duration := 0.0
var _playhead := 0.0
## The cue still on the screen (its end not known yet), or -1.
var _open := -1
var _save_mutex := Mutex.new()
## The video file read (kept in its cache too: a cache for another file is not used).
var _file := ""

## Reads picture subtitle track `row` (subtitles.gd choices()) of `file` from `at` seconds.
func start_track(ffmpeg: String, file: String, row: Dictionary, info: Dictionary, at: float, ocr: RefCounted, data_folder: String) -> void:
	stop()
	mode = "track"; choice = row; _ocr = ocr; problem = ""
	_duration = float(info.get("duration", 0.0))
	_playhead = at
	_file = file
	var folder := ProjectSettings.globalize_path(data_folder).path_join("ocr")
	DirAccess.make_dir_recursive_absolute(folder)
	_prune(folder)
	var track := int(row.get("track", 0))
	_cache = folder.path_join(("%s|%d|%d" % [file, FileAccess.get_modified_time(file), track]).md5_text() + ".json")
	_png = folder.path_join("frame_%d.png" % get_instance_id())
	_load(file, track)
	_thread = Thread.new()
	_thread.start(_track_worker.bind(_session, ffmpeg, file, track, _canvas(info, track), at))

## Reads the picture itself (offer()).
func start_live(ocr: RefCounted, data_folder: String) -> void:
	stop()
	mode = "live"; choice = {"key": "live", "label": "words in the picture", "kind": "live"}; _ocr = ocr; problem = ""
	var folder := ProjectSettings.globalize_path(data_folder).path_join("ocr")
	DirAccess.make_dir_recursive_absolute(folder)
	_png = folder.path_join("frame_%d.png" % get_instance_id())

func stop() -> void:
	if mode == "track": _save(_session)
	super()
	mode = ""
	progress = 0.0
	_mutex.lock()
	_covered = []
	_open = -1
	_mutex.unlock()

## Where playback is now (tv_set.gd, every frame): the track is read at most AHEAD seconds ahead.
func set_playhead(seconds: float) -> void:
	_mutex.lock()
	_playhead = seconds
	_mutex.unlock()

func found_any() -> bool:
	_mutex.lock()
	var any := not cues.is_empty()
	_mutex.unlock()
	return any

## The decoded frame on the screen now (live way), at `seconds` into the film; `film` is where the
## film is in it (without black bars). Skipped while the last one is still being read.
func offer(frame: Image, seconds: float, film: Rect2i) -> void:
	if mode != "live" or frame == null: return
	if _thread != null and _thread.is_started():
		if _thread.is_alive(): return
		_thread.wait_to_finish()
	_thread = Thread.new()
	_thread.start(_live_task.bind(_session, frame, seconds, film))

# --- the track ------------------------------------------------------------------------------------

## The size ffmpeg draws the subtitles at: the track's own canvas, else the film's, at most 1080 lines.
static func _canvas(info: Dictionary, track: int) -> Vector2i:
	var size := Vector2i(int(info.get("width", 0)), int(info.get("height", 0)))
	for row: Variant in info.get("subtitles", []):
		if row is Dictionary and int((row as Dictionary).get("track", -1)) == track and int((row as Dictionary).get("width", 0)) > 0:
			size = Vector2i(int(row.width), int(row.height))
	if size.x <= 0 or size.y <= 0: size = Vector2i(1920, 1080)
	return size

func _track_worker(session: int, ffmpeg: String, file: String, track: int, canvas: Vector2i, at: float) -> void:
	var from := maxf(0.0, at - 5.0)
	while _current(session):
		var gap := _gap(from)
		if gap.is_empty(): break
		var read := _read_span(session, ffmpeg, file, track, canvas, float(gap[0]), float(gap[1]))
		if read <= 0: break
		from = float(gap[1])
	_save(session)

## One run of ffmpeg over [start, end) (end INF: to the end of the file). Returns the frames read.
func _read_span(session: int, ffmpeg: String, file: String, track: int, canvas: Vector2i, start: float, end: float) -> int:
	var out := canvas
	var shrink := ""
	if canvas.y > 1080:
		out = Vector2i(canvas.x / 4 * 2, canvas.y / 4 * 2)
		shrink = ",scale=%d:%d" % [out.x, out.y]
	var arguments := PackedStringArray(["-nostdin", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "color=c=black:s=%dx%d:r=%d" % [canvas.x, canvas.y, RATE],
		"-ss", "%.3f" % start, "-i", file,
		"-filter_complex", "[0:v][1:s:%d]overlay=eof_action=endall%s,format=gray,negate[words]" % [track, shrink],
		"-map", "[words]"])
	if end < INF: arguments.append_array(["-t", "%.3f" % (end - start)])
	arguments.append_array(["-an", "-dn", "-f", "rawvideo", "-pix_fmt", "gray", "pipe:1"])
	var process := OS.execute_with_pipe(ffmpeg, arguments)
	if process.is_empty():
		problem = "ffmpeg could not be started"
		return 0
	_pid = int(process.get("pid", -1))
	if not _current(session):
		OS.kill(_pid)
		return 0
	var pipe: FileAccess = process.get("stdio")
	var size := out.x * out.y
	var last := PackedByteArray()
	var index := 0
	var marked := start
	var saved := Time.get_ticks_msec()
	while _current(session):
		var t := start + float(index) / RATE
		# At most AHEAD seconds in front of what is being watched.
		while _current(session) and t - _ahead_of() > AHEAD: OS.delay_msec(250)
		if not _current(session): break
		var bytes := MEDIA._read_exact(pipe, size)
		if bytes.size() < size: break
		index += 1
		if bytes == last:
			if t - marked >= 5.0:
				_cover(session, start, t); marked = t
			continue
		last = bytes
		_close_open(session, t)
		var text := tidy(_read_words(Image.create_from_data(out.x, out.y, false, Image.FORMAT_L8, bytes), canvas.y < 700))
		if not text.is_empty(): _add(session, t, text)
		if Time.get_ticks_msec() - saved > SAVE_SECONDS * 1000.0:
			saved = Time.get_ticks_msec()
			_cover(session, start, t)
			_save(session)
	var stopped := start + float(index) / RATE
	if not _current(session): return index
	_close_open(session, stopped)
	if index == 0:
		problem = MEDIA._errors(process)
		print("[watch_party] OCR: ffmpeg drew no subtitles%s" % ((" (" + problem + ")") if not problem.is_empty() else ""))
		return 0
	# ffmpeg ended by itself: read to the end of the span (or of the file, its subtitles all done).
	_cover(session, start, end if end < INF else maxf(stopped, _duration))
	print("[watch_party] OCR: read %.0f to %.0f s, %d lines so far" % [start, stopped, cues.size()])
	return index

func _ahead_of() -> float:
	_mutex.lock()
	var at := _playhead
	_mutex.unlock()
	return at

## The words in a grey frame (black on white; ffmpeg's white may be 235, its black 16): found on a
## quarter-size copy, cropped to them with a margin, doubled when small, then read. "" (no OCR) when
## the frame is empty: the line up before has gone.
func _read_words(image: Image, small: bool) -> String:
	var w := image.get_width(); var h := image.get_height()
	var thumb := image.duplicate() as Image
	thumb.resize(maxi(1, w / THUMB), maxi(1, h / THUMB), Image.INTERPOLATE_BILINEAR)
	var tw := thumb.get_width(); var th := thumb.get_height()
	var data := thumb.get_data()
	var low := Vector2i(tw, th); var high := Vector2i(-1, -1)
	for y in th:
		var row := y * tw
		for x in tw:
			if data[row + x] < INK:
				low = Vector2i(mini(low.x, x), mini(low.y, y)); high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	if high.x < 0: return ""
	var from := Vector2i(maxi(0, (low.x - 2) * THUMB), maxi(0, (low.y - 2) * THUMB))
	var to := Vector2i(mini(w, (high.x + 3) * THUMB), mini(h, (high.y + 3) * THUMB))
	var words := image.get_region(Rect2i(from, to - from))
	if small: words.resize(words.get_width() * 2, words.get_height() * 2, Image.INTERPOLATE_CUBIC)
	return _ocr_image(words)

## Puts `words` (black on white) on a white margin and reads it.
func _ocr_image(words: Image) -> String:
	if _ocr == null: return ""
	var framed := Image.create_empty(words.get_width() + 32, words.get_height() + 32, false, Image.FORMAT_L8)
	framed.fill(Color.WHITE)
	framed.blit_rect(words, Rect2i(Vector2i.ZERO, words.get_size()), Vector2i(16, 16))
	framed.convert(Image.FORMAT_RGB8)
	if framed.save_png(_png) != OK: return ""
	var text := str(_ocr.call("read", _png))
	DirAccess.remove_absolute(_png)
	return text

## A line comes up at `t`: the same as the one just before (gone less than a second ago), it is that
## line still up; otherwise a new one, its end not known yet.
func _add(session: int, t: float, text: String) -> void:
	_mutex.lock()
	if session != _session:
		_mutex.unlock(); return
	var at := cues.bsearch_custom(t, func(cue: Array, time: float) -> bool: return float(cue[0]) < time)
	if at > 0:
		var before: Array = cues[at - 1]
		if t - float(before[1]) <= 1.0 and str(before[2]).similarity(text) >= SAME:
			before[1] = INF
			if text.length() > str(before[2]).length(): before[2] = text
			_open = at - 1
			_mutex.unlock(); return
	cues.insert(at, [t, INF, text])
	_open = at
	_mutex.unlock()

func _close_open(session: int, t: float) -> void:
	_mutex.lock()
	if session == _session and _open >= 0 and _open < cues.size():
		cues[_open][1] = maxf(t, float(cues[_open][0]) + 0.25)
	if session == _session: _open = -1
	_mutex.unlock()

## [start, end] of the first stretch not read yet at or after `from`, or [] when all is read.
func _gap(from: float) -> Array:
	_mutex.lock()
	var at := from
	for span: Array in _covered:
		if float(span[0]) <= at + 0.5 and float(span[1]) > at: at = float(span[1])
	var end := INF
	for span: Array in _covered:
		if float(span[0]) > at:
			end = float(span[0]); break
	_mutex.unlock()
	if _duration > 0.0 and at >= _duration - 1.0: return []
	return [at, end]

func _cover(session: int, from: float, to: float) -> void:
	if to <= from: return
	_mutex.lock()
	if session != _session:
		_mutex.unlock(); return
	_covered.append([from, to])
	_covered.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var merged: Array = []
	for span: Array in _covered:
		if not merged.is_empty() and float(span[0]) <= float(merged[-1][1]) + 0.5: merged[-1][1] = maxf(float(merged[-1][1]), float(span[1]))
		else: merged.append([float(span[0]), float(span[1])])
	_covered = merged
	var done := 0.0
	for span: Array in merged: done += float(span[1]) - float(span[0])
	progress = clampf(done / _duration, 0.0, 1.0) if _duration > 0.0 else 0.0
	_mutex.unlock()

func _load(file: String, track: int) -> void:
	if not FileAccess.file_exists(_cache): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_cache))
	if not parsed is Dictionary or int((parsed as Dictionary).get("version", 0)) != CACHE_VERSION: return
	var doc: Dictionary = parsed
	if str(doc.get("file", "")) != file or int(doc.get("track", -1)) != track: return
	var found: Array = []
	for row: Variant in doc.get("cues", []):
		if row is Array and (row as Array).size() == 3: found.append([float(row[0]), float(row[1]), str(row[2])])
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var spans: Array = []
	for row: Variant in doc.get("covered", []):
		if row is Array and (row as Array).size() == 2: spans.append([float(row[0]), float(row[1])])
	_mutex.lock()
	cues = found
	_covered = spans
	_mutex.unlock()
	var done := 0.0
	for span: Array in spans: done += float(span[1]) - float(span[0])
	progress = clampf(done / _duration, 0.0, 1.0) if _duration > 0.0 else 0.0
	print("[watch_party] OCR: %d lines already read for %s (%.0f%%)" % [found.size(), file.get_file(), progress * 100.0])

func _save(session: int) -> void:
	_save_mutex.lock()
	_mutex.lock()
	if session != _session or _cache.is_empty():
		_mutex.unlock(); _save_mutex.unlock(); return
	var rows: Array = []
	for cue: Array in cues:
		if float(cue[1]) < INF: rows.append([snappedf(float(cue[0]), 0.01), snappedf(float(cue[1]), 0.01), str(cue[2])])
	var spans := _covered.duplicate(true)
	var path := _cache
	var source := str(choice.get("label", ""))
	_mutex.unlock()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version": CACHE_VERSION, "file": _file, "track": int(choice.get("track", -1)), "label": source, "covered": spans, "cues": rows}))
		file.close()
	_save_mutex.unlock()

## Keeps the cache folder to CACHE_KEEP films (the oldest go first).
static func _prune(folder: String) -> void:
	var files: Array = []
	for name: String in DirAccess.get_files_at(folder):
		if name.get_extension() == "json": files.append([FileAccess.get_modified_time(folder.path_join(name)), name])
		elif name.begins_with("frame_") and name.get_extension() == "png": DirAccess.remove_absolute(folder.path_join(name))
	if files.size() <= CACHE_KEEP: return
	files.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	for i in files.size() - CACHE_KEEP: DirAccess.remove_absolute(folder.path_join(str(files[i][1])))

# --- the picture itself ---------------------------------------------------------------------------

func _live_task(session: int, frame: Image, seconds: float, film: Rect2i) -> void:
	var area := film.intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	if area.size.x < 16 or area.size.y < 16: area = Rect2i(Vector2i.ZERO, frame.get_size())
	var top := area.position.y + int(area.size.y * 0.65)
	var strip := frame.get_region(Rect2i(area.position.x, top, area.size.x, area.end.y - top))
	strip.convert(Image.FORMAT_L8)
	var light := strip.get_data()
	var count := light.size()
	# A quick look first (every 4th pixel of every 2nd row): no light text, no OCR.
	var w := strip.get_width()
	var seen := 0
	var looked := 0
	for y in range(0, strip.get_height(), 2):
		for x in range(0, w, 4):
			looked += 1
			if light[y * w + x] >= LIVE_LIGHT: seen += 1
	var text := ""
	if looked > 0 and float(seen) / looked >= LIVE_INK:
		var ink := PackedByteArray(); ink.resize(count)
		for i in count: ink[i] = 0 if light[i] >= LIVE_LIGHT else 255
		var mask := Image.create_from_data(w, strip.get_height(), false, Image.FORMAT_L8, ink)
		var grow := 3 if w <= 800 else 2
		mask.resize(w * grow, strip.get_height() * grow, Image.INTERPOLATE_CUBIC)
		text = tidy(_ocr_image(mask), LIVE_MIN_CHARS)
	_live_seen(session, seconds, text)

## What the live way read at `seconds`: nothing ends the line up; the same as it extends it.
func _live_seen(session: int, seconds: float, text: String) -> void:
	_mutex.lock()
	if session != _session:
		_mutex.unlock(); return
	if text.is_empty():
		if _open >= 0 and _open < cues.size(): cues[_open][1] = seconds
		_open = -1
	elif _open >= 0 and _open < cues.size() and str(cues[_open][2]).similarity(text) >= SAME:
		cues[_open][1] = seconds + LIVE_EVERY
		if text.length() > str(cues[_open][2]).length(): cues[_open][2] = text
	else:
		if _open >= 0 and _open < cues.size(): cues[_open][1] = seconds
		cues.append([seconds, seconds + LIVE_EVERY, text])
		_open = cues.size() - 1
	_mutex.unlock()

# --- cleaning what was read -----------------------------------------------------------------------

## OCR text as subtitle words: dashes back to hyphens, spaces tidied, Tesseract's "|" for "I", and
## "" for anything shorter than `shortest` characters (spaces aside).
static func tidy(text: String, shortest := 1) -> String:
	var rows := PackedStringArray()
	for row: String in text.replace("\r", "").replace("—", "-").replace("–", "-").split("\n"):
		var line := row.strip_edges()
		while "  " in line: line = line.replace("  ", " ")
		if line == "|" or line.is_empty(): continue
		line = line.replace(" | ", " I ")
		if line.begins_with("| "): line = "I " + line.substr(2)
		rows.append(line)
	var out := "\n".join(rows)
	return out if out.replace("\n", "").replace(" ", "").length() >= shortest else ""
