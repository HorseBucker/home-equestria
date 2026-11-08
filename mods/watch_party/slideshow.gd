extends Node
## The photo slideshow (screen saver): the pictures in one folder of the player's (watch_settings
## slides_folder, subfolders too), shuffled (a new order each time round, playtest 2026-11-03), each shown `seconds` and then
## crossfaded into the next (the screen shaders' previous/fade, screen_common.gd). Each picture is
## loaded and fitted to the screen's shape on a worker thread, so a big photo never stalls a frame.
## tv_set.gd owns one per set: it starts on its own after IDLE_SECONDS with nothing on (or from the
## TV menu), and any use of the set stops it.

signal picture(texture: ImageTexture, average: Color)
signal problem(text: String)
## A moving picture (GIF, WebM) is next: tv_set.gd plays it with ffmpeg, loops it until its
## `seconds` are up (always to its end at least once), then calls step(1).
signal animated(path: String)

const STILL := ["jpg", "jpeg", "png", "webp", "bmp", "tga", "svg"]
const MOVING := ["gif", "webm"]
const TYPES := ["jpg", "jpeg", "png", "webp", "bmp", "tga", "svg", "gif", "webm"]
const MAX_FILES := 5000
const MAX_DEPTH := 4

var size := Vector2i(1280, 720)
var seconds := 8.0
var running := false
var files: PackedStringArray = PackedStringArray()
## Indexes into `files` in showing order, and where in it the picture on screen is.
var _order: Array[int] = []
var _index := -1
var _wait := 0.0
var _loader: Thread
var _loading := false
## A moving picture is playing on the set; the set says when it is done.
var playing_moving := false

func _exit_tree() -> void:
	stop()

## Starts showing `folder`; false (with a problem) when it has no pictures.
func start(folder: String, every: float) -> bool:
	stop()
	seconds = clampf(every, 2.0, 600.0)
	files = list(folder)
	if files.is_empty():
		problem.emit("No pictures in " + (folder if not folder.is_empty() else "the slideshow folder (set it in the TV menu)"))
		return false
	running = true
	_shuffle(-1)
	_index = -1
	_wait = 0.0
	step(1)
	return true

## A new random order; `avoid` (the picture just shown) does not come first.
func _shuffle(avoid: int) -> void:
	_order.clear()
	for i in files.size(): _order.append(i)
	_order.shuffle()
	if _order.size() > 1 and _order[0] == avoid: _order.append(_order.pop_front())

func stop() -> void:
	running = false
	playing_moving = false
	_finish()

func _process(delta: float) -> void:
	if not running or _loading or playing_moving: return
	_wait -= delta
	if _wait <= 0.0: step(1)

## The next (1) or previous (-1) picture; each time round the order is shuffled again.
func step(direction: int) -> void:
	if files.is_empty() or not running or _loading: return
	_index += direction
	if _index >= _order.size():
		_shuffle(_order[-1] if not _order.is_empty() else -1)
		_index = 0
	elif _index < 0:
		_index = _order.size() - 1
	_finish()
	var path := files[_order[_index]]
	playing_moving = path.get_extension().to_lower() in MOVING
	if playing_moving:
		animated.emit(path)
		return
	_loading = true
	_loader = Thread.new()
	_loader.start(_load.bind(path, size))

func _load(path: String, fit: Vector2i) -> void:
	var image := Image.load_from_file(path)
	call_deferred("_loaded", path, _fitted(image, fit) if image != null and not image.is_empty() else null)

func _loaded(path: String, image: Image) -> void:
	_finish()
	if not running: return
	_wait = seconds
	if image == null:
		print("[watch_party] slideshow: could not read ", path)
		_wait = 0.1
		return
	var small := image.duplicate() as Image
	small.resize(8, 6, Image.INTERPOLATE_BILINEAR)
	var total := Color(0, 0, 0)
	for y in 6:
		for x in 8: total += small.get_pixel(x, y)
	picture.emit(ImageTexture.create_from_image(image), total / 48.0)

func _finish() -> void:
	if _loader != null and _loader.is_started(): _loader.wait_to_finish()
	_loader = null
	_loading = false

## `image` letterboxed onto black at `fit` (the whole photo shows, never cropped or stretched).
static func _fitted(image: Image, fit: Vector2i) -> Image:
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGB8)
	var scale := minf(float(fit.x) / image.get_width(), float(fit.y) / image.get_height())
	var inner := Vector2i(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)))
	image.resize(inner.x, inner.y, Image.INTERPOLATE_CUBIC)
	var canvas := Image.create(fit.x, fit.y, false, Image.FORMAT_RGB8)
	canvas.fill(Color.BLACK)
	canvas.blit_rect(image, Rect2i(Vector2i.ZERO, inner), (fit - inner) / 2)
	return canvas

## Every picture under `folder`, sorted by name.
static func list(folder: String) -> PackedStringArray:
	var found: Array[String] = []
	_scan(folder, 0, found)
	found.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return PackedStringArray(found)

static func _scan(dir: String, depth: int, found: Array[String]) -> void:
	if dir.is_empty() or depth > MAX_DEPTH or found.size() >= MAX_FILES or not DirAccess.dir_exists_absolute(dir): return
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension().to_lower() in TYPES:
			found.append(dir.path_join(file))
			if found.size() >= MAX_FILES: return
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."): _scan(dir.path_join(sub), depth + 1, found)
