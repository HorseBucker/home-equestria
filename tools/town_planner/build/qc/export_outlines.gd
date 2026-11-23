extends SceneTree
## Quality control: every triangle of each house design's outside, seen from above, for exact roof-against-roof
## checks (tools/town_planner/roof_check.py). Reads the background houses (the outside only, already merged).
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/export_outlines.gd
## Writes res://tools/town_planner/build/out/outlines/<design>.f32: x0 z0 x1 z1 x2 z2 per triangle, model units.
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/town_planner/build/out/outlines"))
	for design: String in ["a", "b", "c", "d", "e", "f", "g", "h"]:
		var node: Node3D = (load("res://world/towns/ponyville/background/house_%s_bg.scn" % design) as PackedScene).instantiate()
		var out := PackedFloat32Array()
		for n in node.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var x := Transform3D.IDENTITY
			var at: Node = mi
			while at != node and at != null:
				if at is Node3D: x = (at as Node3D).transform * x
				at = at.get_parent()
			for s in mi.mesh.get_surface_count():
				var a := mi.mesh.surface_get_arrays(s)
				var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var idx: Variant = a[Mesh.ARRAY_INDEX]
				var count: int = (idx as PackedInt32Array).size() if idx != null else v.size()
				for i in count:
					var p: Vector3 = x * v[(idx as PackedInt32Array)[i] if idx != null else i]
					out.append(p.x); out.append(p.z)
		var f := FileAccess.open("res://tools/town_planner/build/out/outlines/%s.f32" % design, FileAccess.WRITE)
		f.store_buffer(out.to_byte_array()); f.close()
		print("OUTLINE %s: %d triangles" % [design, out.size() / 6])
		node.free()
	quit()
