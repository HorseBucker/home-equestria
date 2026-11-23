extends Node
## The in-game map's aerial picture of the rebuilt Ponyville (2026-11-17): straight-down orthographic shots
## of the town in the real game, 0.25 m a pixel, one per 256 m tile of world/ui/aerial_map's "town" level
## (north up: image top is -Z). tools/town_planner/build/make_map_tiles.py grades them and writes the tiles.
##   godot --xr-mode off --resolution 1024x1024 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/capture_map.gd
## (needs a window, square; set APPDATA to a scratch folder first). Noon, the clock held; the HUD and the
## player hidden while each shot is taken. Always summer (2026-11-23: "The pictures were taken during Winter or early
## Spring, where the trees are barren. I want them taken during Summer, where the trees are fully out and green"): the
## season is pinned (season_state.gd pin(), as --season=summer would) with no snow. Shots: tools/town_planner/build/out/map/shot_<x>_<z>.png (x, z: the
## tile's north-west corner in metres). Quits by itself.

const OUT := "res://tools/town_planner/build/out/map"
## The tiles: x from X0 to X1, z from Z0 to Z1, every TILE metres (the plan's edge is x -300..500, z -588..188).
const X0 := -512
const X1 := 512
const Z0 := -768
const Z1 := 256
const TILE := 256.0
## The camera this far above the ground at the tile's middle: low enough that houses (drawn to 250 m) at the
## tile's corners (181 m off) still draw.
const HEIGHT := 60.0           # (110 m was above the low clouds' undersides west of town)
var game: Node
var cam: Camera3D
var player: Node3D


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		await get_tree().process_frame


func _hud(on: bool) -> void:
	for layer: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = on
	# and every interface panel drawn straight into the window (the hotbar, the minimap)
	for panel: Node in get_tree().root.find_children("*", "Control", true, false):
		if not (panel.get_parent() is Control):
			if on and panel.has_meta("map_hid"): (panel as Control).visible = true; panel.remove_meta("map_hid")
			elif not on and (panel as Control).visible: panel.set_meta("map_hid", true); (panel as Control).visible = false
	if is_instance_valid(player): player.visible = on


## Clear air for a shot (2026-11-18, round 8: the tiles south of the town, x 0..512 z 0..256, came out hazed by the
## Everfree's fog and were left out): every environment's fog and volumetric fog, and every fog volume, off while
## the shot is taken.
var _air: Array = []
func _clear_air(clear: bool) -> void:
	if not clear:
		for row: Array in _air:
			if not is_instance_valid(row[0]): continue
			if row[0] is FogVolume: (row[0] as FogVolume).visible = row[1]
			else: (row[0] as Environment).fog_enabled = row[1]; (row[0] as Environment).volumetric_fog_enabled = row[2]
		_air.clear()
		return
	var envs: Array = []
	for node: Node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		if (node as WorldEnvironment).environment != null: envs.append((node as WorldEnvironment).environment)
	for node: Node in get_tree().root.find_children("*", "Camera3D", true, false):
		if (node as Camera3D).environment != null: envs.append((node as Camera3D).environment)
	if get_viewport().world_3d != null and get_viewport().world_3d.environment != null: envs.append(get_viewport().world_3d.environment)
	for env: Environment in envs:
		_air.append([env, env.fog_enabled, env.volumetric_fog_enabled])
		env.fog_enabled = false; env.volumetric_fog_enabled = false
	for node: Node in get_tree().root.find_children("*", "FogVolume", true, false):
		_air.append([node, (node as FogVolume).visible]); (node as FogVolume).visible = false


## The top of anything built in the sky over this tile (2026-11-23: "Rainbow Dash's home isn't visible in the map,
## but the shadow of it is"): the Cloudominium floats above HEIGHT, so the camera started under it and only its shadow
## on the ground was in the shot. Over its tile the camera goes above its top; -INF where there is nothing.
func _sky_top(cx: float, cz: float) -> float:
	var top := -INF
	for runtime: Node in get_tree().root.find_children("UsableCloudominium", "", true, false):
		var house := runtime.get_parent() as Node3D
		if house == null: continue
		for node: Node in [house] + house.find_children("*", "GeometryInstance3D", true, false):
			var shape := node as GeometryInstance3D
			if shape == null or not shape.is_visible_in_tree(): continue
			var box: AABB = shape.global_transform * shape.get_aabb()
			var mid := box.get_center()
			if absf(mid.x - cx) <= TILE * 0.5 and absf(mid.z - cz) <= TILE * 0.5: top = maxf(top, box.end.y)
	return top


func _go() -> void:
	# The town at a lower density (town_density.gd; its user://town_density.cfg): shots in out/map_<setting>.
	var density: String = preload("res://world/towns/ponyville/town_density.gd").current()
	var out := OUT if density == "high" else OUT + "_" + density
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var watchdog := get_tree().create_timer(1800.0)
	watchdog.timeout.connect(func() -> void: print("MAP watchdog: quitting"); get_tree().quit())
	for i in 1200:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(game): print("MAP no game"); get_tree().quit(); return
	player = game.get("player")
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
		await _wait(3.0)
	var seasons: Node = game.get_node_or_null("SeasonState")
	if seasons != null and seasons.has_method("pin"):
		seasons.call("pin", "summer", 0.0)
		if seasons.has_method("tick"): seasons.call("tick")
		await _wait(5.0)
		print("MAP season: %s" % str(seasons.call("season")))
	else: print("MAP no season state: the trees take the calendar's season")
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.hours = 12.0; tod.paused = true
	cam = Camera3D.new(); cam.name = "MapCamera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = TILE
	cam.near = 1.0; cam.far = 600.0
	game.add_child(cam)
	# `--map-only x:z,x:z`: just these tiles (by their north-west corner)
	var only := PackedStringArray()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--map-only" and i + 1 < args.size(): only = args[i + 1].split(",")
	var first := true
	var x := X0
	while x < X1:
		var z := Z0
		while z < Z1:
			var cx := float(x) + TILE * 0.5
			var cz := float(z) + TILE * 0.5
			if not only.is_empty() and not only.has("%d:%d" % [x, z]):
				z += int(TILE); continue
			var ground: float = WorldTerrain.instance.height_at(Vector3(cx, 0, cz))
			if not is_finite(ground): ground = -12.0
			# The player stands at the tile's middle so it streams in, but never in the Everfree: there the
			# forest's own fog closes in round him and the shot is a blue haze. South of z 0 east of x 0 he
			# waits at the tile's north edge, by the town.
			# (round 8: with the fog cleared for the shot (_clear_air), he stands at the middle of those too: from
			# their north edge the trees and the ground's detail did not stream in over most of the tile)
			var stand := Vector3(cx, 0, cz)
			var stand_ground: float = WorldTerrain.instance.height_at(stand)
			player.global_position = Vector3(stand.x, (stand_ground if is_finite(stand_ground) else ground) + 0.5, stand.z)
			if "velocity" in player: player.set("velocity", Vector3.ZERO)
			await _wait(25.0 if first else 12.0)
			first = false
			var eye := Vector3(cx, maxf(ground, -12.0) + HEIGHT, cz)
			eye.y = maxf(eye.y, _sky_top(cx, cz) + 3.0)
			cam.look_at_from_position(eye, eye + Vector3.DOWN, Vector3(0, 0, -1))
			cam.make_current()
			_hud(false)
			_clear_air(true)
			for f in 4: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			image.save_png(ProjectSettings.globalize_path(out).path_join("shot_%d_%d.png" % [x, z]))
			_hud(true)
			_clear_air(false)
			cam.clear_current(true)
			print("MAP shot %d %d (%dx%d)" % [x, z, image.get_width(), image.get_height()])
			z += int(TILE)
		x += int(TILE)
	print("MAP done")
	get_tree().quit()
