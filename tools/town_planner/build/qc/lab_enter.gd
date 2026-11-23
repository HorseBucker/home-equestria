extends Node
## Whether ponies get into buildings on their own (2026-11-23 play test: "difficult if not impossible to get ponies to
## go into places like Hayburger, the boutique"): --mode hayburger (a day visit through the restaurant's own customer
## path, hayburger_customers.gd request_day_visit, from its front) or --mode boutique (the AI's go_to to
## house:carousel_boutique, from 20 m out). --pony id, --scale. Each second where she is and whether she is inside;
## ENTER result line with the seconds it took. Prints ENTER lines.
var _reports: Array[String] = []
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
	var mode := _arg("--mode", "hayburger")
	var start := Vector3(-1.0, 0, -192.0) if mode == "hayburger" else Vector3(112.0, 0, -78.0)
	if "--from" in OS.get_cmdline_user_args():
		var f := _arg("--from", "").split(","); start = Vector3(float(f[0]), 0, float(f[1]))
	start.y = WorldTerrain.instance.height_at(start)
	var player: Node3D = game.get("player")
	player.global_position = start + Vector3(3, 1, 3)
	await get_tree().create_timer(30.0).timeout
	# (skip_to_free_home moves the player to a home after the first placing: place again, the ground's collision is
	# only built round him)
	player.global_position = start + Vector3(3, 1, 3)
	await get_tree().create_timer(8.0).timeout
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var executors: Dictionary = (director.get("actions") as Object).get("executors")
	var id := _arg("--pony", "rainbow_dash")
	var executor: Object = executors[id]
	var actor: Node3D = executor.get("actor")
	var nav: Node = actor.get_node("Navigator")
	if actor.has_method("set_body_scale"): actor.call("set_body_scale", float(_arg("--scale", "1.0")))
	if actor.has_method("reset_motion"): actor.call("reset_motion", Transform3D(Basis.IDENTITY, start + Vector3.UP * 0.3))
	await get_tree().create_timer(3.0).timeout
	var inside := func() -> bool: return false
	var report := ""
	if mode == "hayburger":
		var customers: Node = get_tree().get_first_node_in_group("hayburger_customers")
		nav.set("command_owner", "day:" + id)
		for attempt in 24:
			report = str(customers.call("request_day_visit", id, actor, "day:" + id, 60.0))
			print("ENTER request %d: '%s'" % [attempt, report])
			if report.is_empty() or report == "cooldown": break
			await get_tree().create_timer(5.0).timeout
		inside = func() -> bool: return str(customers.call("visit_phase", id)) in ["eating", "rising", "seated", "sitting"]
		if not report.is_empty(): print("ENTER result %s %s: refused (%s)" % [mode, id, report]); get_tree().quit(); return
	else:
		var home: Node = null
		for e: Dictionary in preload("res://world/navigation/place_directory.gd").entries(get_tree()):
			if e.id == "house:carousel_boutique": home = e.node
		inside = func() -> bool: return home.call("contains", actor.global_position)
		var svc: Node = null
		for s0: Node in get_tree().get_nodes_in_group("pony_navigation"): svc = s0
		var out_at: Vector3 = home.call("outside")
		print("ENTER boutique outside() %s walkable %s closest %s; inside() %s" % [out_at.snapped(Vector3.ONE * 0.01), svc.call("is_walkable", out_at, actor.get("profile")), (svc.call("closest", out_at, actor.get("profile"), 1.0) as Vector3).snapped(Vector3.ONE * 0.01), (home.call("inside") as Vector3).snapped(Vector3.ONE * 0.01)])
		executor.connect("outcome", func(event: Dictionary) -> void: _reports.append("%s: %s" % [event.get("status", ""), event.get("reason", "")]))
		executor.call("submit", [{"id": "lab_enter", "type": "go_to", "location_id": "house:carousel_boutique"}], {}, 999999)
	var t := 0.0; var next := 0.0; var phase := ""
	var got_in := -1.0
	while t < float(_arg("--seconds", "120")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if got_in < 0.0 and inside.call(): got_in = t
		if mode == "hayburger":
			var ph := str(get_tree().get_first_node_in_group("hayburger_customers").call("visit_phase", id))
			if ph != phase: phase = ph; print("ENTER   %.1fs phase %s at %s" % [t, ph, actor.global_position.snapped(Vector3.ONE * 0.01)])
			if got_in >= 0.0: break
		if t >= next:
			next += 2.0
			print("ENTER   %3.0fs at %s state %s reason '%s' inside %s | %s" % [t, actor.global_position.snapped(Vector3.ONE * 0.01), nav.get("state"), nav.get("reason"), inside.call(), report if not report.is_empty() else (_reports[-1] if not _reports.is_empty() else "")])
		if mode == "boutique" and (report.begins_with("completed") or report.begins_with("failed")) and t > 1.0: break
	print("ENTER result %s %s scale %s: %s after %.1f s (%s)" % [mode, id, _arg("--scale", "1.0"), "INSIDE" if got_in >= 0.0 or inside.call() else "NOT inside", got_in if got_in >= 0.0 else t, report if not report.is_empty() else ", ".join(_reports)])
	get_tree().quit()
