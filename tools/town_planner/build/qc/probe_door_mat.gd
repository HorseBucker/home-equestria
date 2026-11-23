extends SceneTree
## Quality control: how a real house's door artwork material differs from its walls' material.
func _init() -> void:
	var key: String = OS.get_cmdline_user_args()[0]
	var real: Node = (load("res://world/towns/ponyville/house_%s.%s" % [key, "tscn" if key in "abcd" else "scn"]) as PackedScene).instantiate()
	var art: MeshInstance3D = real.find_child("FrontDoor", true, false).get_node("OriginalDoorArtwork")
	var ext: MeshInstance3D = real.find_child("Exterior", true, false)
	var a: Material = art.get_active_material(0)
	print("DOORMAT art mat ", a, " name ", a.resource_name, " override ", art.get_surface_override_material(0), " material_override ", art.material_override, " mesh mat ", art.mesh.surface_get_material(0))
	for s in ext.mesh.get_surface_count():
		var b: Material = ext.get_active_material(s)
		print("DOORMAT ext surface ", s, " mat ", b, " name ", b.resource_name, " same object ", a == b)
		if b.resource_name == a.resource_name:
			for p in a.get_property_list():
				if not (int(p.usage) & PROPERTY_USAGE_STORAGE): continue
				if a.get(p.name) != b.get(p.name): print("DOORMAT   differs: ", p.name, " art ", a.get(p.name), " ext ", b.get(p.name))
	var t: Texture2D = (a as BaseMaterial3D).albedo_texture
	print("DOORMAT art tex ", t, " size ", t.get_size() if t != null else null, " path ", t.resource_path if t != null else "")
	quit()
