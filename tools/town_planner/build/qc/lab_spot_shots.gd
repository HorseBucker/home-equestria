extends Node
## Pictures round a point from four sides (--at x,y,z, --dist m, --height m, --shots DIR, --tag NAME). Prints SPOT lines.
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
	var p := _arg("--at", "0,0,0").split(",")
	var at := Vector3(float(p[0]), float(p[1]), float(p[2]))
	var dist := float(_arg("--dist", "10")); var h := float(_arg("--height", "2"))
	game.get("player").global_position = at + Vector3(0, 2, dist)
	await get_tree().create_timer(25.0).timeout
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.set("hours", 11.0)
	var cam := Camera3D.new(); get_tree().current_scene.add_child(cam); cam.fov = 70.0
	var shots := _arg("--shots", ""); var tag := _arg("--tag", "x")
	var k := 0
	for dir: Vector3 in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0.7, 0, 0.7), Vector3(-0.7, 0, 0.7), Vector3(0.7, 0, -0.7), Vector3(-0.7, 0, -0.7)]:
		var from := at + dir * dist + Vector3.UP * h
		game.get("player").global_position = from + Vector3(0, -30, 0)
		cam.global_position = from; cam.look_at(at, Vector3.UP); cam.make_current()
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(shots.path_join("spot_%d_%s.png" % [k, tag])); k += 1
	print("SPOT done")
	get_tree().quit()
