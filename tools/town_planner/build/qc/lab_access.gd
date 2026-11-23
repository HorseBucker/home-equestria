extends Node
## Can ponies get to every town destination (2026-11-23 play test: leads to the boutique, Golden Oak, Town Hall, the
## spa, Fluttershy's cottage failing): for every landmark the AI can name and every walk-in home, with the player
## standing there (the ground's collision is only built round him) and the walk grid sampled round it, the point a
## pony is sent to (navigator command_location, as go_to and lead use it), whether it is walkable, and a route to it
## from street ground ~30 m out toward Town Hall (the service's own request_path), at canon size and at --scale
## (default 1.35). Prints ACCESS lines; one per destination and size.
var _results := {}

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
	await get_tree().create_timer(25.0).timeout
	var player: Node3D = game.get("player")
	var svc: Node = null
	for s: Node in get_tree().get_nodes_in_group("pony_navigation"): svc = s
	var nav: Node = null
	for n: Node in get_tree().get_nodes_in_group("pony_navigators"):
		if str((n.get("pony") as Node).name).to_lower().contains(_arg("--pony", "twilight")): nav = n; break
	if nav == null: nav = get_tree().get_nodes_in_group("pony_navigators")[0]
	var pony: Node3D = nav.get("pony")
	var places := preload("res://world/navigation/place_directory.gd")
	var only := _arg("--only", "")
	var targets: Array = []
	for e: Dictionary in places.entries(get_tree()):
		var id := str(e.id)
		var keep: bool = (e.kind == "landmark" and (bool(e.get("town_destination", false)) or id.contains("goldenoak") or id.contains("town_hall") or id.contains("spa")))
		var node: Node = e.get("node")
		if e.kind == "house" and node != null and not (node.get_script() != null and str((node.get_script() as Script).resource_path).ends_with("house_interior.gd")): keep = true   # the walk-in homes
		if id.contains("cloudominium"): keep = false        # (in the sky: fliers only)
		if not only.is_empty() and not id.contains(only): keep = false
		if keep: targets.append(e)
	print("ACCESS %d destinations" % targets.size())
	var hall := Vector3(135.5, -12.0, -175.9)
	for e: Dictionary in targets:
		var anchor: Vector3 = e.position
		player.global_position = anchor + Vector3(0, 3, 0)
		if pony.has_method("reset_motion"): pony.call("reset_motion", Transform3D(Basis.IDENTITY, anchor + Vector3(4, 1, 4)))
		await get_tree().create_timer(3.0).timeout
		for size: float in [1.0, float(_arg("--scale", "1.35"))]:
			if pony.has_method("set_body_scale"): pony.call("set_body_scale", size)
			var goal: Vector3 = nav.call("command_location", str(e.id))
			if not goal.is_finite(): print("ACCESS %s | %s size %.2f: no point to go to" % [e.id, e.label, size]); continue
			var toward := hall - goal; toward.y = 0
			if toward.length() < 20.0: toward = Vector3(-60, 0, -40)
			var start_guess := goal + toward.normalized() * 30.0
			svc.call("ensure_near", goal, 24.0); svc.call("ensure_near", start_guess, 12.0)
			for wait in 40:
				await get_tree().create_timer(0.5).timeout
				if not bool(svc.get("baking")): break
			goal = nav.call("command_location", str(e.id))
			var start: Vector3 = svc.call("closest", Vector3(start_guess.x, WorldTerrain.instance.height_at(start_guess), start_guess.z), pony.get("profile"), 6.0)
			var walkable: bool = svc.call("is_walkable", goal, pony.get("profile"))
			var near: Vector3 = svc.call("closest", goal, pony.get("profile"), 1.5)
			var key := "%s@%s" % [e.id, size]
			_results.erase(key)
			svc.call("request_path", start, goal, pony.get("profile"), func(result: Dictionary, _id: int, _rev: int) -> void: _results[key] = result)
			for wait in 80:
				await get_tree().create_timer(0.25).timeout
				if _results.has(key): break
			var r: Dictionary = _results.get(key, {})
			var path: PackedVector3Array = r.get("path", PackedVector3Array())
			var end_gap := Vector2(path[-1].x - goal.x, path[-1].z - goal.z).length() if not path.is_empty() else INF
			print("ACCESS %s | %s | size %.2f | goal %s walkable %s (nearest %s) | from %s | %s" % [e.id, e.label, size, goal.snapped(Vector3.ONE * 0.01), walkable, near.snapped(Vector3.ONE * 0.01), start.snapped(Vector3.ONE * 0.1),
				("ROUTE %d points, ends %.2f m from goal" % [path.size(), end_gap]) if not path.is_empty() else "NO ROUTE: %s" % r.get("reason", "timed out" if r.is_empty() else "?")])
	get_tree().quit()
