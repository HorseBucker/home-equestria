extends Node
## Pictures of a node in the town from around and above (2026-11-18: the market's white tent, to place Watch
## Party's television stand in it). Its own frame: +Z is its front.
##   godot --xr-mode off --resolution 1600x900 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/lab_tent.gd [--node RNLScenery/Town/Market/tent_friagram_pinkish_01]
## Saves tools/town_planner/build/out/lab/tent_<view>.png; prints TENT lines. Quits.
var game: Node
var cam: Camera3D


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		if is_instance_valid(cam) and not cam.current: cam.make_current()
		await get_tree().process_frame


func _go() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void: print("TENT watchdog"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"): await (arrival as Node).skip_to_free_home()
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.hours = 12.0; tod.paused = true
	var path := "RNLScenery/Town/Market/tent_friagram_pinkish_01"
	var args := OS.get_cmdline_user_args()
	if "--node" in args: path = args[args.find("--node") + 1]
	var dist := float(args[args.find("--dist") + 1]) if "--dist" in args else 13.0
	var town := game.get_node("Zones/PonyvilleTown")
	var node: Node3D = town.get_node_or_null(path)
	if node == null: node = town.find_child(path, true, false) as Node3D
	if node == null: print("TENT none at ", path); get_tree().quit(); return
	var t := Transform3D(Basis(Vector3.UP, node.global_basis.get_euler().y), node.global_position)
	print("TENT %s at %s yaw %.3f" % [path, node.global_position, node.global_basis.get_euler().y])
	var player: Node3D = game.get("player")
	player.global_position = t * Vector3(0, 0.3, 14)
	await _wait(6.0)
	cam = Camera3D.new(); cam.fov = 70.0; game.add_child(cam)
	var views: Array = [["front", Vector3(0, 2.2, 13), Vector3(0, 1, 0)], ["inside", Vector3(0, 1.7, 5.2), Vector3(0, 1, -6)],
			["above", Vector3(0.01, 22, 0), Vector3(0, 0, 0)], ["side", Vector3(12, 3, 2), Vector3(0, 1, 0)]]
	if "--dist" in args:
		views = [["n", Vector3(0, 1.2, dist), Vector3(0, 0.8, 0)], ["e", Vector3(dist, 1.2, 0), Vector3(0, 0.8, 0)],
			["s", Vector3(0, 1.2, -dist), Vector3(0, 0.8, 0)], ["w", Vector3(-dist, 1.2, 0), Vector3(0, 0.8, 0)]]
	var tag := str(node.name) + "_" if "--dist" in args else ""
	for view: Array in views:
		cam.look_at_from_position(t * Vector3(view[1]), t * Vector3(view[2]), Vector3.UP if view[0] != "above" else Vector3.FORWARD)
		await _wait(2.0)
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tools/town_planner/build/out/lab/tent_%s%s.png" % [tag, view[0]]))
	print("TENT done")
	get_tree().quit()
