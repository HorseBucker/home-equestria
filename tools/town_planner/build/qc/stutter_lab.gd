extends Node
## Micro-stutter while walking (2026-11-23 play test: "little microstutters that happen pretty much constantly as I
## walk and pan my camera around, but it only happens when I have those mods on ... It feels like it happens every
## second"). The player walks a loop of streets round the town square while the camera turns; every frame's time is
## kept for WALK seconds. Prints STUTTER lines: frame count, median, the frames over 25 ms and 40 ms, how far apart
## the slow frames come (a steady beat points at a timer), and the process / physics time sampled on slow frames.
##   godot --xr-mode off --resolution 1600x900 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/stutter_lab.gd [--stutter-tag NAME]
## (APPDATA set to a scratch profile; the mods to test go in its home-equestria-public/mods). Quits by itself.

const WALK := 60.0
const SPEED := 4.0              # m/s, a trot
const TURN := 0.9               # rad/s the camera turns
const LOOP := [Vector2(118, -160), Vector2(88, -186), Vector2(40, -180), Vector2(20, -177), Vector2(60, -215), Vector2(118, -200)]
var game: Node
var player: Node3D
var cam: Camera3D
var _t := 0.0
var _walking := false
var _leg := 0
var _along := 0.0
var _yaw := 0.0
var _frames := PackedFloat32Array()
var _at := PackedFloat32Array()
var _proc := PackedFloat32Array()
var _phys := PackedFloat32Array()
## per frame: the process phase (first node's _process to the last's), physics steps taken, pipelines compiled
var _script := PackedFloat32Array()
var _steps := PackedInt32Array()
var _comp := PackedInt32Array()
var _start_us := 0
var _last_phys := 0
var _last_comp := 0
var _tail: Node


class Tail extends Node:
	var lab: Node
	func _process(_d: float) -> void:
		lab.call("_tail_done")


func _pipelines() -> int:
	var n := 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		n += RenderingServer.get_rendering_info(info)
	return n


func _tail_done() -> void:
	if not _walking or _start_us == 0: return
	_script.append((Time.get_ticks_usec() - _start_us) / 1000.0)


func _ready() -> void:
	process_priority = -1000
	_go.call_deferred()


func _process(delta: float) -> void:
	if not _walking: return
	_t += delta
	_start_us = Time.get_ticks_usec()
	var pf := Engine.get_physics_frames(); _steps.append(pf - _last_phys); _last_phys = pf
	var pc := _pipelines(); _comp.append(pc - _last_comp); _last_comp = pc
	_frames.append(delta * 1000.0); _at.append(_t)
	_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var a: Vector2 = LOOP[_leg]; var b: Vector2 = LOOP[(_leg + 1) % LOOP.size()]
	_along += SPEED * delta
	if _along >= a.distance_to(b): _along -= a.distance_to(b); _leg = (_leg + 1) % LOOP.size(); return
	var p := a.lerp(b, _along / a.distance_to(b))
	var g: float = WorldTerrain.instance.height_at(Vector3(p.x, 0, p.y))
	if not is_finite(g): g = -12.0
	player.global_position = Vector3(p.x, g + 0.3, p.y)
	if "velocity" in player: player.set("velocity", Vector3.ZERO)
	_yaw += TURN * delta
	var eye := Vector3(p.x, g + 1.7, p.y)
	cam.look_at_from_position(eye, eye + Vector3(sin(_yaw), -0.08, cos(_yaw)), Vector3.UP)


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		await get_tree().process_frame


func _go() -> void:
	var tag := "default"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--stutter-tag" and i + 1 < args.size(): tag = args[i + 1]
	var watchdog := get_tree().create_timer(900.0)
	watchdog.timeout.connect(func() -> void: print("STUTTER watchdog: quitting"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(game): print("STUTTER no game"); get_tree().quit(); return
	player = game.get("player")
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.hours = 12.0; tod.paused = true
	cam = Camera3D.new(); cam.name = "StutterCamera"; cam.far = 4000.0; cam.fov = 75.0
	game.add_child(cam)
	cam.make_current()
	player.global_position = Vector3(118, -11.5, -160)
	await _wait(45.0)       # the town and its ponies stream in, the mods settle
	_walking = true
	await _wait(10.0)       # one lap's warm-up (first sights compile their shaders)
	_tail = Tail.new(); _tail.lab = self; _tail.process_priority = 100000; get_tree().root.add_child(_tail)
	_frames.clear(); _at.clear(); _proc.clear(); _phys.clear(); _script.clear(); _steps.clear(); _comp.clear(); _t = 0.0
	_last_phys = Engine.get_physics_frames(); _last_comp = _pipelines()
	await _wait(WALK)
	_walking = false
	var sorted := _frames.duplicate(); sorted.sort()
	var n := sorted.size()
	var slow: Array = []
	var slow_proc := 0.0; var slow_phys := 0.0; var fast_proc := 0.0; var fast_phys := 0.0; var n_fast := 0
	for i in n:
		if _frames[i] > 25.0: slow.append(i); slow_proc += _proc[i]; slow_phys += _phys[i]
		else: fast_proc += _proc[i]; fast_phys += _phys[i]; n_fast += 1
	var over40 := 0
	for f in _frames: if f > 40.0: over40 += 1
	var gaps := PackedFloat32Array()
	for k in range(1, slow.size()): gaps.append(_at[slow[k]] - _at[slow[k - 1]])
	gaps.sort()
	print("STUTTER %s frames %d in %.0f s  median %.2f ms (%.0f fps)  p99 %.1f ms  over 25 ms: %d  over 40 ms: %d  worst %.0f ms" % [tag, n, WALK,
		sorted[n / 2], 1000.0 / maxf(0.01, sorted[n / 2]), sorted[int(n * 0.99)], slow.size(), over40, sorted[n - 1]])
	print("STUTTER %s slow frames: process %.1f ms physics %.1f ms (other frames %.1f / %.1f); gap between slow frames median %.2f s" % [tag,
		slow_proc / maxf(1, slow.size()), slow_phys / maxf(1, slow.size()), fast_proc / maxf(1, n_fast), fast_phys / maxf(1, n_fast), gaps[gaps.size() / 2] if gaps.size() > 0 else 0.0])
	# frame i's delta is the time since frame i-1: its script phase is _script[i-1], its physics steps and compiles
	# were counted at frame i's start
	var s_slow := 0.0; var s_fast := 0.0; var st_slow := 0.0; var st_fast := 0.0; var c_slow := 0; var c_fast := 0; var ns := 0; var nf := 0
	var worst: Array = []
	for i in range(1, mini(n, _script.size() + 1)):
		if _frames[i] > 25.0:
			s_slow += _script[i - 1]; st_slow += _steps[i]; c_slow += _comp[i]; ns += 1
			if worst.size() < 12: worst.append("%.0f ms: script %.1f ms, %d physics steps, %d compiles" % [_frames[i], _script[i - 1], _steps[i], _comp[i]])
		else:
			s_fast += _script[i - 1]; st_fast += _steps[i]; c_fast += _comp[i]; nf += 1
	print("STUTTER %s split: slow frames script %.1f ms, physics steps %.2f, compiles %d in all; other frames script %.2f ms, physics steps %.2f, compiles %d in all" % [tag,
		s_slow / maxf(1, ns), st_slow / maxf(1, ns), c_slow, s_fast / maxf(1, nf), st_fast / maxf(1, nf), c_fast])
	for w: String in worst: print("STUTTER %s   %s" % [tag, w])
	get_tree().quit()
