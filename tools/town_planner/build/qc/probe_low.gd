extends SceneTree
## Quality control: where a scenery building's low parts stand out from its walls (steps, porches).
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/probe_low.gd -- <node> <top y>
## Prints, in the node's own space, a map of the vertices below <top y> (default 1.2 m): for each 1 m square of
## x and z, the highest such vertex (in tenths of a metre; '.' none).

func _local(n: Node, root: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != root:
		if at is Node3D: x = (at as Node3D).transform * x
		at = at.get_parent()
	return x

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var root: Node = (load("res://world/props/ponyville/rnl_scenery.scn") as PackedScene).instantiate()
	var node: Node = root.find_child(args[0], true, false)
	var top := float(args[1]) if args.size() > 1 else 1.2
	var cells := {}
	var lo := Vector2i(99, 99); var hi := Vector2i(-99, -99)
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null: continue
		var x := _local(mi, node)
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := x * v
				if p.y > top: continue
				var c := Vector2i(floori(p.x), floori(p.z))
				cells[c] = maxf(cells.get(c, -9.0), p.y)
				lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y)); hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	print("LOW ", args[0], " x ", lo.x, "..", hi.x, " (columns), z ", lo.y, "..", hi.y, " (rows)")
	for z in range(lo.y, hi.y + 1):
		var line := "LOW z %3d: " % z
		for xx in range(lo.x, hi.x + 1):
			line += ("%3d" % roundi(float(cells[Vector2i(xx, z)]) * 10.0)) if cells.has(Vector2i(xx, z)) else "  ."
		print(line)
	quit()
