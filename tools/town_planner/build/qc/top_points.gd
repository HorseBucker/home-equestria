extends SceneTree
## Quality control: a scene's direct children, and where its highest points are (for hanging things from it).
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/top_points.gd -- <scene>...
## Prints the children of the root (name, class, script), then the model's height in ten bands from the top: in
## each, the box (x, z) of the vertices found there.
func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var node: Node = (load(path) as PackedScene).instantiate()
		print("SCENE ", path, " root ", node.get_class(), " script ", node.get_script().resource_path if node.get_script() != null else "-")
		for c in node.get_children():
			print("   child ", c.name, " ", c.get_class(), " ", (c.get_script() as Script).resource_path if c.get_script() != null else "", " children ", c.get_child_count(), " ", (c as Node3D).transform if c is Node3D else "")
		var pts := PackedVector3Array()
		for n in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.visible: continue
			var x := Transform3D.IDENTITY; var at: Node = mi
			while at != node and at != null:
				if at is Node3D: x = (at as Node3D).transform * x
				at = at.get_parent()
			for s in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(s)
				if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null: continue
				for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]: pts.append(x * v)
		var top := -1e9; var low := 1e9
		for v in pts: top = maxf(top, v.y); low = minf(low, v.y)
		print("   height ", low, " .. ", top, " (", pts.size(), " vertices)")
		var band := (top - low) / 16.0
		for k in 8:
			var b := AABB(); var first := true; var n := 0
			for v in pts:
				if v.y <= top - band * k and v.y > top - band * (k + 1):
					b = AABB(v, Vector3.ZERO) if first else b.expand(v); first = false; n += 1
			print("   y %.3f..%.3f: %d vertices, x %.3f..%.3f z %.3f..%.3f" % [top - band * (k + 1), top - band * k, n, b.position.x, b.end.x, b.position.z, b.end.z])
		node.free()
	quit()
