extends Node
## Lists the streamed biome foliage near a spot (--at x,z, --reach m): each plant's model and ground position.
## Prints FOL lines; quits. (2026-11-21: the two bushes on the picnic hill in the way of the view of town)
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
	var at := args[args.find("--at") + 1].split(",") if "--at" in args else PackedStringArray(["0", "0"])
	var reach := float(args[args.find("--reach") + 1]) if "--reach" in args else 15.0
	var spot := Vector3(float(at[0]), 0, float(at[1]))
	game.get("player").global_position = spot + Vector3(0, 20, 0)
	await get_tree().create_timer(40.0).timeout
	var foliage := WorldTerrain.instance.get_node_or_null("BiomeFoliage")
	for node: Node in foliage.find_children("*", "", true, false):
		if node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var mm := (node as MultiMeshInstance3D).multimesh
			for k in mm.instance_count:
				var p: Vector3 = (node as Node3D).global_transform * mm.get_instance_transform(k).origin
				if Vector2(p.x - spot.x, p.z - spot.z).length() <= reach:
					print("FOL mm %s %s (%.2f, %.2f, %.2f) scale %.2f" % [node.get_path(), str(mm.mesh.get_aabb().size) if mm.mesh else "?", p.x, p.y, p.z, mm.get_instance_transform(k).basis.get_scale().x])
		elif node is Node3D and not node is MultiMeshInstance3D:
			var p2 := (node as Node3D).global_position
			if node.get_parent() != foliage and Vector2(p2.x - spot.x, p2.z - spot.z).length() <= reach and (node is MeshInstance3D or node.get_child_count() > 0 and node.get_parent().get_parent() == foliage):
				print("FOL node %s %s (%.2f, %.2f, %.2f)" % [node.name, node.scene_file_path.get_file(), p2.x, p2.y, p2.z])
	# --heights x,z;x,z: the terrain's height at each
	if "--heights" in args:
		for pair in args[args.find("--heights") + 1].split(";"):
			var xz := pair.split(",")
			var p3 := Vector3(float(xz[0]), 0, float(xz[1]))
			print("FOL height at %s: %.3f" % [p3, WorldTerrain.instance.height_at(p3)])
	get_tree().quit()
