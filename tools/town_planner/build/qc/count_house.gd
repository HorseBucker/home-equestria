extends SceneTree
## Quality control: how heavy is one real home against one background house (nodes, meshes, surfaces, colliders, lights).
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/count_house.gd
func _init() -> void:
	for path: String in ["res://world/towns/ponyville/house_b.tscn", "res://world/towns/ponyville/house_c.tscn", "res://world/towns/ponyville/house_e.scn",
			"res://world/towns/ponyville/background/house_b_bg.scn", "res://world/towns/ponyville/background/house_e_bg.scn"]:
		var node: Node = (load(path) as PackedScene).instantiate()
		var all: Array[Node] = node.find_children("*", "", true, false)
		var meshes := 0; var surfaces := 0; var bodies := 0; var shapes := 0; var lights := 0; var tris := 0
		for n in all:
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				meshes += 1; var m: Mesh = (n as MeshInstance3D).mesh; surfaces += m.get_surface_count()
				for s in m.get_surface_count():
					var a := m.surface_get_arrays(s)
					if a[Mesh.ARRAY_INDEX] != null: tris += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
					elif a[Mesh.ARRAY_VERTEX] != null: tris += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			if n is CollisionObject3D: bodies += 1
			if n is CollisionShape3D: shapes += 1
			if n is Light3D: lights += 1
		print("COUNT %s: %d nodes, %d meshes, %d surfaces (draws), %d triangles, %d bodies, %d shapes, %d lights" % [path.get_file(), all.size(), meshes, surfaces, tris, bodies, shapes, lights])
		node.free()
	quit()
