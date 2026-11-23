extends SceneTree
## Pictures of the bare ground and water (no town, no props): the terrain and water the game loads,
## under a plain sky, from a few viewpoints over the plan. Needs a window (not --headless):
##   godot --xr-mode off --path <project> --script res://tools/town_planner/build/capture_ground.gd [-- [--town] view names]
## Writes res://tools/town_planner/build/out/captures/*.png, and prints the water's own checks.

const OUT := "res://tools/town_planner/build/out/captures"
## name, eye (x, height above ground, z), look at (x, height above ground, z) - for the plan at 1.5x (V3)
const VIEWS := [
	["overview_from_south", Vector3(131, 260, 456), Vector3(131, 0, -234)],
	["town_from_above", Vector3(56, 90, 20), Vector3(131, 0, -190)],
	["sparkling_lake", Vector3(-19, 30, -264), Vector3(71, 0, -460)],
	["town_hall_river", Vector3(191, 2, -152), Vector3(311, 0, -114)],
	["fluttershy_hill", Vector3(461, 18, 200), Vector3(578, 0, 112)],
	["west_countryside", Vector3(-199, 25, -70), Vector3(-424, 0, -280)],
	["tranquility_lake", Vector3(-49, 6, 50), Vector3(-4, 0, -12)],
	["east_meadow_hills", Vector3(341, 30, -70), Vector3(596, 0, -384)],
	["river_from_the_north", Vector3(461, 25, -534), Vector3(644, 0, -767)],
	["west_river_edge", Vector3(-379, 15, -114), Vector3(-484, 0, -96)],
	["east_river_closeup", Vector3(266, 10, -114), Vector3(288, 0, -242)],
	["probe", Vector3(326, 8, -190), Vector3(353, 0, -272)],
	["fountain_ground", Vector3(126, 1.7, -163), Vector3(137, 0, -173)],
	["plaza_ground", Vector3(110, 2.5, -140), Vector3(200, 0, -200)],
	["town_ground_above", Vector3(60, 40, -100), Vector3(110, 0, -230)],
	["west_streets", Vector3(-40, 1.8, -210), Vector3(40, 0, -250)],
	["lake_top", Vector3(60, 70, -400), Vector3(60.5, 0, -440)],
	["street_west", Vector3(-20, 1.7, -196), Vector3(30, 1.5, -240)],
	["street_north", Vector3(195, 1.7, -330), Vector3(200, 1.5, -260)],
	["plaza_hall", Vector3(110, 1.7, -175), Vector3(169, 3, -153)],
	["town_air", Vector3(20, 60, -80), Vector3(120, 0, -230)],
	["marigold_townhall", Vector3(305, 28, -55), Vector3(160, 4, -170)],
	["marigold_low", Vector3(300, 12, -62), Vector3(165, 6, -160)],
	["library_balloon", Vector3(-40, 14, -200), Vector3(-80, 3, -250)],
]

var terrain: Node
var water: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var holder := Node3D.new(); holder.name = "GroundCapture"; root.add_child(holder)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new(); var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85); sky_mat.sky_horizon_color = Color(0.75, 0.85, 0.95)
	sky.sky_material = sky_mat; e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true; e.fog_density = 0.0006; e.fog_light_color = Color(0.8, 0.87, 0.95)
	env.environment = e; holder.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -35, 0); sun.light_energy = 1.2
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 600.0; holder.add_child(sun)
	var cam := Camera3D.new(); cam.far = 4000.0; cam.fov = 60.0; holder.add_child(cam); cam.make_current()
	cam.position = Vector3(110, 100, 100)
	terrain = load("res://world/terrain/world_terrain.gd").call("ensure", holder)
	for f in 30: await process_frame
	if terrain.terrain.has_method("set_camera"): terrain.terrain.set_camera(cam)
	for f in 200: await process_frame
	water = load("res://world/water/world_water.gd").call("ensure", holder)
	for f in 20: await process_frame
	var only := OS.get_cmdline_user_args()
	if only.has("--town"):
		# the town scene too (houses, landmarks, props), without the game around it
		only.erase("--town")
		var town: Node = (load("res://world/towns/ponyville/town.tscn") as PackedScene).instantiate()
		holder.add_child(town)
		for f in 120: await process_frame
	_check_water()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for view in VIEWS:
		if not only.is_empty() and not only.has(view[0]): continue
		var eye: Vector3 = view[1]; var at: Vector3 = view[2]
		eye.y += _ground(eye.x, eye.z); at.y += _ground(at.x, at.z)
		cam.position = eye
		cam.look_at(at)
		if terrain.has_method("focus"): terrain.focus(eye)
		for f in 90: await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT + "/" + view[0] + ".png"))
		print("CAPTURE ", view[0])
	quit()


func _ground(x: float, z: float) -> float:
	var h: float = terrain.terrain.data.get_height(Vector3(x, 0, z))
	return h if is_finite(h) else 0.0


## The water's surface against the ground under it: wet cells must stand over lower ground.
func _check_water() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/water/ponyville_canals.json"))
	var w := int(doc.width); var d := int(doc.depth)
	var heights := Marshalls.base64_to_raw(String(doc.heights)).to_float32_array()
	var wet := 0; var deep_ok := 0; var shallowest := 99.0; var deepest := 0.0
	for r in range(0, d, 2):
		for c in range(0, w, 2):
			var y := heights[r * w + c]
			if is_nan(y): continue
			var g := _ground(float(doc.origin[0]) + c, float(doc.origin[1]) + r)
			wet += 1
			var depth := y - g
			if depth > 0.05:
				deep_ok += 1; shallowest = minf(shallowest, depth); deepest = maxf(deepest, depth)
	print("WATER canal samples %d, %d over lower ground (the rest are the 2 m reaching under the banks); depth %.2f..%.2f m" % [wet, deep_ok, shallowest, deepest])
	for child in water.get_children():
		if child is MeshInstance3D: print("WATER mesh ", child.name)
	print("WATER river audit ", water.get("river_audit"))
