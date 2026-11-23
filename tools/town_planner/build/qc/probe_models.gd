extends SceneTree
## Quality control: the size of pieces of the baked town scenery, in their own space, and a bridge's walking profile.
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/probe_models.gd -- <node name>...
## For each node of world/props/ponyville/rnl_scenery.scn: its transform, its meshes' box in its own space (before
## its own scale), its extras ("<name>_foundation", "<name>_ramp"), its collision shapes. For a node whose name
## starts with "bridge": the highest collision surface in 24 slices along its length (local x), at the middle of
## its width and near each side.

func _local(n: Node, root: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != root:
		if at is Node3D: x = (at as Node3D).transform * x
		at = at.get_parent()
	return x


func _init() -> void:
	var root: Node = (load("res://world/props/ponyville/rnl_scenery.scn") as PackedScene).instantiate()
	for id in OS.get_cmdline_user_args():
		var node: Node3D = null
		for n in root.find_children(id, "Node3D", true, false): node = n; break
		if node == null: print("MODEL ", id, " not found"); continue
		var box := AABB(); var first := true; var tris := 0
		for m in node.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null: continue
			var b: AABB = _local(mi, node) * mi.mesh.get_aabb()
			box = b if first else box.merge(b); first = false
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var b2: AABB = (node as MeshInstance3D).mesh.get_aabb()
			box = b2 if first else box.merge(b2)
		print("MODEL ", id, " at ", node.position, " rot ", node.rotation, " scale ", node.scale, " file ", node.scene_file_path)
		print("   own box x ", snappedf(box.position.x, 0.01), "..", snappedf(box.end.x, 0.01), " y ", snappedf(box.position.y, 0.01), "..", snappedf(box.end.y, 0.01), " z ", snappedf(box.position.z, 0.01), "..", snappedf(box.end.z, 0.01))
		for sib in node.get_parent().get_children():
			if sib != node and str(sib.name).begins_with(id + "_") and sib is Node3D:
				var sb := AABB(); var f2 := true
				for m in ([sib] + sib.find_children("*", "MeshInstance3D", true, false)):
					if m is MeshInstance3D and (m as MeshInstance3D).mesh != null:
						var b3: AABB = (node.transform.affine_inverse() * (sib as Node3D).transform * _local(m, sib)) * (m as MeshInstance3D).mesh.get_aabb()
						sb = b3 if f2 else sb.merge(b3); f2 = false
				print("   extra ", sib.name, " (", sib.get_class(), ") in the model's space: x ", snappedf(sb.position.x, 0.01), "..", snappedf(sb.end.x, 0.01), " y ", snappedf(sb.position.y, 0.01), "..", snappedf(sb.end.y, 0.01), " z ", snappedf(sb.position.z, 0.01), "..", snappedf(sb.end.z, 0.01))
		var faces := PackedVector3Array()
		for c in node.find_children("*", "CollisionShape3D", true, false):
			var cs := c as CollisionShape3D
			var x := _local(cs, node)
			if cs.shape is ConcavePolygonShape3D:
				for v in (cs.shape as ConcavePolygonShape3D).get_faces(): faces.append(x * v)
				print("   collision ", cs.get_parent().name, "/", cs.name, " concave ", (cs.shape as ConcavePolygonShape3D).get_faces().size() / 3, " faces, layer ", (cs.get_parent() as CollisionObject3D).collision_layer if cs.get_parent() is CollisionObject3D else -1)
			elif cs.shape != null:
				print("   collision ", cs.get_parent().name, "/", cs.name, " ", cs.shape.get_class(), " at ", x.origin, " ", cs.shape.get("size") if cs.shape is BoxShape3D else "")
		if id.begins_with("bridge") and faces.size() > 0:
			var x0 := 1e9; var x1 := -1e9; var z0 := 1e9; var z1 := -1e9
			for v in faces: x0 = minf(x0, v.x); x1 = maxf(x1, v.x); z0 = minf(z0, v.z); z1 = maxf(z1, v.z)
			print("   collision reach x ", x0, "..", x1, " z ", z0, "..", z1)
			for lane in [0.0, 0.6]:
				var line := "   profile at z " + str(lane * z1) + ":"
				for k in 41:
					var px := lerpf(x0, x1, k / 24.0) if k < 25 else lerpf(x1 - 2.4, x1 - 0.01, (k - 25) / 15.0)
					var best := -1e9
					for i in range(0, faces.size() - 2, 3):
						var a := faces[i]; var b := faces[i + 1]; var c2 := faces[i + 2]
						var d := (b.z - c2.z) * (a.x - c2.x) + (c2.x - b.x) * (a.z - c2.z)
						if absf(d) < 1e-9: continue
						var pz: float = lane * z1
						var u := ((b.z - c2.z) * (px - c2.x) + (c2.x - b.x) * (pz - c2.z)) / d
						var w := ((c2.z - a.z) * (px - c2.x) + (a.x - c2.x) * (pz - c2.z)) / d
						if u < -0.001 or w < -0.001 or u + w > 1.001: continue
						best = maxf(best, u * a.y + w * b.y + (1.0 - u - w) * c2.y)
					line += " %.2f:%.2f" % [px, best]
				print(line)
	quit()
