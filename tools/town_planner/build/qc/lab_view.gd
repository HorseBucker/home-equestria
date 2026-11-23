extends Node
## A picture from a spot (--from x,y,z --to x,y,z --out file.png) once the town has streamed in; prints the town's
## density and its tree count. Quits.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var args := OS.get_cmdline_user_args()
	var f := args[args.find("--from") + 1].split(","); var t := args[args.find("--to") + 1].split(",")
	var from := Vector3(float(f[0]), float(f[1]), float(f[2])); var to := Vector3(float(t[0]), float(t[1]), float(t[2]))
	game.get("player").global_position = from + Vector3(0, -1.5, 0)
	await get_tree().create_timer(45.0).timeout
	var cam := Camera3D.new(); get_tree().root.add_child(cam)
	cam.global_position = from; cam.look_at(to); cam.fov = 75; cam.current = true
	await get_tree().create_timer(4.0).timeout
	var town := get_tree().root.find_child("PonyvilleTown", true, false)
	print("VIEW density %s, trees %d" % [preload("res://world/towns/ponyville/town_density.gd").current(), town.find_children("tree_*", "StaticBody3D", true, false).size() if town else -1])
	get_viewport().get_texture().get_image().save_png(args[args.find("--out") + 1])
	get_tree().quit()
