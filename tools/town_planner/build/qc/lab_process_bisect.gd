extends Node
## Which mod script makes the half-second stutter (2026-11-23, stutter_lab.gd: with unfplap the slow frames spend
## 15-50 ms in _process, no shader compiles). While the player walks and the camera turns (as in stutter_lab.gd),
## the processing of one group of nodes at a time is switched off for SPAN seconds (their _process and
## _physics_process; grouped by script file, every node whose script comes from a mod or a mod's extension of a game
## script), and the frames over 25 ms are counted with it off. Prints BISECT lines, the groups by slow frames
## (fewest first: the culprit's group stops the stutter). Quits by itself.
##   godot --xr-mode off --resolution 1600x900 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/lab_process_bisect.gd

const SPAN := 6.0
const SPEED := 4.0
const TURN := 0.9
const LOOP := [Vector2(118, -160), Vector2(88, -186), Vector2(40, -180), Vector2(20, -177), Vector2(60, -215), Vector2(118, -200)]
var game: Node
var player: Node3D
var cam: Camera3D
var _walking := false
var _leg := 0
var _along := 0.0
var _yaw := 0.0
var _counting := false
var _slow := 0
var _frames := 0
var _worst := 0.0


func _ready() -> void:
	process_priority = -1000
	_go.call_deferred()


func _process(delta: float) -> void:
	if _counting:
		_frames += 1
		if delta * 1000.0 > 25.0: _slow += 1
		_worst = maxf(_worst, delta * 1000.0)
	if not _walking: return
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


func _count(seconds: float) -> Array:
	_slow = 0; _frames = 0; _worst = 0.0; _counting = true
	await _wait(seconds)
	_counting = false
	return [_slow, _frames, _worst]


## A mod's script, or a game script a mod extends (the loader's user://mods/.bases chain): the script or any base.
func _modded(script: Script) -> String:
	var s := script
	while s != null:
		var path := s.resource_path
		if path.begins_with("res://mods/") or path.begins_with("user://"): return script.resource_path if not script.resource_path.is_empty() else path
		s = s.get_base_script()
	return ""


func _groups() -> Dictionary:
	var out := {}
	for node: Node in get_tree().root.find_children("*", "", true, false):
		var script := node.get_script() as Script
		if script == null: continue
		var key := _modded(script)
		if key.is_empty(): continue
		if not out.has(key): out[key] = []
		(out[key] as Array).append(node)
	return out


func _go() -> void:
	var watchdog := get_tree().create_timer(1500.0)
	watchdog.timeout.connect(func() -> void: print("BISECT watchdog: quitting"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(game): print("BISECT no game"); get_tree().quit(); return
	player = game.get("player")
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.hours = 12.0; tod.paused = true
	cam = Camera3D.new(); cam.name = "BisectCamera"; cam.far = 4000.0; cam.fov = 75.0
	game.add_child(cam); cam.make_current()
	player.global_position = Vector3(118, -11.5, -160)
	await _wait(45.0)
	_walking = true
	await _wait(10.0)
	var base: Array = await _count(SPAN * 2.0)
	print("BISECT baseline: %d slow of %d frames in %.0f s (worst %.0f ms)" % [base[0], base[1], SPAN * 2.0, base[2]])
	var groups := _groups()
	print("BISECT %d modded script groups" % groups.size())
	var rows: Array = []
	for key: String in groups:
		var nodes: Array = groups[key]
		var was: Array = []
		for node: Node in nodes:
			if not is_instance_valid(node): was.append([]); continue
			was.append([node.is_processing(), node.is_physics_processing()])
			node.set_process(false); node.set_physics_process(false)
		if was.all(func(w: Array) -> bool: return w.is_empty() or (not w[0] and not w[1])):
			for k in nodes.size():
				if is_instance_valid(nodes[k]) and not (was[k] as Array).is_empty(): nodes[k].set_process(was[k][0]); nodes[k].set_physics_process(was[k][1])
			continue
		await _wait(0.5)
		var r: Array = await _count(SPAN)
		for k in nodes.size():
			if is_instance_valid(nodes[k]) and not (was[k] as Array).is_empty(): nodes[k].set_process(was[k][0]); nodes[k].set_physics_process(was[k][1])
		rows.append([r[0], key, nodes.size(), r[1], r[2]])
		print("BISECT off %-70s x%-3d slow %3d of %4d frames (worst %.0f ms)" % [key, nodes.size(), r[0], r[1], r[2]])
		await _wait(0.5)
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	print("BISECT fewest slow frames with the group off (baseline %.1f per %.0f s):" % [float(base[0]) / 2.0, SPAN])
	for row: Array in rows.slice(0, 8): print("BISECT   %3d  %s x%d" % [row[0], row[1], row[2]])
	get_tree().quit()
