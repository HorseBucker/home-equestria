extends Node
## Rainbow Dash's Cloudominium door: where outside() and inside() are, what the floor rays find round the door point
## (layer, height), her flight's landing_surface there, and the walk grid's floor. Prints CLOUD lines.
func _ready() -> void:
	_go.call_deferred()

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
	var home: Node3D = null
	for h: Node in get_tree().get_nodes_in_group("house_interiors"):
		if h.has_method("sky_home"): home = h
	var out: Vector3 = home.call("outside"); var ins: Vector3 = home.call("inside")
	game.get("player").global_position = out + Vector3(1, 1, 1)
	await get_tree().create_timer(8.0).timeout
	print("CLOUD outside %s inside %s porch %s" % [out.snapped(Vector3.ONE * 0.01), ins.snapped(Vector3.ONE * 0.01), home.get_node_or_null("WalkablePorch") != null])
	var up: Node = home
	while up != null and up != get_tree().root:
		if up is Node3D: print("CLOUD ancestor %s scale %s script %s" % [up.name, (up as Node3D).global_basis.get_scale().snapped(Vector3.ONE * 0.01), (up.get_script() as Script).resource_path.get_file() if up.get_script() != null else "-"])
		up = up.get_parent()
		if str(up.name) == "RNLScenery": break
	var porch: Node = home.get_node_or_null("WalkablePorch")
	if porch != null:
		for c: Node in porch.get_children(): print("CLOUD porch part %s at %s" % [c.name, (c as Node3D).global_position.snapped(Vector3.ONE * 0.01)])
	var space: PhysicsDirectSpaceState3D = home.get_world_3d().direct_space_state
	var door_dir: Vector3 = (ins - out); door_dir.y = 0; door_dir = door_dir.normalized()
	for off: Vector3 in [Vector3.ZERO, Vector3(.35, 0, 0), Vector3(-.35, 0, 0), Vector3(0, 0, .35), Vector3(0, 0, -.35), door_dir * 0.6, door_dir * 1.2, door_dir * 1.8, door_dir * 2.4, -door_dir * 1.2]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(out + off + Vector3.UP, out + off + Vector3.DOWN * 2.0, 0xFFFFFFFF))
		print("CLOUD ray %s: %s" % [off, "%s layer %d %s normal %s" % [(hit.position as Vector3).snapped(Vector3.ONE * 0.01), (hit.collider as CollisionObject3D).collision_layer, get_tree().root.get_path_to(hit.collider), (hit.normal as Vector3).snapped(Vector3.ONE * 0.01)] if not hit.is_empty() else "MISS"])
	var dash: Node = null
	for n: Node in get_tree().get_nodes_in_group("pony_navigators"):
		if str((n.get("pony") as Node).name) == "RainbowDash": dash = n.get("pony")
	if dash != null:
		var flight: Object = dash.get("flight")
		print("CLOUD floor_mask %d landing_surface(outside) %s" % [dash.get("floor_mask"), flight.call("landing_surface", out)])
	var svc: Node = null
	for s: Node in get_tree().get_nodes_in_group("pony_navigation"): svc = s
	svc.call("ensure_near", out, 6.0)
	await get_tree().create_timer(20.0).timeout
	print("CLOUD walk grid bounds ", svc.get("bounds"))
	var pad_top := out + Vector3.DOWN * 0.31
	if dash != null:
		for p: Vector3 in [out, pad_top, pad_top + (ins - out).normalized() * 1.2, ins]:
			print("CLOUD walk grid at %s: walkable %s closest %s" % [p.snapped(Vector3.ONE * 0.01), svc.call("is_walkable", p, dash.get("profile")), (svc.call("closest", p, dash.get("profile"), 1.0) as Vector3).snapped(Vector3.ONE * 0.01)])
	# standing at her door, told to go in
	if dash != null:
		var director: Node = get_tree().get_first_node_in_group("conversation_director")
		var executor: Object = (director.get("actions") as Object).get("executors")["rainbow_dash"]
		var nav: Node = dash.get_node("Navigator")
		nav.set("reserved_by", ""); nav.call("stay"); nav.set("command_owner", "")
		var life: Node = game.get("life") as Node
		if is_instance_valid(life) and life.get("core") != null and life.core.state.residents.has("rainbow_dash"): life.core.state.residents["rainbow_dash"]["paused"] = true
		dash.call("reset_motion", Transform3D(Basis.IDENTITY, out + Vector3.UP * 0.2))
		await get_tree().create_timer(2.0).timeout
		var reports: Array[String] = []
		executor.connect("outcome", func(event: Dictionary) -> void: if str(event.get("id", "")) == "lab_home": reports.append("%s: %s" % [event.get("status", ""), event.get("reason", "")]))
		executor.call("submit", [{"id": "lab_home", "type": "go_to", "location_id": "house:cloudominium", "pace": "trot"}], {}, 2000000)
		var t := 0.0; var in_at := -1.0
		while t < 60.0:
			await get_tree().create_timer(0.5).timeout; t += 0.5
			if in_at < 0.0 and home.call("contains", dash.global_position): in_at = t
			if t == floorf(t) and int(t) % 5 == 0: print("CLOUD   %2.0fs at %s state %s '%s'" % [t, dash.global_position.snapped(Vector3.ONE * 0.01), nav.get("state"), nav.get("reason")])
			if reports.any(func(r: String) -> bool: return r.begins_with("completed") or r.begins_with("failed")): break
		print("CLOUD at the door, go inside: %s; %s" % [("INSIDE after %.1f s" % in_at) if in_at >= 0.0 else "NOT inside", ", ".join(reports)])
	get_tree().quit()
