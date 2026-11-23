extends Node
## Ponies sent to the town's places as the AI sends them (pony_action_executor.gd go_to): for each id in --places
## (comma separated; "landmark:..." is the outside meeting point, "house:..." the room inside), the player stands at
## the place (the ground's collision is only built round him), the pony (--pony, --scale) starts ~30 m out on street
## ground, and has --seconds to get there. VISIT line per place: arrived (and inside, for a house) or why not, the
## time, how far she was left. Prints VISIT lines.
var _reports: Array[String] = []
var _current := ""

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
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var executors: Dictionary = (director.get("actions") as Object).get("executors")
	var id := _arg("--pony", "twilight_sparkle")
	var executor: Object = executors[id]
	var actor: Node3D = executor.get("actor")
	var nav: Node = actor.get_node("Navigator")
	if actor.has_method("set_body_scale"): actor.call("set_body_scale", float(_arg("--scale", "1.0")))
	executor.connect("outcome", func(event: Dictionary) -> void:
		if str(event.get("id", "")) == _current: _reports.append("%s: %s" % [event.get("status", ""), event.get("reason", "")]))
	var svc: Node = null
	for s: Node in get_tree().get_nodes_in_group("pony_navigation"): svc = s
	var places := preload("res://world/navigation/place_directory.gd")
	var hall := Vector3(135.5, -12.0, -175.9)
	var turn := 1000000
	for place_id: String in _arg("--places", "landmark:burger_joint_01").split(","):
		var entry: Dictionary = places.find(get_tree(), place_id)
		if entry.is_empty(): print("VISIT %s: no such place" % place_id); continue
		var goal: Vector3 = nav.call("command_location", place_id)
		var anchor: Vector3 = goal if goal.is_finite() else entry.position
		player.global_position = anchor + Vector3(1.5, 1.0, 1.5)
		var toward := hall - anchor; toward.y = 0
		if toward.length() < 20.0: toward = Vector3(-60, 0, -40)
		var start_guess := anchor + toward.normalized() * float(_arg("--from-m", "30"))
		start_guess.y = WorldTerrain.instance.height_at(start_guess)
		svc.call("ensure_near", start_guess, 8.0)
		await get_tree().create_timer(4.0).timeout
		var start: Vector3 = svc.call("closest", start_guess, actor.get("profile"), 6.0)
		if not start.is_finite(): start = start_guess
		if actor.has_method("reset_motion"): actor.call("reset_motion", Transform3D(Basis.IDENTITY, start + Vector3.UP * 0.3))
		await get_tree().create_timer(2.0).timeout
		# hers for the test: her day plan paused (it took her back between orders), her navigator free
		var life: Node = game.get("life") as Node
		if is_instance_valid(life) and life.get("core") != null:
			var residents: Dictionary = life.core.state.residents
			if residents.has(id): residents[id]["paused"] = true
		if not str(nav.get("reserved_by")).is_empty(): print("VISIT (her navigator was reserved by %s: freed)" % nav.get("reserved_by"))
		nav.set("reserved_by", "")
		nav.call("stay"); nav.set("command_owner", ""); nav.set("wander_enabled", false)
		_reports.clear()
		turn += 1
		_current = "lab_visit_%d" % turn
		executor.call("submit", [{"id": _current, "type": "go_to", "location_id": place_id, "pace": _arg("--pace", "trot")}], {}, turn)
		var home: Node = entry.get("node") if str(entry.kind) == "house" else null
		var t := 0.0; var done := ""; var inside_at := -1.0
		while t < float(_arg("--seconds", "120")):
			await get_tree().create_timer(0.5).timeout; t += 0.5
			if home != null and home.has_method("contains") and inside_at < 0.0 and home.call("contains", actor.global_position): inside_at = t
			for r: String in _reports:
				if r.begins_with("completed") or r.begins_with("failed") or r.begins_with("cancelled"): done = r
			if not done.is_empty(): break
		goal = nav.call("command_location", place_id)
		var left := Vector2(actor.global_position.x - goal.x, actor.global_position.z - goal.z).length()
		var verdict := done if not done.is_empty() else "still going after %.0f s (state %s, '%s')" % [t, nav.get("state"), nav.get("reason")]
		print("VISIT %s | %s | scale %s | %.0f s | %s | %.1f m from the goal%s" % [place_id, entry.label, _arg("--scale", "1.0"), t, verdict, left,
			("" if home == null else (" | INSIDE after %.0f s" % inside_at if inside_at >= 0.0 else " | NOT inside"))])
		nav.call("stay")
	get_tree().quit()
