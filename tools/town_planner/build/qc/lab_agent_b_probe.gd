extends SceneTree
## Quality control (play test 2026-11-16): the fountain's radial profile, for its water.
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/lab_agent_b_probe.gd -- fountain_01
## Prints each mesh of the node (name, surface materials, box in the node's space) and, in 0.1 m rings
## from the node's vertical axis, the lowest and highest vertex heights: the basin floor, rim and tiers.


func _local(n: Node, root: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != root:
		if at is Node3D: x = (at as Node3D).transform * x
		at = at.get_parent()
	return x


func _init() -> void:
	var root: Node = (load("res://world/props/ponyville/rnl_scenery.scn") as PackedScene).instantiate()
	for id: String in OS.get_cmdline_user_args():
		var node: Node3D = null
		for n: Node in root.find_children(id, "Node3D", true, false): node = n; break
		if node == null: print("PROBE ", id, " not found"); continue
		print("PROBE ", id, " path ", root.get_path_to(node), " parent ", node.get_parent().name)
		var lo: Dictionary = {}
		var hi: Dictionary = {}
		var seen: Dictionary = {}   # ring -> {height snapped to 5 cm: true}
		for m: Node in node.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null: continue
			var x := _local(mi, node)
			var mats := []
			for s: int in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				mats.append(mat.resource_name if mat != null else "-")
				var arrays := mi.mesh.surface_get_arrays(s)
				for v: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
					var p := x * v
					var ring := int(Vector2(p.x, p.z).length() * 10.0)
					lo[ring] = minf(float(lo.get(ring, 1e9)), p.y)
					hi[ring] = maxf(float(hi.get(ring, -1e9)), p.y)
					if not seen.has(ring): seen[ring] = {}
					(seen[ring] as Dictionary)[snappedf(p.y, 0.05)] = true
			print("   mesh ", root.get_path_to(mi), " box ", x * mi.mesh.get_aabb(), " mats ", mats)
		var rings := lo.keys()
		rings.sort()
		for ring: int in rings:
			var heights: Array = (seen[ring] as Dictionary).keys()
			heights.sort()
			print("   r %.1f  y %.2f .. %.2f  heights %s" % [ring / 10.0, lo[ring], hi[ring], str(heights)])
	quit()
