extends SceneTree
## Quality control: which way does each landmark model face? Three pictures of each scene named on the command
## line, alone on a grey floor: from straight above (model +z toward the bottom of the picture, +x to the right),
## from its +z side and from its -z side. A red post stands 2 m outside its +z edge, a blue one outside +x.
##   godot --xr-mode off --path <project> --script res://tools/town_planner/build/qc/model_shots.gd -- <out dir> [scale=10] <scene path>...
## (scale= for the house scenes, which are one unit big)
## Needs a window (not --headless).

func _initialize() -> void:
	_run.call_deferred()


func _box(n: Node, t: Transform3D) -> AABB:
	var out := AABB(); var first := true
	var stack: Array = [[n, t]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var at: Node = item[0]; var x: Transform3D = item[1]
		for c in at.get_children():
			stack.append([c, x * (c as Node3D).transform if c is Node3D else x])
		if at is MeshInstance3D and (at as MeshInstance3D).mesh != null:
			var b: AABB = x * (at as MeshInstance3D).mesh.get_aabb()
			if first: out = b; first = false
			else: out = out.merge(b)
	return out


func _post(holder: Node3D, at: Vector3, colour: Color) -> Node3D:
	var m := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3(0.5, 3.0, 0.5); m.mesh = box
	var mat := StandardMaterial3D.new(); mat.albedo_color = colour; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.material_override = mat
	m.position = at + Vector3(0, 1.5, 0); holder.add_child(m)
	return m


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1000, 750)
	var holder := Node3D.new(); root.add_child(holder)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.55, 0.6, 0.65)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color.WHITE; e.ambient_light_energy = 0.9
	env.environment = e; holder.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55, -30, 0); holder.add_child(sun)
	var cam := Camera3D.new(); cam.far = 2000.0; holder.add_child(cam); cam.make_current()
	var size := 1.0
	for i in range(1, args.size()):
		var path: String = args[i]
		if path.begins_with("scale="): size = float(path.trim_prefix("scale=")); continue
		var packed := load(path) as PackedScene
		if packed == null: print("NO SCENE ", path); continue
		var node := packed.instantiate() as Node3D
		node.transform = Transform3D.IDENTITY.scaled(Vector3.ONE * size)
		var box := _box(node, node.transform)
		holder.add_child(node)
		var c := box.get_center(); var r := maxf(box.size.x, box.size.z) * 0.5 + (3.0 if size == 1.0 else 1.0)
		var red := _post(holder, Vector3(c.x, box.position.y, box.end.z + 2.0), Color.RED)
		var blue := _post(holder, Vector3(box.end.x + 2.0, box.position.y, c.z), Color.BLUE)
		var name := path.get_base_dir().get_file() if path.get_file() == "prefab.scn" else path.get_file().get_basename()
		var shots := [
			["top", Vector3(c.x, box.end.y + 60.0, c.z), Vector3(0, 0, -1), true],
			["plus_z", Vector3(c.x, box.position.y + box.size.y * 0.6 + 2.0, box.end.z + r * 1.6), Vector3.UP, false],
			["minus_z", Vector3(c.x, box.position.y + box.size.y * 0.6 + 2.0, box.position.z - r * 2.6), Vector3.UP, false],
			["minus_z_far", Vector3(c.x + r, box.position.y + box.size.y + 6.0, box.position.z - r * 3.0), Vector3.UP, false],
		]
		for shot: Array in shots:
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL if shot[3] else Camera3D.PROJECTION_PERSPECTIVE
			cam.size = r * 2.2; cam.fov = 55.0
			cam.look_at_from_position(shot[1], Vector3(c.x, box.position.y + box.size.y * 0.4, c.z) if not shot[3] else c, shot[2])
			for f in 4: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, name, shot[0]])
		print("SHOT %s box x %.1f..%.1f y %.1f..%.1f z %.1f..%.1f" % [name, box.position.x, box.end.x, box.position.y, box.end.y, box.position.z, box.end.z])
		node.queue_free(); red.queue_free(); blue.queue_free()
		await process_frame
	quit()
