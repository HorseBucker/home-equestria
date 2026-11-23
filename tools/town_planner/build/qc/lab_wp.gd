extends Node
## Watch Party with the overhaul (2026-11-18): where its market stand and forest finds stand, with pictures.
## Runs in the installed game too (a scratch APPDATA whose settings.cfg has [debug] unlocked=true; this script in a
## small extra pack). Prints WP lines; pictures in tools/town_planner/build/out/lab/wp_*.png (source runs) or the
## user folder (installed game). Quits.
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


func _shot(name: String) -> void:
	await _wait(2.0)
	var dir := "res://tools/town_planner/build/out/lab/" if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://tools/town_planner/build/out/lab")) else "user://"
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(dir + "wp_%s.png" % name))


func _go() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void: print("WP watchdog"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"): await (arrival as Node).skip_to_free_home()
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.hours = 12.0; tod.paused = true
	var player: Node3D = game.get("player")
	var shop: Node = game.get("shop_world")
	var spot: Variant = shop.call("_watch_party_spot") if shop != null and shop.has_method("_watch_party_spot") else null
	print("WP market stand spot: ", spot)
	# the vintage set's forest spot: walk there so it is laid out
	var finds: Variant = load("res://mods/watch_party/finds.gd") if ResourceLoader.exists("res://mods/watch_party/finds.gd") else null
	var crt: Vector3 = (finds as GDScript).call("forest_point", "goods:watch-tv-vintage") if finds != null else Vector3.INF
	print("WP vintage set forest point: ", crt)
	cam = Camera3D.new(); cam.fov = 65.0; game.add_child(cam)
	if crt.is_finite():
		player.global_position = Vector3(crt.x - 6, crt.y + 2.0 if crt.y != 0.0 else -8.0, crt.z - 6)
		await _wait(20.0)
		for node: Node in game.find_children("WatchPartyFind_*", "", true, false):
			print("WP find ", node.name, " at ", (node as Node3D).global_position)
			var at := (node as Node3D).global_position
			cam.look_at_from_position(at + Vector3(-5, 3, -5), at, Vector3.UP)
			await _shot("crt")
		var cottage := Vector3(407.9, -12.0, 1.08)
		cam.look_at_from_position(cottage + Vector3(-12, 14, -14), crt if crt.y != 0.0 else Vector3(crt.x, cottage.y, crt.z), Vector3.UP)
		await _shot("crt_cottage")
	if spot is Array and not (spot as Array).is_empty():
		var at: Vector3 = spot[0]
		player.global_position = at + Vector3(0, 1, 12)
		await _wait(8.0)
		var front: Basis = spot[1]
		cam.look_at_from_position(at + front * Vector3(0, 2.0, 6.0), at + Vector3.UP * 0.8, Vector3.UP)
		await _shot("stand")
		cam.look_at_from_position(at + Vector3(0, 25, 0.01), at, Vector3.FORWARD)
		await _shot("stand_above")
	print("WP done")
	get_tree().quit()
