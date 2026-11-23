extends Node
## A pony following the player into a building (2026-11-23 play test: "I typically have to pick them up and bring
## them in"): --home place id (house:carousel_boutique, or any house:...), --pony id, --scale. The pony follows
## (the AI's "follow"); the player stands outside, opens the door and walks in at 1 m/s from outside() through the
## doorway to inside() and on to the room's middle, then waits. FOLLOWIN result: inside or not, and when.
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
	var home_id := _arg("--home", "house:carousel_boutique")
	var home: Node3D = null
	var player: Node3D = game.get("player")
	for tries in (0 if home_id == "hayburger" else 40):
		for e: Dictionary in preload("res://world/navigation/place_directory.gd").entries(get_tree()):
			if e.id == home_id: home = e.node
		if home != null: break
		await get_tree().create_timer(1.0).timeout
	var hayburger := home_id == "hayburger"
	if home == null and not hayburger: print("FOLLOWIN no home ", home_id); get_tree().quit(); return
	var outside: Vector3 = Vector3(-10.1, -12.0, -181.0) if hayburger else home.call("outside")
	var inside_at: Vector3 = Vector3(-10.1, -11.96, -184.6) if hayburger else home.call("inside")
	var away: Vector3 = outside - inside_at; away.y = 0; away = away.normalized()
	player.global_position = outside + away * 3.0 + Vector3.UP * 0.3
	await get_tree().create_timer(25.0).timeout
	player.global_position = outside + away * 3.0 + Vector3.UP * 0.3      # (again: skip_to_free_home moved him home)
	await get_tree().create_timer(8.0).timeout
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var executors: Dictionary = (director.get("actions") as Object).get("executors")
	var id := _arg("--pony", "rainbow_dash")
	var executor: Object = executors[id]
	var actor: Node3D = executor.get("actor")
	if actor.has_method("set_body_scale"): actor.call("set_body_scale", float(_arg("--scale", "1.0")))
	if actor.has_method("reset_motion"): actor.call("reset_motion", Transform3D(Basis.IDENTITY, outside + away * 5.0 + Vector3.UP * 0.3))
	await get_tree().create_timer(3.0).timeout
	var report := ""
	executor.connect("outcome", func(event: Dictionary) -> void: report = "%s: %s" % [event.get("status", ""), event.get("reason", "")])
	executor.call("submit", [{"id": "lab_follow", "type": "follow", "target_id": "player", "formation": "right", "distance_m": 1.5}], {"player": player}, 999999)
	await get_tree().create_timer(3.0).timeout
	var doors: Array = []
	if hayburger:
		for n: Node in get_tree().root.find_children("*", "", true, false):
			if n.get_script() != null and str((n.get_script() as Script).resource_path).ends_with("hayburger_door.gd"): doors.append(n)
	elif home.has_method("door"): doors.append(home.call("door"))
	for door: Node in doors:
		if door != null and door.has_method("toggle_door"): door.call("toggle_door")
	await get_tree().create_timer(1.5).timeout
	var route: Array[Vector3] = [outside + away * 3.0, outside, inside_at, Vector3(-10.1, -11.96, -188.0) if hayburger else home.call("center")]
	var in_room := func(p: Vector3) -> bool: return (p.z < -184.3 and absf(p.x + 10.0) < 6.0 and p.z > -194.0) if hayburger else home.call("contains", p)
	var t := 0.0; var got_in := -1.0; var next := 0.0
	var leg := 0; var at := route[0]
	while t < float(_arg("--seconds", "90")):
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time(); t += dt
		if leg < route.size() - 1:
			at = at.move_toward(route[leg + 1], dt * 1.0)
			if at.distance_to(route[leg + 1]) < 0.05: leg += 1
			player.global_position = at + Vector3.UP * 0.1
		if got_in < 0.0 and in_room.call(actor.global_position): got_in = t
		if t >= next:
			next += 3.0
			var nav: Node = actor.get_node("Navigator")
			print("FOLLOWIN %3.0fs player %s pony %s inside %s state %s reason '%s' | %s" % [t, player.global_position.snapped(Vector3.ONE * 0.1), actor.global_position.snapped(Vector3.ONE * 0.1), in_room.call(actor.global_position), nav.get("state"), nav.get("reason"), report])
		if got_in >= 0.0 and t > got_in + 5.0: break
	print("FOLLOWIN result %s %s scale %s: %s" % [home_id, id, _arg("--scale", "1.0"), ("INSIDE after %.1f s (player in at about %.0f s)" % [got_in, (route[0].distance_to(route[1]) + route[1].distance_to(route[2]))]) if got_in >= 0.0 else "NOT inside after %.0f s (%s)" % [t, report]])
	get_tree().quit()
