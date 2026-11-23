extends Node
## The walk grid's own data for the cells along a line (--from x,z --to x,z, 0.25 m steps): each span's floor height,
## slope, headroom, water and flags, and whether a canon pony fits there. Prints DUMP lines.
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
	var f := _arg("--from", "98,-102").split(","); var t := _arg("--to", "103,-100").split(",")
	var a := Vector3(float(f[0]), 0, float(f[1])); var b := Vector3(float(t[0]), 0, float(t[1]))
	game.get("player").global_position = a + Vector3(0, 2, 4)
	await get_tree().create_timer(25.0).timeout
	game.get("player").global_position = a + Vector3(0, 2, 4)      # (again: skip_to_free_home moved him home)
	await get_tree().create_timer(8.0).timeout
	var svc: Node = null
	for s: Node in get_tree().get_nodes_in_group("pony_navigation"): svc = s
	svc.call("ensure_near", a.lerp(b, 0.5), 10.0)
	await get_tree().create_timer(6.0).timeout
	var pony: Node = null
	for nav: Node in get_tree().get_nodes_in_group("pony_navigators"): pony = nav.get("pony"); break
	var profile: Resource = pony.get("profile")
	if pony.has_method("set_body_scale"): pony.call("set_body_scale", 1.0)
	print("DUMP profile ", WalkGrid.profile(profile))
	var n := int(a.distance_to(b) / 0.25)
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		var c := WalkGrid.column(p)
		var line := "DUMP (%.2f,%.2f) terrain %.2f |" % [p.x, p.z, WorldTerrain.instance.height_at(p)]
		for span in WalkGrid.SPANS:
			var s: Dictionary = svc.call("cached_sample", Vector3i(c.x, span, c.y))
			if s.is_empty(): line += " -"; continue
			line += " y %.2f slope %s head %.2f water %.2f flags %d ok %s |" % [s.get("height", NAN), s.get("slope", "?"), s.get("clearance", s.get("headroom", NAN)), s.get("water", 0.0), s.get("flags", 0), WalkGrid.allowed(s, WalkGrid.profile(profile))]
		var c3: Vector3 = svc.call("closest", Vector3(p.x, WorldTerrain.instance.height_at(p), p.z), profile, 0.45)
		line += " walkable-here %s" % (c3.is_finite() and Vector2(c3.x - p.x, c3.z - p.z).length() < 0.3)
		print(line)
	get_tree().quit()
