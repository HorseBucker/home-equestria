extends SceneTree
## Quality control: the front door parts of a house scene (visibility, transform, material, triangles).
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/probe_door.gd -- <res:// scene>...
func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var house: Node = (load(path) as PackedScene).instantiate()
		for n in house.find_children("*", "", true, false):
			var name := str(house.get_path_to(n))
			if not ("FrontDoor" in name or "DoorReveal" in name) or "Balcony" in name: continue
			var line := "DOOR %s %s [%s]" % [path.get_file(), name, n.get_class()]
			if n is Node3D: line += " visible %s pos %s rot %s scale %s" % [(n as Node3D).visible, (n as Node3D).position, (n as Node3D).rotation, (n as Node3D).scale]
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var mi := n as MeshInstance3D
				var m: Material = mi.get_active_material(0)
				line += " tris %d range %.0f..%.0f mat %s" % [mi.mesh.get_faces().size() / 3, mi.visibility_range_begin, mi.visibility_range_end, m.get_class() if m != null else "none"]
				if m is BaseMaterial3D: line += " transparency %d cull %d albedo %s" % [(m as BaseMaterial3D).transparency, (m as BaseMaterial3D).cull_mode, (m as BaseMaterial3D).albedo_color]
				if m is ShaderMaterial: line += " shader " + str((m as ShaderMaterial).shader.resource_path)
			if n.get_script() != null: line += " script " + str((n.get_script() as Script).resource_path)
			print(line)
		house.free()
	quit()
