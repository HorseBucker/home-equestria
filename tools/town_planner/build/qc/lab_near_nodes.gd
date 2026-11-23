extends Node
## Lists the scene's 3D nodes near a spot (--at x,z, --reach m) with their positions, and each FrontDoor's; for
## finding what stands by a doorstep. Prints NEAR lines; quits.
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
	var at := args[args.find("--at") + 1].split(",")
	var reach := float(args[args.find("--reach") + 1]) if "--reach" in args else 5.0
	var spot := Vector3(float(at[0]), 0, float(at[1]))
	game.get("player").global_position = spot + Vector3(0, 2, 6)
	await get_tree().create_timer(60.0).timeout
	for node: Node in get_tree().root.find_children("*", "Node3D", true, false):
		var p := (node as Node3D).global_position
		if Vector2(p.x - spot.x, p.z - spot.z).length() > reach: continue
		var parent := node.get_parent()
		# whole pieces only: a node whose parent stands elsewhere, or a door
		if str(node.name) == "FrontDoor" or (parent is Node3D and (parent as Node3D).global_position.distance_to(p) > 0.05) or not parent is Node3D:
			var box := ""
			if node is VisualInstance3D: box = str((node as VisualInstance3D).global_transform * (node as VisualInstance3D).get_aabb())
			print("NEAR %s (%.2f, %.2f, %.2f) %s %s" % [node.get_path(), p.x, p.y, p.z, node.scene_file_path.get_file(), box])
	get_tree().quit()
