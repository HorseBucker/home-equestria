extends SceneTree
## Agent G probe (play test 2026-11-16): materials of kit kinds. Headless, --script.

func _init() -> void:
	for kind: String in ["crop_row", "flowering_shrub", "lupin_clump", "sunflower_clump"]:
		var scene := (load("res://world/props/ponyville_kit/%s.scn" % kind) as PackedScene).instantiate()
		var meshes: Array = scene.find_children("*", "MeshInstance3D", true, false)
		if scene is MeshInstance3D: meshes.push_front(scene)
		for m: MeshInstance3D in meshes:
			print(kind, " mesh ", m.name, " aabb ", m.mesh.get_aabb(), " surfaces ", m.mesh.get_surface_count())
			for s: int in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(s)
				if mat is BaseMaterial3D:
					var b := mat as BaseMaterial3D
					print("  ", s, " ", mat.get_class(), " col ", b.albedo_color, " tex ", b.albedo_texture != null, " normal ", b.normal_enabled, " transp ", b.transparency, " rough ", b.roughness, " cull ", b.cull_mode, " vcol ", b.vertex_color_use_as_albedo)
				else:
					print("  ", s, " ", mat)
		scene.free()
	quit()
