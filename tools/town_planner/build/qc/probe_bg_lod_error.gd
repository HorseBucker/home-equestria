extends SceneTree
## Per surface of a background house's Exterior: full triangles, then each stored LOD's [error, triangles]
## (error in the model's own units; a house is about 1 unit tall, about 10 m in town). Prints LODERR lines.
func _init() -> void:
	for key in ["b", "c"]:
		var root: Node = (load("res://world/towns/ponyville/background/house_%s_bg.scn" % key) as PackedScene).instantiate()
		var mi := root.find_child("Exterior", true, false) as MeshInstance3D
		var stored: Array = mi.mesh.get("_surfaces")
		print("LODERR %s aabb %s" % [key, mi.mesh.get_aabb().size])
		for s in stored.size():
			var sd: Dictionary = stored[s]
			var wide := int(sd.get("vertex_count", 0)) > 65535
			var full: int = mi.mesh.surface_get_array_index_len(s) / 3
			var row := []
			var l: Array = sd.get("lods", [])
			for i in range(0, l.size(), 2): row.append("[%.4f, %d]" % [float(l[i]), (l[i + 1] as PackedByteArray).size() / (4 if wide else 2) / 3])
			var mat: Material = mi.mesh.surface_get_material(s)
			print("LODERR %s s%d %-40s full %6d  lods %s" % [key, s, (mat.resource_name if mat else "-").left(40), full, " ".join(row)])
		root.free()
	quit()
