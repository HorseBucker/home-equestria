extends SceneTree
## Quality control: every mesh of a real house that has triangles inside its front door's box.
func _local(n: Node, root: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != root:
		if at is Node3D: x = (at as Node3D).transform * x
		at = at.get_parent()
	return x
func _init() -> void:
	var key: String = OS.get_cmdline_user_args()[0]
	var real: Node = (load("res://world/towns/ponyville/house_%s.%s" % [key, "tscn" if key in "abcd" else "scn"]) as PackedScene).instantiate()
	var door: Node3D = real.find_child("FrontDoor", true, false)
	var art: MeshInstance3D = door.get_node("OriginalDoorArtwork")
	var box: AABB = (door.transform * art.transform * art.mesh.get_aabb()).grow(0.004)
	for m in real.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null: continue
		var x := _local(mi, real)
		var f := mi.mesh.get_faces()
		var n := 0; var zlo := 9.0; var zhi := -9.0
		for i in range(0, f.size(), 3):
			var a := x * f[i]; var b := x * f[i + 1]; var c := x * f[i + 2]
			if box.has_point(a) and box.has_point(b) and box.has_point(c):
				n += 1; zlo = minf(zlo, minf(a.z, minf(b.z, c.z))); zhi = maxf(zhi, maxf(a.z, maxf(b.z, c.z)))
		if n > 0: print("DOORBOX ", key, " ", real.get_path_to(mi), " tris ", n, " z ", snappedf(zlo, 0.0001), "..", snappedf(zhi, 0.0001), " visible ", mi.is_visible_in_tree() or mi.visible, " range ", mi.visibility_range_begin, "..", mi.visibility_range_end, " script ", mi.get_script())
	quit()
