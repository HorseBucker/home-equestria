extends SceneTree
## A house design's window-ish meshes (names with Window, Sash, Frame, Glass, Pane, Arch, Sill): name, triangles,
## material name and colour, and whether the background house build keeps it. Prints WIN lines.
## godot --headless --path . --script res://tools/town_planner/build/qc/probe_house_windows.gd -- house_f.scn
func _init() -> void:
	var file := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "house_f.scn"
	var house: Node = (load("res://world/towns/ponyville/" + file) as PackedScene).instantiate()
	var counts := {}
	for m: Node in house.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null: continue
		var n := str(mi.name)
		var key := n.rstrip("0123456789_")
		var mat := mi.get_active_material(0)
		var colour := (mat as BaseMaterial3D).albedo_color if mat is BaseMaterial3D else Color()
		var k := "%s | %s | %s | tex %s | visible %s" % [key, mat.resource_name if mat else "-", colour, (mat as BaseMaterial3D).albedo_texture != null if mat is BaseMaterial3D else "?", mi.visible]
		counts[k] = int(counts.get(k, 0)) + 1
	for k: String in counts:
		var low := k.to_lower()
		if "window" in low or "sash" in low or "frame" in low or "glass" in low or "pane" in low or "arch" in low or "sill" in low or "reveal" in low:
			print("WIN %dx %s" % [counts[k], k])
	quit()
