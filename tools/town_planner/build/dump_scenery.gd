extends SceneTree
## Build step 5 (first): where every piece of the baked town scenery really stands (its node in
## world/props/ponyville/rnl_scenery.scn, with the town scene's own pins from rnl_scenery_defaults.tscn applied).
## The scenery list (rnl_scenery.json) keeps a building's lowest ground, not its floor, and nothing of a sky
## building's height; the nodes hold the truth. Writes build/out/scenery_nodes.json: id -> [x, y, z, yaw].
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/dump_scenery.gd
## Run it on the scenes from git, before apply_scenery.gd.
func _init() -> void:
	var root: Node = (load("res://world/props/ponyville/rnl_scenery_defaults.tscn") as PackedScene).instantiate()
	var out := {}
	for n in root.find_children("*", "Node3D", true, false):
		var node := n as Node3D
		var id := str(node.name)
		if out.has(id) or node.get_child_count() == 0 and not (node is MeshInstance3D): continue
		var x := Transform3D.IDENTITY; var at: Node = node
		while at != root and at != null:
			if at is Node3D: x = (at as Node3D).transform * x
			at = at.get_parent()
		out[id] = [x.origin.x, x.origin.y, x.origin.z, node.rotation.y]
	var f := FileAccess.open("res://tools/town_planner/build/out/scenery_nodes.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out)); f.close()
	print("SCENERY NODES ", out.size())
	quit()
