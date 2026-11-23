extends SceneTree
## Build step 7 (third part): take the old railway out of the rebuilt map.
##   godot --xr-mode off --path <project> --script res://tools/town_planner/build/cut_track.gd -- <x0> <x1> <z0> <z1>
## (needs a window, not --headless: a MultiMesh's instances cannot be read without a renderer)
## (the plan's edge box; run on world/railway/track.scn from git)
## The game's track (world/railway/track.scn) is baked from the old route: its Ponyville station stood at
## (-80, -272) and its lines ran on through what are now rows of houses. Its builder is not in the source release,
## so the plan's own line cannot be laid yet. Until it can, the old rails, bed, platform and their collision are
## taken out inside the plan's edge, so nothing runs through a house: every triangle whose middle lies inside the
## box goes, from the drawn meshes and from the collision; a station piece standing inside the box is hidden.
## Outside the box the network is untouched (trains are switched off in rail_network.gd in any case).

func _world(n: Node, root: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != root:
		if at is Node3D: x = (at as Node3D).transform * x
		at = at.get_parent()
	return x


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		# without a renderer a MultiMesh gives back no instance positions: every sleeper would read as standing at
		# the origin, inside the box, and the whole network's sleepers would go
		print("TRACK needs a window: run without --headless"); quit(); return
	var a := OS.get_cmdline_user_args()
	var x0 := float(a[0]); var x1 := float(a[1]); var z0 := float(a[2]); var z1 := float(a[3])
	var path := "res://world/railway/track.scn"
	var compressed := FileAccess.get_file_as_bytes(path).slice(0, 4).get_string_from_ascii() == "RSCC"
	var track: Node3D = (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var cut_meshes := 0; var hidden := 0; var cut_tris := 0; var cut_shapes := 0; var cut_instances := 0
	for n in track.find_children("*", "", true, false):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var x := _world(mi, track)
			var box: AABB = x * mi.mesh.get_aabb()
			if box.end.x < x0 or box.position.x > x1 or box.end.z < z0 or box.position.z > z1: continue
			if not (mi.mesh is ArrayMesh):
				var c := box.get_center()
				if c.x >= x0 and c.x <= x1 and c.z >= z0 and c.z <= z1: mi.visible = false; hidden += 1
				continue
			var src := mi.mesh as ArrayMesh
			var out := ArrayMesh.new()
			var changed := false
			for s in src.get_surface_count():
				if src.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
					out.add_surface_from_arrays(src.surface_get_primitive_type(s), src.surface_get_arrays(s)); out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s)); continue
				var arrays := src.surface_get_arrays(s)
				var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				if index.is_empty():
					index.resize(v.size())
					for i in v.size(): index[i] = i
				var kept := PackedInt32Array()
				for i in range(0, index.size() - 2, 3):
					var c: Vector3 = x * ((v[index[i]] + v[index[i + 1]] + v[index[i + 2]]) / 3.0)
					if c.x >= x0 and c.x <= x1 and c.z >= z0 and c.z <= z1: cut_tris += 1; changed = true
					else: kept.append_array([index[i], index[i + 1], index[i + 2]])
				if kept.is_empty(): continue
				arrays[Mesh.ARRAY_INDEX] = kept
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
			if not changed: continue
			if out.get_surface_count() == 0:
				mi.visible = false; hidden += 1
			else:
				out.resource_name = src.resource_name
				mi.mesh = out; cut_meshes += 1
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			# sleepers, posts and the like: each instance standing inside the box goes
			var mmi := n as MultiMeshInstance3D
			var xm := _world(mmi, track)
			var old := mmi.multimesh
			var keep: Array[int] = []
			for i in old.instance_count:
				var c: Vector3 = xm * old.get_instance_transform(i).origin
				if not (c.x >= x0 and c.x <= x1 and c.z >= z0 and c.z <= z1): keep.append(i)
			if keep.size() == old.instance_count: continue
			cut_instances += old.instance_count - keep.size()
			if keep.is_empty():
				mmi.visible = false; hidden += 1
			else:
				var mm := MultiMesh.new()
				mm.transform_format = old.transform_format; mm.use_colors = old.use_colors; mm.use_custom_data = old.use_custom_data
				mm.mesh = old.mesh; mm.instance_count = keep.size()
				for k in keep.size():
					mm.set_instance_transform(k, old.get_instance_transform(keep[k]))
					if old.use_colors: mm.set_instance_color(k, old.get_instance_color(keep[k]))
					if old.use_custom_data: mm.set_instance_custom_data(k, old.get_instance_custom_data(keep[k]))
				mmi.multimesh = mm
		elif n is GeometryInstance3D and not (n is MeshInstance3D):
			# signs and other drawn things that are not meshes (the station's name board)
			var c := _world(n, track).origin
			if c.x >= x0 and c.x <= x1 and c.z >= z0 and c.z <= z1: (n as GeometryInstance3D).visible = false; hidden += 1
		elif n is CollisionShape3D and (n as CollisionShape3D).shape != null:
			var cs := n as CollisionShape3D
			var xs := _world(cs, track)
			if cs.shape is ConcavePolygonShape3D:
				var faces: PackedVector3Array = (cs.shape as ConcavePolygonShape3D).get_faces()
				var kept_faces := PackedVector3Array()
				var dropped := false
				for i in range(0, faces.size() - 2, 3):
					var c: Vector3 = xs * ((faces[i] + faces[i + 1] + faces[i + 2]) / 3.0)
					if c.x >= x0 and c.x <= x1 and c.z >= z0 and c.z <= z1: dropped = true
					else: kept_faces.append_array([faces[i], faces[i + 1], faces[i + 2]])
				if dropped:
					cut_shapes += 1
					if kept_faces.is_empty(): cs.disabled = true
					else:
						var shape := ConcavePolygonShape3D.new(); shape.backface_collision = (cs.shape as ConcavePolygonShape3D).backface_collision
						shape.set_faces(kept_faces); cs.shape = shape
			else:
				var c := xs.origin
				if c.x >= x0 and c.x <= x1 and c.z >= z0 and c.z <= z1: cs.disabled = true; cut_shapes += 1
	var packed := PackedScene.new()
	var err := packed.pack(track)
	if err == OK: err = ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS if compressed else 0)
	print("TRACK inside x %d..%d, z %d..%d: %d triangles cut from %d meshes, %d sleepers and the like taken out, %d pieces hidden, %d collision shapes cut; save %d" % [x0, x1, z0, z1, cut_tris, cut_meshes, cut_instances, hidden, cut_shapes, err])
	quit()
