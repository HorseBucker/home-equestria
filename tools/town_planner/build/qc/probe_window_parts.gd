extends SceneTree
## Per window of a house design: its glass and reveal meshes, their paths, house-space boxes and the glass's facing.
## Prints WP lines. godot --headless --path . --script res://tools/town_planner/build/qc/probe_window_parts.gd -- house_e.scn
func _xf(node: Node, house: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != house:
		if n is Node3D: xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

func _init() -> void:
	var file := OS.get_cmdline_user_args()[0]
	var house: Node = (load("res://world/towns/ponyville/" + file) as PackedScene).instantiate()
	for m: Node in house.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var n := str(mi.name)
		if mi.mesh == null or not ("Glass" in n or "Reveal" in n): continue
		var xf := _xf(mi, house)
		var box := xf * mi.mesh.get_aabb()
		var faces := mi.mesh.get_faces()
		var nrm := Vector3.ZERO
		for i in range(0, faces.size(), 3): nrm += (xf.basis * (faces[i + 1] - faces[i])).cross(xf.basis * (faces[i + 2] - faces[i]))
		print("WP %s tris %d box %s size %s normal %s" % [house.get_path_to(mi), faces.size() / 3, box.position.snapped(Vector3.ONE * 0.001), box.size.snapped(Vector3.ONE * 0.001), nrm.normalized().snapped(Vector3.ONE * 0.01)])
	quit()
