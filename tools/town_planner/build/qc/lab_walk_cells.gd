extends Node
## The walk grid round given points (--points "x,z;x,z"): for each, its walk-grid cells in a 3 m square (each cell:
## '#' no floor, 'x' a floor but not walkable for a pony at canon size, '.' walkable, '@' the point), what stands there
## (physics shapes' owners within 2 m), and a picture from above. Prints CELLS lines.
func _ready() -> void:
	_go.call_deferred()

func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	return args[args.find(name) + 1] if name in args else fallback

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	var points: Array[Vector3] = []
	for t: String in _arg("--points", "77,-207").split(";"):
		var f := t.split(","); var p := Vector3(float(f[0]), 0, float(f[1])); points.append(p)
	game.get("player").global_position = points[0] + Vector3(0, 2, 6)
	await get_tree().create_timer(25.0).timeout
	var svc: Node = null
	for s: Node in get_tree().get_nodes_in_group("pony_navigation"): svc = s
	var pony: Node = null
	for nav: Node in get_tree().get_nodes_in_group("pony_navigators"): pony = nav.get("pony"); break
	var profile: Resource = pony.get("profile")
	if pony.has_method("set_body_scale"): pony.call("set_body_scale", 1.0)
	var space: PhysicsDirectSpaceState3D = get_tree().current_scene.get_world_3d().direct_space_state
	var cam := Camera3D.new(); get_tree().current_scene.add_child(cam)
	var k := 0
	for p0: Vector3 in points:
		var p := p0; p.y = WorldTerrain.instance.height_at(p)
		svc.call("ensure_near", p, 8.0)
		await get_tree().create_timer(3.0).timeout
		print("CELLS point %s: walkable %s, closest %s" % [p.snapped(Vector3.ONE * 0.01), svc.call("is_walkable", p, profile), (svc.call("closest", p, profile, 1.0) as Vector3).snapped(Vector3.ONE * 0.01)])
		for dz in range(-6, 7):
			var row := ""
			for dx in range(-6, 7):
				var q := p + Vector3(dx * 0.5, 0, dz * 0.5)
				var ch := "#"
				var c: Vector3 = svc.call("closest", q, profile, 0.45)
				if dx == 0 and dz == 0: ch = "@"
				elif c.is_finite() and Vector2(c.x - q.x, c.z - q.z).length() < 0.3: ch = "."
				else:
					var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 3.0, q + Vector3.DOWN * 3.0))
					ch = "x" if not hit.is_empty() else "#"
				row += ch
			print("CELLS   %s" % row)
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new(); sphere.radius = 2.0
		query.shape = sphere; query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.8)
		var owners := {}
		for r: Dictionary in space.intersect_shape(query, 32):
			var o: Object = r.collider
			if o is Node: owners[str(get_tree().root.get_path_to(o as Node)).replace("Main/Zones/PonyvilleTown/", "")] = true
		print("CELLS   near: ", owners.keys())
		cam.global_position = p + Vector3(0, 9, 0.01); cam.look_at(p, Vector3.FORWARD); cam.make_current()
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(_arg("--shots", "").path_join("cells_%d.png" % k)); k += 1
	get_tree().quit()
