extends SceneTree
## Build steps 1 and 3, the "Very Low" quality copy of the terrain: the baked 512-texel, 2 m regions in
## world/terrain/data_half carry the sculpt overlays baked in, so the plan's ground is written into them
## too (every 2 m sample inside the plan's box), from the 1 m grid apply_ground.py exported.
## godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/apply_ground_half.gd

const OUT := "res://tools/town_planner/build/out"
const HALF := "res://world/terrain/data_half"
const REGION := 1024


func _init() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT + "/grid.json"))
	var nx := int(meta.columns); var nz := int(meta.rows)
	var x0 := int(meta.origin[0]); var z0 := int(meta.origin[1])
	var ground := FileAccess.get_file_as_bytes(OUT + "/ground.f32").to_float32_array()
	var paint_bytes := FileAccess.get_file_as_bytes(OUT + "/control.u32") if FileAccess.file_exists(OUT + "/control.u32") else PackedByteArray()
	var paint := PackedInt64Array()
	for i in range(0, paint_bytes.size(), 4): paint.append(paint_bytes.decode_u32(i))
	if ground.size() != nx * nz:
		push_error("ground grid size mismatch"); quit(1); return
	for lz in range(floori(float(z0) / REGION), floori(float(z0 + nz - 1) / REGION) + 1):
		for lx in range(floori(float(x0) / REGION), floori(float(x0 + nx - 1) / REGION) + 1):
			var path := HALF + "/terrain3d" + _part(lx) + _part(lz) + ".res"
			if not ResourceLoader.exists(path):
				print("no half-res region ", path); continue
			var region: Resource = load(path)
			var size: int = region.get_region_size()
			var step := REGION / size
			var img: Image = region.get_height_map()
			var count := 0
			for y in size:
				var wz := lz * REGION + y * step
				if wz < z0 or wz >= z0 + nz: continue
				for x in size:
					var wx := lx * REGION + x * step
					if wx < x0 or wx >= x0 + nx: continue
					img.set_pixel(x, y, Color(ground[(wz - z0) * nx + (wx - x0)], 0, 0))
					count += 1
			# the paint too, when apply_paint.py has run (control words, the same 2 m samples)
			if paint.size() == nx * nz:
				var cimg: Image = region.get_control_map()
				var bytes := cimg.get_data()
				var painted := 0
				for y in size:
					var wz := lz * REGION + y * step
					if wz < z0 or wz >= z0 + nz: continue
					for x in size:
						var wx := lx * REGION + x * step
						if wx < x0 or wx >= x0 + nx: continue
						bytes.encode_u32((y * size + x) * 4, paint[(wz - z0) * nx + (wx - x0)])
						painted += 1
				region.set_control_map(Image.create_from_data(size, size, false, cimg.get_format(), bytes))
				print("  paint: ", painted, " samples")
			region.set_location(Vector2i(lx, lz))   # files carry no location (Terrain3D reads it from the name); save needs it
			region.set_height_map(img)
			region.calc_height_range()
			region.set_modified(true)   # Terrain3D skips saving a region it thinks is unchanged
			var err: int = region.save(path)
			print(path, ": ", count, " samples written, height range ", region.get_height_range(), ", save ", err)
	quit()


## terrain3d_00-01.res is (0, -1): "_" before a positive part, "-" before a negative one.
func _part(v: int) -> String:
	return ("_%02d" % v) if v >= 0 else ("-%02d" % -v)
