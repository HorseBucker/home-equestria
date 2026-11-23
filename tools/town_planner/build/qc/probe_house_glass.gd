extends SceneTree
## Every mesh named like glass in a house design: its path, triangles, size and visibility. Prints GLASS lines.
func _init() -> void:
	var file := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "house_g.scn"
	var house: Node = (load("res://world/towns/ponyville/" + file) as PackedScene).instantiate()
	for m: Node in house.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not "Glass" in str(mi.name): continue
		var tris := 0
		for s in mi.mesh.get_surface_count(): tris += maxi(mi.mesh.surface_get_array_index_len(s), mi.mesh.surface_get_array_len(s)) / 3
		print("GLASS %s: %d tris, aabb %s, visible %s" % [house.get_path_to(mi), tris, mi.mesh.get_aabb().size, mi.visible])
	quit()
