extends RefCounted
## Native 3D flight routes (phase 5 of docs/NAVIGATION_OVERHAUL_COMPLETE_2026_10_02.txt,
## docs/NAVIGATION_PHASE_5_2026_10_02.md). One PonyAirNavigation per game holds the baked air
## volume (world/navigation/air_data/, built by tools/navigation/air_extract_geometry.gd and the
## nav_air baker) and a follower per flying pony. pony_flight.gd asks it for the cruise between
## takeoff and the glide-in; outside the baked volume, for bodies larger than the baked envelope,
## with `-- --native-navigation off` or without the native class, flights use their old corridors.
const BACKEND := preload("res://world/navigation/native_navigation_backend.gd")
const CLASS_NAME := "PonyAirNavigation"
const DATA := "res://world/navigation/air_data/ponyville_everfree.pegasus_mare.airnav"
## The data is baked for a full-size pegasus mare's envelope; bigger bodies need their own bake.
const MAX_BODY_SCALE := 1.15
## nav_air::Cell
const FREE := 1
const SOLID := 2
## nav_air::AirCommandMode
const ARRIVED := 3
const FAILED := 4

static var _air: RefCounted = null
static var _tried := false
static var _next_id := 0
## Loaded in the background as the world starts (0.1.0 perf pass): reading and unpacking the 8.9 MB
## volume took about 0.75 s on the main thread, a freeze the first time a pegasus flew a long route.
## The first flight waits only for what is left of that load. Rollback: WARM_IN_BACKGROUND = false.
const WARM_IN_BACKGROUND := true
static var _warm_task := -1
static var _warmed: RefCounted = null
static var _warm_info: Dictionary = {}


## Starts the background load (world/game.gd at world start). Same checks and data as instance().
static func warm() -> void:
	if not WARM_IN_BACKGROUND or _tried or _warm_task >= 0: return
	if BACKEND.mode() == "off" or not ClassDB.class_exists(CLASS_NAME) or not FileAccess.file_exists(DATA): return
	_warm_task = WorkerThreadPool.add_task(_warm_load, false, "Air volume")


## Leaving the world: joins a background load still running (kept for the next world).
static func join() -> void:
	if _warm_task >= 0 and not _tried: instance()


static func _warm_load() -> void:
	var air: RefCounted = ClassDB.instantiate(CLASS_NAME)
	_warm_info = air.load_bytes(FileAccess.get_file_as_bytes(DATA))
	_warmed = air


## The loaded air volume, or null (reported once, loudly, when native navigation is on).
static func instance() -> RefCounted:
	if _tried:
		return _air
	_tried = true
	if BACKEND.mode() == "off":
		return null
	if _warm_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_warm_task)
		_warm_task = -1
		if not bool(_warm_info.get("ok", false)):
			_report("The baked air volume did not load (%s); flights use their old corridors" % str(_warm_info.get("error", "?")))
			return null
		_air = _warmed
		return _air
	if not ClassDB.class_exists(CLASS_NAME):
		_report("%s is not in this build of native/pony_solver for %s; flights use their old corridors" % [CLASS_NAME, OS.get_name()])
		return null
	if not FileAccess.file_exists(DATA):
		_report("No baked air volume at %s; flights use their old corridors" % DATA)
		return null
	var air: RefCounted = ClassDB.instantiate(CLASS_NAME)
	var info: Dictionary = air.load_bytes(FileAccess.get_file_as_bytes(DATA))
	if not bool(info.get("ok", false)):
		_report("The baked air volume did not load (%s); flights use their old corridors" % str(info.get("error", "?")))
		return null
	_air = air
	return _air


## Her size against the baked full-size mare: body scale times model scale (the princesses are
## full-size bodies on a bigger model).
static func size_of(pony: Node) -> float:
	var body: float = float(pony.get("body_scale")) if pony.get("body_scale") != null else 1.0
	var model: float = float(pony.get("model_scale")) if pony.get("model_scale") != null else 1.0
	return body * model


static func new_id() -> int:
	_next_id += 1
	return _next_id


static func _report(message: String) -> void:
	push_error(message)
	printerr(message)
