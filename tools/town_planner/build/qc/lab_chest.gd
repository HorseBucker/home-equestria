extends Node
## The Town Hall chest (2026-11-18) in the real game: pictures of it shut and open and of its page, and its moves
## (briefcase -> chest -> briefcase, discard) checked. Prints CHEST lines; pictures in build/out/lab/chest_*.png.
##   godot --xr-mode off --resolution 1600x900 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/lab_chest.gd
var game: Node
var lab_cam: Camera3D
const STORE := preload("res://world/props/town_chest/chest_store.gd")


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		if is_instance_valid(lab_cam) and not lab_cam.current: lab_cam.make_current()
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _wait(1.5)
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tools/town_planner/build/out/lab/chest_%s.png" % name))


func _go() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void: print("CHEST watchdog"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"): await (arrival as Node).skip_to_free_home()
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.hours = 12.0; tod.paused = true
	var chest: Node3D = game.get_node_or_null("Zones/PonyvilleTown/TownHallChest")
	print("CHEST node ", chest, " at ", chest.global_position if chest != null else "-")
	if chest == null: get_tree().quit(); return
	var player: Node3D = game.get("player")
	var front := chest.global_transform * Vector3(0, 0, 1.9)
	player.global_position = front + Vector3.UP * 0.2
	await _wait(6.0)
	var cam := Camera3D.new(); cam.fov = 60.0; game.add_child(cam); lab_cam = cam
	cam.look_at_from_position(chest.global_transform * Vector3(0.9, 1.3, 1.9), chest.global_transform * Vector3(0, 0.35, 0), Vector3.UP); cam.make_current()
	await _shot("shut")
	chest.set_open(true)
	await _shot("open")
	var box: MeshInstance3D = chest.get_node_or_null("Box")
	print("CHEST box visible %s in tree %s aabb %s layers %d; viewport occlusion %s" % [box.visible, box.is_visible_in_tree(), box.global_transform * box.get_aabb(), box.layers, get_viewport().use_occlusion_culling])
	for occ: Node in get_tree().root.find_children("*", "OccluderInstance3D", true, false):
		var o := occ as OccluderInstance3D
		if o.global_position.distance_to(chest.global_position) < 20.0: print("CHEST occluder near: ", o.get_path(), " at ", o.global_position)
	get_viewport().use_occlusion_culling = false
	await _shot("open_nocull")
	get_viewport().use_occlusion_culling = true
	cam.look_at_from_position(chest.global_transform * Vector3(-2.5, 1.7, 3.5), chest.global_transform * Vector3(0, 0.4, 0), Vector3.UP)
	await _shot("room")
	chest.set_open(false)
	cam.queue_free()
	# the moves, on the briefcase's own store
	var store := STORE.briefcase(game)
	print("CHEST grant fish ", store.call("grant", "river-fish", 5), " notebook ", store.call("grant", "notebook", 1))
	var fish := -1
	for i in (store.get("slots") as Array).size():
		if not (store.slots[i] as Dictionary).is_empty() and str(store.slots[i].id) == "river-fish": fish = i
	print("CHEST store 2 fish: ", STORE.store_slot(game, fish, 2), " | store all: ", STORE.store_slot(game, fish, -1))
	print("CHEST entries ", STORE.entries(game))
	print("CHEST take 1: ", STORE.take(game, 0, 1), " | discard 1: ", STORE.discard(game, 0, 1), " | entries ", STORE.entries(game))
	# the page, as E would open it
	chest.access()
	await _wait(1.0)
	print("CHEST menu open ", chest.menu.opened if chest.menu != null else false, " lid open ", chest.is_open())
	await _shot("page")
	chest.menu.close()
	await _wait(1.0)
	print("CHEST after close: menu ", chest.menu.opened, " lid ", chest.is_open())
	print("CHEST done")
	get_tree().quit()
