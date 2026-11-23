extends Node
## The Hayburger's customer markers (hayburger_customers.gd _markers): where each is, the walk grid there, and whether
## the restaurant finds a supported spot (_destination) for a canon pony in each slot; then the restaurant watched for
## --seconds with every visit logged. Prints HBM lines.
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
	game.get("player").global_position = Vector3(0, -10, -192)
	await get_tree().create_timer(40.0).timeout
	# (skip_to_free_home moves the player to a home after the first placing: place again, and wait for the ground's
	# collision round him)
	game.get("player").global_position = Vector3(-2, -11.5, -178)
	await get_tree().create_timer(8.0).timeout
	print("HBM player at ", (game.get("player") as Node3D).global_position.snapped(Vector3.ONE * 0.1))
	var customers: Node = get_tree().get_first_node_in_group("hayburger_customers")
	var markers: Dictionary = customers.get("_markers")
	var svc: Node = null
	for s: Node in get_tree().get_nodes_in_group("pony_navigation"): svc = s
	var pony: Node3D = null
	for nav: Node in get_tree().get_nodes_in_group("pony_navigators"): pony = nav.get("pony"); break
	for name: String in markers:
		var m: Node3D = markers[name]
		if not is_instance_valid(m): print("HBM %s: gone" % name); continue
		var line := "HBM %s at %s terrain %.2f walkable %s closest %s |" % [name, m.global_position.snapped(Vector3.ONE * 0.01), WorldTerrain.instance.height_at(m.global_position), svc.call("is_walkable", m.global_position, pony.get("profile")), (svc.call("closest", m.global_position, pony.get("profile"), 1.0) as Vector3).snapped(Vector3.ONE * 0.01)]
		for slot in 3:
			var d: Vector3 = customers.call("_destination", {"actor": pony, "slot": slot, "id": "lab"}, name, false)
			line += " slot%d %s" % [slot, d.snapped(Vector3.ONE * 0.01)]
		print(line)
	var space: PhysicsDirectSpaceState3D = pony.get_world_3d().direct_space_state
	for name: String in ["EntrySpawn", "EntryClearance", "DeparturePoint"]:
		var m: Node3D = markers[name]
		var r := float(pony.get("profile").radius)
		for off: Vector3 in [Vector3.ZERO, Vector3.RIGHT * r, Vector3.LEFT * r, Vector3.FORWARD * r, Vector3.BACK * r]:
			var st := m.global_position + off + Vector3.UP * 0.5
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(st, m.global_position + off - Vector3.UP * 0.75, 1))
			var l15 := space.intersect_ray(PhysicsRayQueryParameters3D.create(st, (hit.position as Vector3) + Vector3.DOWN * .02 if not hit.is_empty() else st + Vector3.DOWN * 1.3, 1 << 15))
			print("HBM ray %s %s: %s %s normal %s | layer15 %s" % [name, off.snapped(Vector3.ONE * 0.01), (hit.position as Vector3).snapped(Vector3.ONE * 0.01) if not hit.is_empty() else "MISS", get_tree().root.get_path_to(hit.collider) if not hit.is_empty() else "", (hit.normal as Vector3).snapped(Vector3.ONE * 0.01) if not hit.is_empty() else "", get_tree().root.get_path_to(l15.collider) if not l15.is_empty() else "-"])
		var shape := CylinderShape3D.new(); shape.radius = r; shape.height = float(pony.get("profile").clearance)
		var q := PhysicsShapeQueryParameters3D.new(); q.shape = shape; q.transform.origin = m.global_position + Vector3.UP * (shape.height * .5 + .06); q.collision_mask = 1 | 2048
		for f: Dictionary in space.intersect_shape(q, 6): print("HBM shape %s blocked by %s" % [name, get_tree().root.get_path_to(f.collider)])
	var seen := {}
	var t := 0.0
	var seconds := float(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--seconds") + 1]) if "--seconds" in OS.get_cmdline_user_args() else 240.0
	while t < seconds:
		await get_tree().create_timer(2.0).timeout; t += 2.0
		var visitors: Dictionary = customers.get("_visitors")
		for id: String in visitors:
			var ph := str(visitors[id].get("phase", ""))
			if seen.get(id, "") != ph: seen[id] = ph; print("HBM %3.0fs visitor %s phase %s at %s" % [t, id, ph, (visitors[id].actor as Node3D).global_position.snapped(Vector3.ONE * 0.1)])
		var last: Variant = customers.get("_last_recruit")
		if last is Dictionary and str(last.get("result", "")) != str(seen.get("_last", "")):
			seen["_last"] = str(last.get("result", "")); print("HBM %3.0fs last recruit: %s" % [t, last])
	get_tree().quit()
