extends Node
## The Town Hall's room (2026-11-18): its floor and walls by rays, and pictures inside, to place things in it.
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/lab_hall.gd
## Prints HALL lines (a map of the floor in the hall's own metres: '#' no floor, '.' floor, 'o' floor with
## something standing on it) and saves pictures to tools/town_planner/build/out/lab/hall_*.png. Quits.
var game: Node


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		await get_tree().process_frame


func _hall() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("house_interiors"):
		if str(node.get("home_kind")) == "town_hall": return node as Node3D
	return null


func _go() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void: print("HALL watchdog"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"): await (arrival as Node).skip_to_free_home()
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.hours = 12.0; tod.paused = true
	var hall := _hall()
	if hall == null: print("HALL none"); get_tree().quit(); return
	var player: Node3D = game.get("player")
	var centre := hall.to_global(Vector3(0, 0.793, 3.5) / 26.0)
	player.global_position = centre + Vector3.UP * 0.3
	await _wait(8.0)
	print("HALL node %s at %s basis %s; centre %s" % [hall.get_path(), hall.global_position, hall.global_basis, centre])
	var space := hall.get_world_3d().direct_space_state
	var skip: Array[RID] = []
	if player is CollisionObject3D: skip.append((player as CollisionObject3D).get_rid())
	# the outside wall, centred on each side and at the back: horizontal rays from outside toward the middle, at
	# a bench's back height (0.6 m over the floor)
	for side: Array in [["+x", Vector3(15, 0, -0.76), Vector3(0, 0, -0.76)], ["-x", Vector3(-15, 0, -0.76), Vector3(0, 0, -0.76)],
			["-z", Vector3(0, 0, -16), Vector3(0, 0, -0.76)]]:
		for h: float in [0.3, 0.6, 1.0]:
			var a := hall.to_global((Vector3(side[1]) + Vector3(0, 0.805 + h, 0)) / 26.0)
			var b := hall.to_global((Vector3(side[2]) + Vector3(0, 0.805 + h, 0)) / 26.0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1, skip))
			print("HALL wall %s at %.1f m up: %s" % [side[0], h, (hall.to_local(hit.position) * 26.0) if not hit.is_empty() else "none"])
	# the floor, every half metre of the hall's own metres (p = to_local * 26)
	for z in range(-40, 30):
		var row := ""
		for x in range(-30, 31):
			var p := Vector3(x * 0.5, 0.0, z * 0.5)
			var top := hall.to_global((p + Vector3(0, 2.5, 0)) / 26.0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 3.5, 1, skip))
			if hit.is_empty(): row += " "; continue
			var h := (hall.to_local(hit.position) * 26.0).y
			row += "." if absf(h - 0.805) < 0.08 else ("o" if h > 0.885 and h < 2.4 else "#")
		print("HALL z %5.1f %s" % [z * 0.5, row])
	# pictures: from the door toward the back, and from the back toward the door
	var cam := Camera3D.new(); cam.fov = 75.0; game.add_child(cam)
	for view: Array in [["door", Vector3(0, 2.4, 6.5), Vector3(0, 1.0, -6)], ["back", Vector3(0, 2.4, -4), Vector3(0, 1.0, 7)],
			["left", Vector3(6, 2.4, 2), Vector3(-6, 0.8, 2)], ["right", Vector3(-6, 2.4, 2), Vector3(6, 0.8, 2)]]:
		var from := hall.to_global(Vector3(view[1]) / 26.0)
		cam.look_at_from_position(from, hall.to_global(Vector3(view[2]) / 26.0), Vector3.UP); cam.make_current()
		await _wait(2.0)
		var image := get_viewport().get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path("res://tools/town_planner/build/out/lab/hall_%s.png" % view[0]))
	print("HALL done")
	get_tree().quit()
