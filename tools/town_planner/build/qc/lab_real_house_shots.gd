extends Node
## A real (lived-in) house of a design (--design f), the one nearest the town middle, from the same views as
## lab_bg_house_shots.gd: to tell what a background house got wrong from what the design itself looks like.
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
	var design := _arg("--design", "f")
	var house: Node3D = null; var best := 1e9
	for n: Node in get_tree().root.find_children("*", "Node3D", true, false):
		if not n.scene_file_path.get_file().begins_with("house_%s." % design): continue
		var d := Vector2((n as Node3D).global_position.x - 60.0, (n as Node3D).global_position.z + 180.0).length()
		if d < best: best = d; house = n
	if house == null: print("REAL none"); get_tree().quit(); return
	game.get("player").global_position = house.global_position + Vector3(10, 1, 10)
	await get_tree().create_timer(20.0).timeout
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.set("hours", 11.0)
	var cam := Camera3D.new(); get_tree().current_scene.add_child(cam); cam.fov = 60.0
	var c := house.global_position
	var z := house.global_basis.z.normalized(); var x := house.global_basis.x.normalized()
	for v: Array in [["front7", z], ["back7", -z], ["left7", x], ["right7", -x]]:
		cam.global_position = c + (v[1] as Vector3) * 7.0 + Vector3.UP * 2.0
		game.get("player").global_position = c + (v[1] as Vector3) * 9.0
		cam.look_at(c + Vector3.UP * 3.0, Vector3.UP); cam.make_current()
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(_arg("--shots", "").path_join("real_%s_%s.png" % [design, v[0]]))
	print("REAL %s %s at %s" % [design, house.name, c.round()])
	get_tree().quit()
