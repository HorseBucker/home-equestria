extends SceneTree
## Quality control: each mesh surface of a scene (material name, vertex height range in the scene's frame).
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/list_surfaces.gd -- <scene>
func _init() -> void:
	var node: Node = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.mesh is ArrayMesh: continue
		var x := Transform3D.IDENTITY; var at: Node = mi
		while at != node and at != null:
			if at is Node3D: x = (at as Node3D).transform * x
			at = at.get_parent()
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var lo := INF; var hi := -INF
			for v in verts:
				var w := x * v
				lo = minf(lo, w.y); hi = maxf(hi, w.y)
			var mat := mi.get_active_material(s)
			var hist := {}
			for v in verts:
				var w2 := x * v
				if w2.y < 1.2: hist[snappedf(w2.y, 0.05)] = hist.get(snappedf(w2.y, 0.05), 0) + 1
			var ks := hist.keys(); ks.sort()
			var line := ""
			for k in ks: if hist[k] >= 6: line += " %.2f:%d" % [k, hist[k]]
			print("HIST ", mi.name, " ", s, line)
			print("SURF ", mi.name, " ", s, " ", mat.resource_name if mat else "-", " ", (mat.resource_path.get_file() if mat else ""), " y %.3f..%.3f n %d" % [lo, hi, verts.size()])
	quit()
