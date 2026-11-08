extends Node
## Plays one media file through two ffmpeg processes (OS.execute_with_pipe): one decodes the picture
## to raw RGBA frames at a fixed size and rate, the other the sound to 32-bit float stereo. A worker
## thread reads each pipe into a short queue; the main thread feeds the sound to an
## AudioStreamGenerator on the set's speaker and shows the newest frame that is due. The sound is
## the clock (frames handed to the speaker minus what it still holds), so the picture follows the
## sound; a file without sound runs on the wall clock.
## Pausing stops the speaker and the queues fill up, which stalls ffmpeg on its full pipe; seeking
## starts both processes again at the new time.
## Cuts (Watch Party part 3): each frame's 12 x 9 colour grid is compared with the one shown before;
## a big change is a cut. The frame shown just before the latest cut is kept (picture_before_cut),
## so a pony asked about the scene that just ended is shown that scene, not the new one.

signal picture(texture: ImageTexture)
signal finished
## The picture could not be made (ffmpeg's first error line); the sound may still play.
signal problem(text: String)
const RATE := 44100
const FPS := 30.0
const VIDEO_QUEUE := 6
const AUDIO_CHUNK := 2048            # frames per read
const AUDIO_AHEAD := RATE            # at most one second of sound queued
const GENERATOR_SECONDS := 0.4
## A worker that does not end this soon after its process is killed is left to finish later.
const STOP_WAIT_MS := 300
## Largest single pipe read: asking for a whole frame at once allocates a frame-sized buffer for
## every few kilobytes the pipe actually hands over.
const READ_CHUNK := 65536
## Mean colour change across the grid (0..1) that counts as a cut; one shot moving stays far below.
const CUT_CHANGE := 0.14
## Cuts closer together than this (flashes, strobing) count once.
const CUT_SPACING := 0.6

var ffmpeg := "ffmpeg"
var width := 640
var height := 480
## Fill the screen (crop the sides of a wide film) instead of fitting it with black bars.
var fill := false
## HDR film (PQ or HLG): ffmpeg maps it down to the screen's range (tonemap below).
var tonemap := false
## An embedded picture subtitle stream (Blu-ray PGS, DVD) drawn into the picture by ffmpeg, or -1.
var burn_subtitle := -1
## The average colour of the frame on screen (the set's light follows it).
var average := Color.BLACK
var speaker: AudioStreamPlayer3D
var state := "idle"                  # idle, playing, paused, ended
var error := ""
var path := ""
## Where the sound comes from when not from `path` (a stream whose sound is a stream of its own:
## CyTube's custom media, web_view.gd); its first sound track.
var audio_source := ""
var duration := 0.0
## Video seconds of the latest cut (-1 before the first one since playing started).
var last_cut := -1.0

var _mutex := Mutex.new()
var _video_queue: Array = []         # [presentation time, Image, average colour, colour grid]
var _audio_queue: Array = []         # PackedVector2Array chunks
var _audio_queued := 0
var _audio_rest := PackedVector2Array()
var _video_done := false
var _audio_done := false
## Each play() is a new session; a worker from an older one stops and leaves the queues alone.
var _session := 0
var _video_process: Dictionary = {}
var _audio_process: Dictionary = {}
var _video_thread: Thread
var _audio_thread: Thread
var _lingering: Array[Thread] = []
var _start := 0.0
var _sound := false
var _wants_sound := false
var _track := 0
var _playback: AudioStreamGeneratorPlayback
var _capacity := 0
var _pushed := 0
var _wall := 0.0
var _texture: ImageTexture
var _audio_error := ""
var _video_error := ""
var _frames_shown := 0
var _problem_said := false
var _frame: Image
var _frame_grid := PackedFloat32Array()
var _before_cut: Image

## Starts `file` at `at` seconds. `length` (0 when unknown) and `sound` come from the probe.
func play(file: String, at: float, length: float, sound: bool, audio_track := 0) -> bool:
	stop()
	path = file; duration = length; error = ""; _wants_sound = sound; _track = audio_track
	_start = clampf(at, 0.0, maxf(0.0, length - 1.0)) if length > 0.0 else maxf(0.0, at)
	_video_done = false; _audio_done = not sound; _sound = sound
	_video_queue.clear(); _audio_queue.clear(); _audio_queued = 0; _audio_rest = PackedVector2Array()
	_pushed = 0; _wall = 0.0; _audio_error = ""; _video_error = ""; _frames_shown = 0; _problem_said = false
	last_cut = -1.0; _frame = null; _frame_grid = PackedFloat32Array(); _before_cut = null
	# A fresh texture each start, so the set is always handed the picture (after a stop it shows
	# its dark glass and would never hear of a reused texture).
	_texture = null
	_video_process = OS.execute_with_pipe(ffmpeg, _video_arguments(file, _start))
	if _video_process.is_empty():
		error = "ffmpeg could not be started."
		state = "idle"; return false
	var session := _session
	_video_thread = Thread.new()
	_video_thread.start(_read_video.bind(session, _video_process))
	if sound:
		_audio_process = OS.execute_with_pipe(ffmpeg, _audio_arguments(audio_source if not audio_source.is_empty() else file, _start, audio_track if audio_source.is_empty() else 0))
		if _audio_process.is_empty():
			_sound = false; _audio_done = true
		else:
			_audio_thread = Thread.new()
			_audio_thread.start(_read_audio.bind(session, _audio_process))
	if _sound and is_instance_valid(speaker):
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = RATE
		generator.buffer_length = GENERATOR_SECONDS
		speaker.stream = generator
		speaker.stream_paused = false
		speaker.play()
		_playback = speaker.get_stream_playback() as AudioStreamGeneratorPlayback
		_capacity = _playback.get_frames_available() if _playback != null else 0
		if _playback == null: _sound = false
	state = "playing"
	return true

func pause() -> void:
	if state != "playing": return
	state = "paused"
	if is_instance_valid(speaker): speaker.stream_paused = true

func resume() -> void:
	if state != "paused": return
	state = "playing"
	if is_instance_valid(speaker): speaker.stream_paused = false

## Seconds into the file that are being heard and seen now.
func position() -> float:
	if _sound and _playback != null:
		var held := maxi(0, _capacity - _playback.get_frames_available())
		return _start + maxf(0.0, float(_pushed - held) / RATE - AudioServer.get_output_latency())
	return _start + _wall

func seek(to: float) -> void:
	if path.is_empty() or state == "idle": return
	var was_paused := state == "paused"
	play(path, to, duration, _wants_sound, _track)
	if was_paused: pause()

## Another sound track, picture shape or burned-in subtitle: starts again from here.
func restart(audio_track: int) -> void:
	if path.is_empty() or state in ["idle", "ended"]: return
	_track = audio_track
	seek(position())

func audio_track() -> int:
	return _track

## Ends playback and both processes. Safe to call at any time.
func stop() -> void:
	_mutex.lock()
	_session += 1
	_mutex.unlock()
	for process: Dictionary in [_video_process, _audio_process]:
		var pid: int = int(process.get("pid", -1))
		if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
	for thread: Thread in [_video_thread, _audio_thread]:
		if thread == null or not thread.is_started(): continue
		var waited := 0
		while thread.is_alive() and waited < STOP_WAIT_MS:
			OS.delay_msec(10); waited += 10
		if thread.is_alive(): _lingering.append(thread)
		else: thread.wait_to_finish()
	_video_thread = null; _audio_thread = null
	_video_process = {}; _audio_process = {}
	if is_instance_valid(speaker): speaker.stop()
	_playback = null
	_mutex.lock()
	_video_queue.clear(); _audio_queue.clear(); _audio_queued = 0
	_mutex.unlock()
	_audio_rest = PackedVector2Array()
	if state != "ended": state = "idle"

func _process(delta: float) -> void:
	_reap()
	if state != "playing": return
	_feed_sound()
	if not _sound: _wall += delta
	_show_due()
	_report_problem()
	_check_end()

func _exit_tree() -> void:
	stop()
	for thread: Thread in _lingering:
		if thread.is_started(): thread.wait_to_finish()
	_lingering.clear()

## Hands queued sound to the speaker as far as it has room.
func _feed_sound() -> void:
	if not _sound or _playback == null: return
	var room := _playback.get_frames_available()
	# The generator's real size, in case it was not running yet when play() measured it.
	_capacity = maxi(_capacity, room)
	while room > 0:
		if _audio_rest.is_empty():
			_mutex.lock()
			if _audio_queue.is_empty():
				_mutex.unlock(); break
			_audio_rest = _audio_queue.pop_front()
			_audio_queued -= _audio_rest.size()
			_mutex.unlock()
		var count := mini(room, _audio_rest.size())
		if count == _audio_rest.size():
			_playback.push_buffer(_audio_rest)
			_audio_rest = PackedVector2Array()
		else:
			_playback.push_buffer(_audio_rest.slice(0, count))
			_audio_rest = _audio_rest.slice(count)
		_pushed += count
		room -= count

## Shows the newest frame whose time has come; older due frames are dropped.
func _show_due() -> void:
	var now := position()
	var frame: Image = null
	var grid := PackedFloat32Array()
	var at := 0.0
	_mutex.lock()
	while not _video_queue.is_empty() and float(_video_queue[0][0]) <= now + 0.5 / FPS:
		var due: Array = _video_queue.pop_front()
		at = due[0]
		frame = due[1]
		average = due[2]
		grid = due[3]
	_mutex.unlock()
	if frame == null: return
	if not _frame_grid.is_empty() and change(_frame_grid, grid) >= CUT_CHANGE and at - last_cut >= CUT_SPACING:
		last_cut = at
		_before_cut = _frame
	_frame = frame
	_frame_grid = grid
	_frames_shown += 1
	if _frames_shown == 1: print("[watch_party] picture: first frame at %.1f s into %s" % [now, path.get_file()])
	if _texture == null or _texture.get_width() != frame.get_width() or _texture.get_height() != frame.get_height():
		_texture = ImageTexture.create_from_image(frame)
		picture.emit(_texture)
	else:
		_texture.update(frame)

## The picture process ended without a single frame while the sound goes on: say why, once.
func _report_problem() -> void:
	if _problem_said or _frames_shown > 0: return
	_mutex.lock()
	var failed := _video_done and _video_queue.is_empty()
	var reason := _video_error
	_mutex.unlock()
	if not failed: return
	_problem_said = true
	var text := reason if not reason.is_empty() else "ffmpeg gave no picture for this file"
	print("[watch_party] picture failed: ", text)
	problem.emit(text)

func _check_end() -> void:
	_mutex.lock()
	var video_left := not _video_done or not _video_queue.is_empty()
	var sound_left := not _audio_done or not _audio_queue.is_empty()
	_mutex.unlock()
	if _sound and _playback != null and _capacity - _playback.get_frames_available() > 0: sound_left = true
	if not _audio_rest.is_empty(): sound_left = true
	if video_left or (_sound and sound_left): return
	var reason := _video_error if not _video_error.is_empty() else _audio_error
	if not reason.is_empty() and position() < _start + 1.0: error = reason
	state = "ended"
	stop()
	finished.emit()

func _reap() -> void:
	for i in range(_lingering.size() - 1, -1, -1):
		if not _lingering[i].is_alive():
			_lingering[i].wait_to_finish()
			_lingering.remove_at(i)

func _current(session: int) -> bool:
	_mutex.lock()
	var same := session == _session
	_mutex.unlock()
	return same

func _read_video(session: int, process: Dictionary) -> void:
	var pipe: FileAccess = process.get("stdio")
	var size := width * height * 4
	var start := _start
	var index := 0
	while pipe != null and _current(session):
		_mutex.lock()
		var full := _video_queue.size() >= VIDEO_QUEUE
		_mutex.unlock()
		if full:
			OS.delay_msec(4); continue
		var bytes := _read_exact(pipe, size)
		if bytes.size() < size: break
		if index == 0: print("[watch_party] picture: ffmpeg sent its first frame")
		var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)
		var grid := _grid(bytes, width, height)
		var colour := _average(grid)
		_mutex.lock()
		if session == _session: _video_queue.append([start + index / FPS, image, colour, grid])
		_mutex.unlock()
		index += 1
	var reason := _errors(process) if index == 0 and _current(session) else ""
	if _current(session): print("[watch_party] picture: ffmpeg stopped after %d frames%s" % [index, (" (" + reason + ")") if not reason.is_empty() else ""])
	_mutex.lock()
	if session == _session:
		_video_done = true
		_video_error = reason
	_mutex.unlock()

func _read_audio(session: int, process: Dictionary) -> void:
	var pipe: FileAccess = process.get("stdio")
	var size := AUDIO_CHUNK * 8
	var read := 0
	while pipe != null and _current(session):
		_mutex.lock()
		var ahead := _audio_queued
		_mutex.unlock()
		if ahead >= AUDIO_AHEAD:
			OS.delay_msec(5); continue
		var bytes := _read_exact(pipe, size)
		if bytes.size() < 8: break
		var samples := bytes.slice(0, bytes.size() - bytes.size() % 8).to_float32_array()
		var frames := samples.size() / 2
		var chunk := PackedVector2Array()
		chunk.resize(frames)
		for i in frames:
			chunk[i] = Vector2(samples[i * 2], samples[i * 2 + 1])
		_mutex.lock()
		if session == _session:
			_audio_queue.append(chunk)
			_audio_queued += frames
		_mutex.unlock()
		read += frames
		if bytes.size() < size: break
	var reason := _errors(process) if read == 0 and _current(session) else ""
	_mutex.lock()
	if session == _session:
		_audio_done = true
		_audio_error = reason
	_mutex.unlock()

## The picture on screen now (null before the first frame).
func picture_now() -> Image:
	return _frame

## The last frame of the shot before the latest cut (null when there has been none).
func picture_before_cut() -> Image:
	return _before_cut

## A 12 x 9 grid of RGB samples (0..1): about a hundred reads a frame, enough for a light and cuts.
static func _grid(bytes: PackedByteArray, w: int, h: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(108 * 3)
	var i := 0
	for gy in 9:
		var y := int((gy + 0.5) * h / 9.0)
		for gx in 12:
			var at := (y * w + int((gx + 0.5) * w / 12.0)) * 4
			for c in 3:
				out[i] = bytes[at + c] / 255.0
				i += 1
	return out

## The mean of the grid.
static func _average(grid: PackedFloat32Array) -> Color:
	var sum := Vector3.ZERO
	for i in range(0, grid.size(), 3): sum += Vector3(grid[i], grid[i + 1], grid[i + 2])
	sum /= maxf(1.0, grid.size() / 3.0)
	return Color(sum.x, sum.y, sum.z)

## Mean absolute colour change between two grids (0 same, 1 black to white).
static func change(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size() or a.is_empty(): return 0.0
	var sum := 0.0
	for i in a.size(): sum += absf(a[i] - b[i])
	return sum / a.size()

## A pipe read returns what has arrived so far (Windows), so read until `size` or the end.
static func _read_exact(pipe: FileAccess, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	while out.size() < size:
		var part := pipe.get_buffer(mini(READ_CHUNK, size - out.size()))
		if part.is_empty(): break
		out.append_array(part)
	return out

## What ffmpeg printed on stderr, for a process that ended without any output.
static func _errors(process: Dictionary) -> String:
	var pipe: FileAccess = process.get("stderr")
	if pipe == null: return ""
	var text := _read_exact(pipe, 4096).get_string_from_utf8().strip_edges()
	return text.get_slice("\n", 0).left(200)

func _video_arguments(file: String, at: float) -> PackedStringArray:
	var shape := "scale=%d:%d:force_original_aspect_ratio=decrease:flags=bilinear,pad=%d:%d:(ow-iw)/2:(oh-ih)/2" % [width, height, width, height]
	if fill: shape = "scale=%d:%d:force_original_aspect_ratio=increase:flags=bilinear,crop=%d:%d" % [width, height, width, height]
	var chain := "fps=%d,%s,format=rgba" % [int(FPS), shape]
	if tonemap:
		# HDR to SDR after the scale-down (cheap at screen size): to linear light, BT.709
		# primaries, then Hable's curve, which keeps highlights from clipping to flat white;
		# desat=0 keeps bright colours vivid. Needs ffmpeg's zscale (zimg), which full builds have.
		chain = "fps=%d,%s,zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=pc,format=rgba" % [int(FPS), shape]
	# -hwaccel auto decodes on the graphics card when it can (4K HEVC is too slow on the CPU
	# alone) and falls back to the CPU; 0:V:0 is the first real video stream, never cover art.
	var arguments := PackedStringArray(["-nostdin", "-hide_banner", "-loglevel", "error", "-hwaccel", "auto", "-ss", "%.3f" % at, "-i", file])
	if burn_subtitle >= 0:
		# The subtitle pictures are laid over the film at its own size, then the whole is scaled.
		arguments.append_array(["-filter_complex", "[0:V:0][0:s:%d]overlay=(W-w)/2:H-h,%s[picture]" % [burn_subtitle, chain], "-map", "[picture]"])
	else:
		arguments.append_array(["-map", "0:V:0", "-vf", chain])
	arguments.append_array(["-an", "-sn", "-dn", "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"])
	return arguments

func _audio_arguments(file: String, at: float, track: int) -> PackedStringArray:
	return PackedStringArray(["-nostdin", "-hide_banner", "-loglevel", "error", "-ss", "%.3f" % at, "-i", file,
		"-map", "0:a:%d" % maxi(0, track), "-vn", "-sn", "-dn", "-ac", "2", "-ar", str(RATE), "-f", "f32le", "pipe:1"])
