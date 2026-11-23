extends Node
## Hayburger's front door from outside (2026-11-22 play test: sky seen through the wall above the inner doorway).
## Pictures to --shots, and the meshes a ray from the camera through the gap hits. Prints HB lines.
func _ready() -> void:
	_go.call_deferred()

func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	return args[args.find(name) + 1] if name in args else fallback

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	await get_tree().create_timer(12.0).timeout
	var shell: Node3D = null
	for n: Node in get_tree().root.find_children("*", "Node3D", true, false):
		if str(n.name).to_lower().contains("hayburger") and n is Node3D:
			print("HB node %s %s at %s" % [n.get_path(), n.get_class(), (n as Node3D).global_position.round()])
			if shell == null: shell = n
	var door: Node3D = null
	for n: Node in get_tree().root.find_children("*", "Node3D", true, false):
		if n.get_script() != null and str((n.get_script() as Script).resource_path).ends_with("hayburger_door.gd"): door = n; break
	if door == null: print("HB no door"); get_tree().quit(); return
	print("HB door at %s facing %s" % [door.global_position, door.global_basis.z])
	var bj: Node3D = get_tree().root.find_child("burger_joint_01", true, false)
	for key in bj.get_meta_list():
		var st: Variant = bj.get_meta(key)
		if st is Dictionary and (st as Dictionary).has("report"):
			var r: Dictionary = st.report
			var box: AABB = r.door_opening
			print("HB shell door local %s; global from %s to %s; ceiling_y %s floor_y %s" % [box, bj.global_transform * box.position, bj.global_transform * box.end, r.ceiling_y, r.floor_y])
	var room: Node3D = get_tree().root.find_child("RestaurantInterior", true, false)
	print("HB room origin %s basis x %s z %s scale %s" % [room.global_position, room.global_basis.x, room.global_basis.z, room.global_basis.get_scale()])
	print("HB room front wall top (0, 3.6, 5.12) -> %s; lintel bottom (0, 2.76, 5.0) -> %s" % [room.global_transform * Vector3(0, 3.6, 5.24), room.global_transform * Vector3(0, 2.76, 5.0)])
	var player: Node3D = game.get("player")
	player.global_position = door.global_position + door.global_basis.z * 6.0
	await get_tree().create_timer(4.0).timeout
	var cam := Camera3D.new(); get_tree().current_scene.add_child(cam)
	var shots := _arg("--shots", "")
	var out := Vector3(0, 0, 1)
	var d := Vector3(-8.4, -11.88, -184.8)
	var views := {"front": [d + out * 5.5 + Vector3.UP * 1.9, d - out * 4.0 + Vector3.UP * 2.6],
		"low": [d + out * 3.0 + Vector3.UP * 1.2, d - out * 5.0 + Vector3.UP * 3.2],
		"inside": [d - out * 3.5 + Vector3.UP * 2.0, d + out * 1.0 + Vector3.UP * 3.0],
		"inside_up": [d - out * 6.0 + Vector3.UP * 2.0, d - out * 3.0 + Vector3.UP * 4.0]}
	var space := get_viewport().get_world_3d().direct_space_state
	for key: String in views:
		cam.global_position = views[key][0]
		cam.look_at(views[key][1], Vector3.UP); cam.fov = 70.0; cam.make_current()
		await get_tree().process_frame; await get_tree().process_frame; await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shots.path_join("hb_%s.png" % key))
	get_tree().quit()
