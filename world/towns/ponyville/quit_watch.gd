extends Node
## A safety net for quitting (2026-11-21 play test: the game now and then hung on quit, its log cut off before the
## end, with no TV on). When the game starts to close:
## - user://logs/quit_trace.txt records each step of the shutdown as it happens (written straight to disk, so it
##   survives a forced close): the main pieces of the game as they are taken down, and anything that held the close up
##   for more than a moment. The last lines of a hung close name what it was stuck on.
## - a small watcher outside the game (PowerShell on Windows, sh elsewhere) closes the game if it is still running
##   LIMIT seconds later. By then the world is saved (the game saves before it starts closing). A game that closes
##   normally is gone before the watcher looks, and the watcher finds nothing to do.
## Lives under the root (it outlives world reloads), attached once by town_root.gd.

const NAME := "QuitWatch"
const LIMIT := 10               # seconds from the start of the close (after the save) to a forced close
const WINDOW_LIMIT := 25        # from the window's close button (the game saves first)
const TRACE := "user://logs/quit_trace.txt"
const SLOW_MS := 300

var _file: FileAccess
var _started := 0
var _last := 0
var _watching := false


static func attach(town: Node) -> void:
	var root := town.get_tree().root
	if root.get_node_or_null(NAME) != null: return
	var node: Node = (load("res://world/towns/ponyville/quit_watch.gd") as GDScript).new()
	node.name = NAME
	root.add_child.call_deferred(node)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_begin("the window's close button", WINDOW_LIMIT)


## The root is being taken down: the game is quitting (its world already saved).
func _exit_tree() -> void:
	_begin("the game closing", LIMIT)
	_note("the game's pieces are being taken down")


func _begin(why: String, limit: int) -> void:
	if _watching:
		return
	_watching = true
	_started = Time.get_ticks_msec(); _last = _started
	_file = FileAccess.open(TRACE, FileAccess.WRITE)
	_note("quit started (%s) at %s; a forced close after %d s if it hangs" % [why, Time.get_datetime_string_from_system(), limit])
	if is_inside_tree():
		# the top pieces close in the reverse of their order: a hang lies in the one after the last listed as taken down
		# (a piece's own closing work runs before anything of it is taken down)
		var order: Array[String] = []
		for child: Node in get_tree().root.get_children():
			order.push_front(str(child.name))
		_note("the top pieces close in this order: " + ", ".join(order))
		get_tree().node_removed.connect(_removed)
	_watcher(limit)


func _removed(node: Node) -> void:
	var now := Time.get_ticks_msec()
	var depth := str(node.get_path()).count("/")
	if now - _last >= SLOW_MS:
		_note("held up %d ms, then took down %s" % [now - _last, node.get_path()])
	elif depth <= 3 or node.get_script() != null:
		# (every piece with a script of its own: those are what do work while closing, and the last line names the one
		# a hang is in, or the one just before it)
		_note("took down %s" % node.get_path())
	_last = now


func _note(text: String) -> void:
	if _file == null:
		return
	_file.store_line("%6d ms  %s" % [Time.get_ticks_msec() - _started, text])
	_file.flush()


## The watcher: a process of its own, so it works whatever state the game is stuck in.
func _watcher(limit: int) -> void:
	var pid := OS.get_process_id()
	var trace := ProjectSettings.globalize_path(TRACE)
	var line := "%d s passed and the game was still running: closed it" % limit
	var started := -1
	if OS.get_name() == "Windows":
		started = OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command",
			"Start-Sleep -Seconds %d; if (Get-Process -Id %d -ErrorAction SilentlyContinue) { Add-Content -LiteralPath '%s' -Value '%s'; Stop-Process -Id %d -Force }"
			% [limit, pid, trace.replace("'", "''"), line, pid]])
	else:
		started = OS.create_process("sh", ["-c", "sleep %d; if kill -0 %d 2>/dev/null; then echo '%s' >> '%s'; kill -9 %d; fi" % [limit, pid, line, trace, pid]])
	_note("watcher %s" % ("started" if started > 0 else "could not start"))
