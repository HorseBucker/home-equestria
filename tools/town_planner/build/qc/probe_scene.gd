extends SceneTree
## Quality control: what a building scene is made of, in its own space (before the scale it is placed with).
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/probe_scene.gd -- <res:// scene>
## Every mesh's box and materials, every collision shape's box, the house interior's door numbers, and the highest
## collision surface along the line from inside the door out past the spot a pony stands at to go in.

func _local(n: Node, root: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != root:
		if at is Node3D: x = (at as Node3D).transform * x
		at = at.get_parent()
	return x

func _box(b: AABB) -> String:
	return "x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f" % [b.position.x, b.end.x, b.position.y, b.end.y, b.position.z, b.end.z]

func _init() -> void:
	var root: Node = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
	var faces := PackedVector3Array()
	for n in [root] + root.find_children("*", "", true, false):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh: Mesh = (n as MeshInstance3D).mesh
			var mats := []
			for s in mesh.get_surface_count():
				var m: Material = (n as MeshInstance3D).get_active_material(s)
				mats.append(m.resource_name if m != null and m.resource_name != "" else (m.get_class() if m != null else "none"))
			print("MESH ", root.get_path_to(n), " ", _box(_local(n, root) * mesh.get_aabb()), " ", mats)
		elif n is CollisionShape3D and (n as CollisionShape3D).shape != null:
			var cs := n as CollisionShape3D
			var x := _local(cs, root)
			if cs.shape is ConcavePolygonShape3D:
				var b := AABB(); var first := true
				for v in (cs.shape as ConcavePolygonShape3D).get_faces():
					faces.append(x * v)
					b = AABB(x * v, Vector3.ZERO) if first else b.expand(x * v); first = false
				print("COLL ", root.get_path_to(n), " concave ", _box(b))
			else:
				print("COLL ", root.get_path_to(n), " ", cs.shape.get_class(), " at ", x.origin, " ", cs.shape.get("size"))
		elif n.get("approach") != null:
			print("HOUSE ", root.get_path_to(n), " at ", _local(n, root).origin, " basis scale ", _local(n, root).basis.get_scale(), " approach ", n.get("approach"), " doorway ", n.get("doorway"), " floor_y ", n.get("floor_y"), " door_width ", n.get("door_width"))
			var x2 := _local(n, root)
			var a: Vector3 = x2 * (n.get("approach") as Vector3)
			var d: Vector3 = x2 * Vector3((n.get("doorway") as Vector3).x, float(n.get("floor_y")), (n.get("doorway") as Vector3).z)
			print("   in the scene's space: approach ", a, " doorway ", d)
			root.set_meta("probe_line", [d, a])
	if root.has_meta("probe_line") and faces.size() > 0:
		var line: Array = root.get_meta("probe_line")
		var d2: Vector3 = line[0]; var a2: Vector3 = line[1]
		var out := "PROFILE (t along doorway->approach, top collision y):"
		for k in range(-4, 33):
			var t := k / 20.0
			var p := d2.lerp(a2, t)
			var best := -1e9
			for i in range(0, faces.size(), 3):
				var hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, 50, p.z), Vector3.DOWN, faces[i], faces[i + 1], faces[i + 2])
				if hit != null and (hit as Vector3).y < d2.y + 0.08 and (hit as Vector3).y > best: best = (hit as Vector3).y
			out += " %.2f:%.3f" % [t, best]
		print(out)
	quit()
