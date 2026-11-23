extends SceneTree
## Quality control: the mesh parts of a scene, by name with trailing numbers dropped: count, triangles, world box.
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/list_parts.gd -- <scene>
func _init() -> void:
	var node: Node = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
	var groups := {}
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null: continue
		var key := str(mi.name).rstrip("0123456789_ ")
		var x := Transform3D.IDENTITY; var at: Node = mi
		while at != node and at != null:
			if at is Node3D: x = (at as Node3D).transform * x
			at = at.get_parent()
		var b: AABB = x * mi.mesh.get_aabb()
		var g: Array = groups.get(key, [0, 0, b, str(node.get_path_to(mi.get_parent()))])
		g[0] += 1
		if mi.mesh is ArrayMesh:
			for s in mi.mesh.get_surface_count(): g[1] += maxi((mi.mesh as ArrayMesh).surface_get_array_index_len(s), (mi.mesh as ArrayMesh).surface_get_array_len(s)) / 3
		else: g[1] += 2
		g[2] = (g[2] as AABB).merge(b); groups[key] = g
	for key: String in groups:
		var g: Array = groups[key]; var b: AABB = g[2]
		print("PART ", key, " x", g[0], " ", g[1], " tris  x ", snappedf(b.position.x, 0.01), "..", snappedf(b.end.x, 0.01), " y ", snappedf(b.position.y, 0.01), "..", snappedf(b.end.y, 0.01), " z ", snappedf(b.position.z, 0.01), "..", snappedf(b.end.z, 0.01), "  under ", g[3])
	quit()
