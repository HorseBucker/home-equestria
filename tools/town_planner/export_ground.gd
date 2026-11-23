extends SceneTree
## Town planner: writes the ground around Ponyville as the game builds it (generated terrain plus
## the published sculpt and paint overlays) for the planner page.
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/export_ground.gd [-- --out res://dir/]
## Output, in res://tools/town_planner/data/: ground.json (bounds, step, counts), heights.f32
## (float32 rows, north to south = -z first... row = z index, column = x index) and control.u32
## (Terrain3D control words, the same layout).

const DEFAULT_OUT := "res://tools/town_planner/data/"
## `-- --out res://somewhere/` writes there instead (to check a build without touching the planner's data).
var OUT := DEFAULT_OUT
## World metres: x from, x to, z from, z to, and the sample step.
const BOUNDS := [-700.0, 1100.0, -900.0, 500.0]
const STEP := 2.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var flag := args.find("--out")
	if flag >= 0 and flag + 1 < args.size(): OUT = args[flag + 1].trim_suffix("/") + "/"
	var holder := Node3D.new()
	holder.name = "PlannerExport"
	root.add_child(holder)
	var script: Script = load("res://world/terrain/world_terrain.gd")
	var world: Node = script.call("ensure", holder)
	# Regions, sculpt and paint overlays settle over a few frames.
	for frame in 240:
		await process_frame
	var data: Object = world.terrain.data
	var columns := int((BOUNDS[1] - BOUNDS[0]) / STEP) + 1
	var rows := int((BOUNDS[3] - BOUNDS[2]) / STEP) + 1
	var heights := PackedFloat32Array()
	heights.resize(columns * rows)
	var controls := PackedInt32Array()
	controls.resize(columns * rows)
	var missing := 0
	for row in rows:
		var z: float = BOUNDS[2] + float(row) * STEP
		for column in columns:
			var at := Vector3(BOUNDS[0] + float(column) * STEP, 0.0, z)
			var height: float = data.get_height(at)
			if not is_finite(height): missing += 1
			heights[row * columns + column] = height
			controls[row * columns + column] = int(data.get_control(at)) & 0xFFFFFFFF
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := FileAccess.open(OUT + "heights.f32", FileAccess.WRITE)
	file.store_buffer(heights.to_byte_array())
	file.close()
	file = FileAccess.open(OUT + "control.u32", FileAccess.WRITE)
	file.store_buffer(controls.to_byte_array())
	file.close()
	file = FileAccess.open(OUT + "ground.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"bounds": BOUNDS, "step": STEP, "columns": columns, "rows": rows, "missing": missing,
		"regions": data.get_region_count() if data.has_method("get_region_count") else -1}, "\t"))
	file.close()
	print("PLANNER_GROUND %d x %d samples, %d without ground" % [columns, rows, missing])
	quit()
