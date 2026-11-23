extends Node
## Performance measurement inside the real game (2026-11-17): load, memory and frame cost of the town, at a fixed
## set of viewpoints, noon, the clock held, clear weather.
##   godot --xr-mode off --resolution 1600x900 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/perf_lab.gd [--perf-tag NAME]
## (set APPDATA to a fresh scratch folder first). Prints PERF lines: the time from engine start to a playable world,
## memory and object counts after the town settles, then for each viewpoint the frame time (mean, p95, p99),
## draw calls and triangles over SAMPLE seconds. At the flower meadow's viewpoints it measures with the meadow
## shown, hidden, and shown again (its kit rows and far dots, found by position), so the two can be compared in
## one run. Quits by itself.

const SAMPLE := 8.0
const SETTLE := 6.0
## name, where the player stands, camera height above the ground there, what it looks at
const VIEWS := [
	["square_eye", Vector2(118, -160), 1.7, Vector3(135, 2, -176)],
	["main_street", Vector2(88, -186), 1.7, Vector3(20, 2, -177)],
	["west_rows", Vector2(-10, -200), 1.7, Vector3(60, 2, -260)],
	["uptown", Vector2(178, -258), 1.7, Vector3(179, 2, -330)],
	["town_above", Vector2(60, -150), 45.0, Vector3(110, 0, -230)],
	["meadow_eye", Vector2(300, -236), 1.9, Vector3(340, 0, -280)],
	["meadow_above", Vector2(285, -222), 26.0, Vector3(345, 0, -285)],
	["meadow_from_town", Vector2(215, -250), 3.0, Vector3(330, 0, -280)],
]
const MEADOW := Rect2(245, -350, 200, 140)     # x, z of the flower meadow's rows
var game: Node
var cam: Camera3D
var player: Node3D
var _frames: PackedFloat32Array = PackedFloat32Array()
var _recording := false
var _draws := 0.0
var _tris := 0.0
var _count := 0


func _ready() -> void:
	_go.call_deferred()


func _process(delta: float) -> void:
	if not _recording: return
	_frames.append(delta * 1000.0)
	_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_tris += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_count += 1


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		await get_tree().process_frame


func _stand(view: Array) -> void:
	var at: Vector2 = view[1]
	var ground: float = WorldTerrain.instance.height_at(Vector3(at.x, 0, at.y))
	if not is_finite(ground): ground = -12.0
	player.global_position = Vector3(at.x, ground + 0.5, at.y)
	if "velocity" in player: player.set("velocity", Vector3.ZERO)
	var look: Vector3 = view[3]
	var lg: float = WorldTerrain.instance.height_at(Vector3(look.x, 0, look.z))
	cam.look_at_from_position(Vector3(at.x, ground + float(view[2]), at.y), Vector3(look.x, (lg if is_finite(lg) else ground) + look.y, look.z), Vector3.UP)
	cam.make_current()


func _measure(label: String) -> void:
	_frames.clear(); _draws = 0.0; _tris = 0.0; _count = 0
	_recording = true
	await _wait(SAMPLE)
	_recording = false
	var sorted := _frames.duplicate(); sorted.sort()
	var n := sorted.size()
	var mean := 0.0
	for f in sorted: mean += f
	mean /= maxf(1.0, float(n))
	print("PERF view %-28s frames %4d  mean %6.2f ms (%5.0f fps)  p95 %6.2f  p99 %6.2f  draws %6.0f  tris %6.2f M" % [label, n, mean, 1000.0 / maxf(mean, 0.001),
		sorted[int(n * 0.95)] if n > 0 else 0.0, sorted[int(n * 0.99)] if n > 0 else 0.0, _draws / maxf(1, _count), _tris / maxf(1, _count) / 1e6])


## The flower meadow's kit batches and far dots: MultiMeshInstance3D nodes whose instances lie in MEADOW.
func _meadow_nodes() -> Array:
	var out: Array = []
	for node: Node in get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.instance_count == 0: continue
		var box := mmi.global_transform * mmi.multimesh.get_aabb()
		var c := box.get_center()
		if MEADOW.has_point(Vector2(c.x, c.z)) and box.size.x < 80.0: out.append(mmi)
	return out


func _go() -> void:
	var tag := "default"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--perf-tag" and i + 1 < args.size(): tag = args[i + 1]
	var watchdog := get_tree().create_timer(1500.0)
	watchdog.timeout.connect(func() -> void: print("PERF watchdog: quitting"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(game): print("PERF no game"); get_tree().quit(); return
	print("PERF %s world ready at %.1f s after engine start" % [tag, Time.get_ticks_msec() / 1000.0])
	player = game.get("player")
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
	print("PERF %s playable at %.1f s after engine start" % [tag, Time.get_ticks_msec() / 1000.0])
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.hours = 12.0; tod.paused = true
	cam = Camera3D.new(); cam.name = "PerfCamera"; cam.far = 4000.0; cam.fov = 70.0
	game.add_child(cam)
	_stand(VIEWS[0])
	await _wait(40.0)       # the town and its ponies stream in around the square
	var houses := get_tree().get_nodes_in_group("house_interiors").size()
	print("PERF %s settled: memory %.0f MB static, video %.0f MB, nodes %d, objects %d, resources %d, physics 3D active %d, house interiors %d, walk-in houses in the town scene %d" % [tag,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), houses, get_tree().root.find_children("plot_*", "", true, false).size()])
	for view: Array in VIEWS:
		_stand(view)
		await _wait(SETTLE)
		var name := str(view[0])
		if name.begins_with("meadow"):
			var meadow := _meadow_nodes()
			await _measure(name + " (meadow on)")
			for m: MultiMeshInstance3D in meadow: m.visible = false
			await _wait(1.0)
			await _measure(name + " (meadow off, %d batches)" % meadow.size())
			for m: MultiMeshInstance3D in meadow: m.visible = true
			await _wait(1.0)
			await _measure(name + " (meadow on again)")
		else:
			await _measure(name)
	print("PERF %s done" % tag)
	get_tree().quit()
