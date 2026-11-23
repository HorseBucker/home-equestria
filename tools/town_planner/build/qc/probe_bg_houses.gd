extends SceneTree
## Each background house scene's meshes: triangles at full detail and at each generated LOD, visibility ranges and
## lod_bias. Prints BGH lines. godot --headless --path . --script res://tools/town_planner/build/qc/probe_bg_houses.gd
func _init() -> void:
	for key in ["a", "b", "c", "e", "f", "g", "h"]:
		var root: Node = (load("res://world/towns/ponyville/background/house_%s_bg.scn" % key) as PackedScene).instantiate()
		for m: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null: continue
			var tris := 0; var lods := []
			var stored: Variant = mi.mesh.get("_surfaces")
			for s in mi.mesh.get_surface_count():
				tris += maxi(mi.mesh.surface_get_array_index_len(s), mi.mesh.surface_get_array_len(s)) / 3
			if stored is Array:
				var per: Dictionary = {}
				for sd: Variant in stored:
					var l: Array = (sd as Dictionary).get("lods", [])
					for i in range(0, l.size(), 2):
						var idx: PackedByteArray = l[i + 1]
						per[i / 2] = int(per.get(i / 2, 0)) + idx.size() / (4 if int((sd as Dictionary).get("vertex_count", 70000)) > 65535 else 2) / 3
				lods = per.values()
			print("BGH %s %s: %d tris, %d surfaces, LOD tris %s, range %.0f-%.0f, lod_bias %.2f, shadow %d" % [key, root.get_path_to(mi), tris, mi.mesh.get_surface_count(), lods,
				mi.visibility_range_begin, mi.visibility_range_end, mi.lod_bias, mi.cast_shadow])
		root.free()
	quit()
