extends Node
## The title screen's pictures of the remade Ponyville (2026-11-19 play test: new shots like HorseBucker's screenshots, in
## summer, each at its best time of day, no HUD, 1440p, good at any window size). For each view:
## - a flat picture, 3440x1440 (21:9; the title crops it to the window's shape, so any screen is covered at full
##   height), drawn at twice that and scaled down: world/ui/baked_vistas/<view>.picture, JPEG bytes (baked_vistas.gd shows it on
##   desktop);
## - the 360-degree cubemap the title's sky uses (VR, and desktop without the picture): 2048 a face, DXT1 with
##   mipmaps like the game's own, world/ui/baked_vistas/<view>.res. Its faces' orientation is checked here by
##   drawing the new sky and comparing it with the world itself in three directions (VISTA lines).
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/capture_vistas.gd [--views a,b] [--quick]
## (set APPDATA to a scratch folder). `--quick`: the flat picture only, at 1720x720, to tune a view. Quits by itself.

const OUT := "res://world/ui/baked_vistas"
const PREVIEW := "res://tools/town_planner/build/out/lab"
const FLAT := Vector2i(3440, 1440)
const FACE := 2048
const SUPER := 2
const FOV := 75.0            # the desktop camera's default (Settings controls/fov)
const SKY_FOV := 50.0         # the title's own camera (title_screen.gd)
## name (the game's title/view names, kept: Settings lists them) -> where it is.
## eye: [x, metres above the ground there, z]; look: [x, metres above the ground there, z]; hours; extras.
const VIEWS := {
	"town_square": {"label": "the market at noon", "eye": [145.0, 13.0, -252.0], "look": [134.0, 0.0, -287.0], "hours": 12.0, "shoppers": 6},
	"above_ponyville": {"label": "the whole town, late afternoon", "eye": [246.0, 38.0, -222.0], "look": [135.5, 6.0, -175.9], "hours": 17.2},
	"golden_oak": {"label": "the schoolhouse, late afternoon", "eye": [56.0, 1.7, -38.0], "look": [30.5, 3.2, -50.0], "hours": 17.2},
	"sweet_apple_acres": {"label": "the barn, late afternoon", "eye": [-6.0, 2.0, 36.0], "look": [-27.4, 4.0, 51.5], "hours": 17.2},
	"fluttershy_cottage": {"label": "the cottage at night", "eye": [409.0, 1.9, -31.0], "look": [407.9, 2.8, 1.08], "hours": 23.0},
	# checks only (--views hill_check, --quick): never title pictures
	"hill_check": {"label": "the new hill from the town", "eye": [262.0, 6.0, -232.0], "look": [372.0, 9.0, -290.0], "hours": 15.0, "check": true},
	"hill_top_check": {"label": "the town from the hill", "eye": [366.0, 1.7, -286.0], "look": [200.0, -2.0, -210.0], "hours": 15.0, "check": true},
	"zecora_hut": {"label": "the Town Hall at night, moon up", "eye": [173.0, 12.0, -161.0], "look": [135.5, 9.0, -175.9], "hours": 4.75, "full_moon": true},
}
var game: Node
var player: Node3D
var quick := false
var _held: Array = []


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		await get_tree().process_frame


func _go() -> void:
	get_tree().create_timer(2400.0).timeout.connect(func() -> void: print("VISTA watchdog"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	player = game.get("player")
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"): await (arrival as Node).skip_to_free_home()
	var args := OS.get_cmdline_user_args()
	quick = "--quick" in args
	var only := PackedStringArray()
	if "--views" in args: only = args[args.find("--views") + 1].split(",")
	var season: Node = get_tree().get_first_node_in_group("season_state")
	if season != null and season.has_method("pin"): season.call("pin", "summer"); season.call("tick")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW))
	var first := true
	for view: String in VIEWS:
		if not only.is_empty() and not only.has(view): continue
		if bool(VIEWS[view].get("check", false)) and not only.has(view): continue
		await _capture(view, VIEWS[view], first)
		first = false
	print("VISTA done")
	get_tree().quit()


func _ground(x: float, z: float) -> float:
	var h: float = WorldTerrain.instance.height_at(Vector3(x, 0, z))
	return h if is_finite(h) else -12.0


func _capture(view: String, spec: Dictionary, first: bool) -> void:
	var e: Array = spec.eye
	var l: Array = spec.look
	var eye := Vector3(e[0], _ground(e[0], e[2]) + float(e[1]), e[2])
	var look := Vector3(l[0], _ground(l[0], l[2]) + float(l[1]), l[2])
	# the player stands just behind the eye, so the place streams in, then is hidden
	player.global_position = Vector3(eye.x, _ground(eye.x, eye.z) + 0.5, eye.z) + (eye - look).normalized() * Vector3(4, 0, 4)
	if "velocity" in player: player.set("velocity", Vector3.ZERO)
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null:
		if bool(spec.get("full_moon", false)):
			# a full moon: the moon's phase angle near 0 at this hour (time_of_day.gd moon_phase_angle)
			tod.day = int(round(float(tod.MOON_CYCLE_DAYS) * 4.0 - float(spec.hours) / 24.0))
		tod.hours = float(spec.hours)
		tod.paused = true
	var season: Node = get_tree().get_first_node_in_group("season_state")
	if season != null and season.has_method("tick"): season.call("tick")
	await _wait(25.0 if first else 14.0)
	if int(spec.get("shoppers", 0)) > 0: await _shoppers(look, int(spec.shoppers))
	_hud(false)
	var basis := Basis.looking_at(look - eye, Vector3.UP)
	if tod != null and bool(spec.get("full_moon", false)):
		var moon: Vector3 = tod.call("moon_direction")
		print("VISTA %s moon elevation %.1f deg, %.0f deg off the view, lit %.2f" % [view, rad_to_deg(asin(moon.y)), rad_to_deg(acos(clampf((-basis.z).normalized().dot(moon), -1, 1))), tod.call("moon_lit_fraction")])
	var flat_size := FLAT / 2 if quick else FLAT
	var flat := await _render(Transform3D(basis, eye), flat_size * (1 if quick else SUPER), FOV)
	flat.resize(flat_size.x, flat_size.y, Image.INTERPOLATE_LANCZOS)
	flat.save_png(ProjectSettings.globalize_path(PREVIEW.path_join("vista_%s.png" % view)))
	if not quick and not bool(spec.get("check", false)):
		flat.save_jpg(ProjectSettings.globalize_path(OUT.path_join(view + ".picture")), 0.92)   # JPEG bytes; an extension the importer leaves alone, so the pack carries the file itself
		if not bool(spec.get("check", false)): await _cube(view, eye, basis)
	_hud(true)
	print("VISTA %s (%s) at %s looking at %s, %.2f h" % [view, spec.label, eye, look, float(spec.hours)])


## Ponies shopping: the nearest few brought to stand before the market's stalls, facing them, held still.
func _shoppers(centre: Vector3, count: int) -> void:
	var stalls: Array[Node3D] = []
	# the market's own pieces (RNLScenery/.../Market), each stall or tent once
	for market: Node in get_tree().root.find_children("Market", "Node3D", true, false):
		for node: Node in market.get_children():
			if node is Node3D and (node as Node3D).global_position.distance_to(centre) < 40.0: stalls.append(node as Node3D)
	var population: Node = get_tree().get_first_node_in_group("pony_populations")
	var live: Dictionary = population.get("live") if population != null else {}
	var ids: Array = live.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var pa: Node3D = live[a].get("actor"); var pb: Node3D = live[b].get("actor")
		return (pa.global_position.distance_to(centre) if is_instance_valid(pa) else INF) < (pb.global_position.distance_to(centre) if is_instance_valid(pb) else INF))
	var placed := 0
	for id: String in ids:
		if placed >= mini(count, stalls.size() * 2): break
		var body: Node3D = live[id].get("actor")
		if not is_instance_valid(body) or body.get("flight") != null and body.flight.active(): continue
		var stall: Node3D = stalls[placed % stalls.size()]
		var out := Vector3(centre.x - stall.global_position.x, 0, centre.z - stall.global_position.z).normalized()
		var at := stall.global_position + out * 2.6 + out.cross(Vector3.UP) * (1.1 if placed >= stalls.size() else 0.0)
		at.y = _ground(at.x, at.z) + 0.05
		var nav: Node = body.get_node_or_null("Navigator")
		if nav != null: nav.call("stay"); nav.set("command_owner", "lab:vista"); nav.set("wander_enabled", false)
		if body.has_method("reset_motion"): body.call("reset_motion", Transform3D(Basis.looking_at(-out, Vector3.UP), at))
		else: body.global_position = at
		if body.has_method("face_direction"): body.call("face_direction", -out)
		placed += 1
		_held.append([body, Transform3D(Basis.looking_at(-out, Vector3.UP), at)])
	print("VISTA shoppers: %d of %d stalls" % [placed, stalls.size()])
	await _wait(4.0)
	for row: Array in _held:
		print("VISTA shopper %s at %s (wanted %s)" % [(row[0] as Node).name, (row[0] as Node3D).global_position, (row[1] as Transform3D).origin])


## The world from `xform` at `size`, through a viewport sharing the game's world.
func _render(xform: Transform3D, size: Vector2i, fov: float, world: World3D = null, env: Environment = null) -> Image:
	var port := SubViewport.new()
	port.size = size
	port.msaa_3d = Viewport.MSAA_4X
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	port.own_world_3d = world != null
	if world == null: port.world_3d = get_viewport().world_3d
	add_child(port)
	if world != null: port.world_3d = world
	# the shoppers held where they were put (their day would walk them off)
	for row: Array in _held:
		if is_instance_valid(row[0]):
			(row[0] as Node3D).global_transform = row[1]
			if "velocity" in row[0]: (row[0] as Node3D).set("velocity", Vector3.ZERO)
	var cam := Camera3D.new(); cam.fov = fov; cam.near = 0.1; cam.far = 4000.0
	if env != null: cam.environment = env
	port.add_child(cam)
	cam.global_transform = xform
	cam.current = true
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := port.get_texture().get_image()
	port.queue_free()
	return image


## The cubemap's six faces about `basis` (its -Z is the title camera's view), each in the layout a cube texture
## samples (+X, -X, +Y, -Y, +Z, -Z; tried mirrored and not, the one that matches the world kept).
const FACES := [[Vector3.RIGHT, Vector3.UP], [Vector3.LEFT, Vector3.UP], [Vector3.UP, Vector3.FORWARD], [Vector3.DOWN, Vector3.BACK],
	[Vector3.BACK, Vector3.UP], [Vector3.FORWARD, Vector3.UP]]
func _cube(view: String, eye: Vector3, basis: Basis) -> void:
	var faces: Array[Image] = []
	for f: Array in FACES:
		var d: Vector3 = basis * Vector3(f[0]); var up: Vector3 = basis * Vector3(f[1])
		var image := await _render(Transform3D(Basis.looking_at(d, up), eye), Vector2i(FACE * SUPER, FACE * SUPER), 90.0)
		image.resize(FACE, FACE, Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGB8)
		faces.append(image)
	# which way the faces read: check by drawing the sky against the world forward, to the right and up
	var best := -1; var best_err := INF
	for mirrored: int in 2:
		var cube := _assemble(faces, mirrored == 1, false)
		var err := 0.0
		for dir: Array in [[Vector3.FORWARD, Vector3.UP], [Vector3.RIGHT, Vector3.UP], [Vector3.UP, Vector3.BACK]]:
			var xf := Transform3D(Basis.looking_at(basis * Vector3(dir[0]), basis * Vector3(dir[1])), Vector3.ZERO)
			var sky := await _render(xf, Vector2i(320, 320), SKY_FOV, World3D.new(), _sky_env(cube))
			var truth := await _render(Transform3D(xf.basis, eye), Vector2i(320, 320), SKY_FOV)
			err += _diff(sky, truth)
		print("VISTA %s faces mirrored %s: difference %.1f" % [view, mirrored == 1, err])
		if err < best_err: best_err = err; best = mirrored
	var final := _assemble(faces, best == 1, true)
	var path := OUT.path_join(view + ".res")
	print("VISTA %s cubemap %s (mirrored %s) save %s" % [view, path, best == 1, ResourceSaver.save(final, path, ResourceSaver.FLAG_COMPRESS)])


func _assemble(faces: Array[Image], mirrored: bool, finished: bool) -> Cubemap:
	var layers: Array[Image] = []
	for image: Image in faces:
		var copy := image.duplicate() as Image
		if mirrored: copy.flip_x()
		if finished:
			copy.generate_mipmaps()
			copy.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
		layers.append(copy)
	var cube := Cubemap.new()
	cube.create_from_images(layers)
	return cube


func _sky_env(cube: Cubemap) -> Environment:
	var shader := Shader.new()
	shader.code = "shader_type sky; uniform samplerCube panorama : source_color, filter_linear_mipmap; void sky() { COLOR = texture(panorama, EYEDIR).rgb; }"
	var material := ShaderMaterial.new(); material.shader = shader; material.set_shader_parameter("panorama", cube)
	var sky := Sky.new(); sky.sky_material = material
	var env := Environment.new(); env.background_mode = Environment.BG_SKY; env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return env


func _diff(a: Image, b: Image) -> float:
	a.convert(Image.FORMAT_RGB8); b.convert(Image.FORMAT_RGB8)
	var total := 0.0
	for y in range(0, a.get_height(), 8):
		for x in range(0, a.get_width(), 8):
			var ca := a.get_pixel(x, y); var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total


func _hud(on: bool) -> void:
	for layer: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = on
	for panel: Node in get_tree().root.find_children("*", "Control", true, false):
		if not (panel.get_parent() is Control):
			if on and panel.has_meta("vista_hid"): (panel as Control).visible = true; panel.remove_meta("vista_hid")
			elif not on and (panel as Control).visible: panel.set_meta("vista_hid", true); (panel as Control).visible = false
	if is_instance_valid(player): player.visible = on
