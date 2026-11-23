extends SceneTree
## Quality control: what a background house draws where its real house's front door is (surface, material, UVs),
## beside the real door's own artwork.   ... --script res://tools/town_planner/build/qc/probe_bg_door.gd -- h
func _init() -> void:
	var key: String = OS.get_cmdline_user_args()[0]
	var real: Node = (load("res://world/towns/ponyville/house_%s.%s" % [key, "tscn" if key in "abcd" else "scn"]) as PackedScene).instantiate()
	var door: Node3D = real.find_child("FrontDoor", true, false)
	var art: MeshInstance3D = door.get_node("OriginalDoorArtwork")
	var box: AABB = door.transform * art.transform * art.mesh.get_aabb()
	print("BGDOOR real artwork box ", box, " surfaces ", art.mesh.get_surface_count())
	for s in art.mesh.get_surface_count():
		var arr := art.mesh.surface_get_arrays(s)
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var m: Material = art.get_active_material(s)
		var lo := Vector2(9, 9); var hi := Vector2(-9, -9)
		for u in uv: lo = lo.min(u); hi = hi.max(u)
		print("BGDOOR   real surface ", s, " verts ", (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), " uv ", lo, "..", hi, " format ", art.mesh.surface_get_format(s), " mat ", m, " tex ", (m as BaseMaterial3D).albedo_texture if m is BaseMaterial3D else null,
			" colors ", arr[Mesh.ARRAY_COLOR] != null, " vcol_albedo ", (m as BaseMaterial3D).vertex_color_use_as_albedo if m is BaseMaterial3D else null, " uv1_scale ", (m as BaseMaterial3D).uv1_scale if m is BaseMaterial3D else null)
	var bg: Node = (load("res://world/towns/ponyville/background/house_%s_bg.scn" % key) as PackedScene).instantiate()
	var ext: MeshInstance3D = bg.get_node("Exterior")
	var grown := box.grow(0.004)
	for s in ext.mesh.get_surface_count():
		var arr := ext.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n := 0; var lo := Vector2(9, 9); var hi := Vector2(-9, -9); var zlo := 9.0; var zhi := -9.0
		var count := idx.size() if idx.size() > 0 else v.size()
		for i in range(0, count, 3):
			var a := v[idx[i] if idx.size() > 0 else i]; var b := v[idx[i + 1] if idx.size() > 0 else i + 1]; var c := v[idx[i + 2] if idx.size() > 0 else i + 2]
			if grown.has_point(a) and grown.has_point(b) and grown.has_point(c):
				n += 1
				for k in 3:
					var j: int = idx[i + k] if idx.size() > 0 else i + k
					if uv.size() > j: lo = lo.min(uv[j]); hi = hi.max(uv[j])
					zlo = minf(zlo, v[j].z); zhi = maxf(zhi, v[j].z)
		var m: Material = ext.mesh.surface_get_material(s)
		if n > 0: print("BGDOOR   bg surface ", s, " tris in the door's box ", n, " z ", zlo, "..", zhi, " uv ", lo, "..", hi, " mat ", m.resource_name, " ", m, " tex ", (m as BaseMaterial3D).albedo_texture if m is BaseMaterial3D else null, " cull ", (m as BaseMaterial3D).cull_mode if m is BaseMaterial3D else -1)
	quit()
