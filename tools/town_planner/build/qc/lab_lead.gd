extends Node
## A pony leading the player somewhere, as the AI's "lead" does (pony_action_executor.gd): --pony id, --from x,z,
## --place location id, --scale body scale. The player keeps 2.5 m behind her. Each second: where she is, her
## navigator's state, the lead's last report, frame rate and physics time. Prints LEAD lines.
var game: Node
var last_report := ""
var _last_reason := ""
func _svc() -> Node:
	var found: Node = null
	for n: Node in get_tree().get_nodes_in_group("pony_navigation"): found = n
	return found
func _ready() -> void:
	_go.call_deferred()

func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	return args[args.find(name) + 1] if name in args else fallback

func _go() -> void:
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	var f := _arg("--from", "77,-207").split(",")
	var start := Vector3(float(f[0]), 0, float(f[1])); start.y = WorldTerrain.instance.height_at(start)
	var player: Node3D = game.get("player")
	player.global_position = start + Vector3(2, 1, 2)
	await get_tree().create_timer(30.0).timeout
	player.global_position = start + Vector3(2, 1, 2)      # (again: skip_to_free_home moved him home)
	await get_tree().create_timer(5.0).timeout
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var executors: Dictionary = (director.get("actions") as Object).get("executors")
	var id := _arg("--pony", "rainbow_dash")
	if not executors.has(id): id = str(executors.keys()[0])
	var executor: Object = executors[id]
	var actor: Node3D = executor.get("actor")
	if actor.has_method("set_body_scale"): actor.call("set_body_scale", float(_arg("--scale", "1.35")))
	if actor.has_method("reset_motion"): actor.call("reset_motion", Transform3D(Basis.IDENTITY, start + Vector3.UP * 0.3))
	await get_tree().create_timer(3.0).timeout
	(executor as Object).connect("outcome", func(event: Dictionary) -> void:
		last_report = "%s: %s" % [event.get("status", ""), event.get("reason", event.get("detail", ""))])
	executor.call("submit", [{"id": "lab_lead", "type": "lead", "target_id": "player", "location_id": _arg("--place", "landmark:burger_joint_01"), "wait_distance_m": 6.0}], {"player": player}, 999999)
	var nav: Node = actor.get_node("Navigator")
	var goal: Vector3 = nav.call("command_location", _arg("--place", "landmark:burger_joint_01"))
	var svc0: Node = null
	for s0: Node in get_tree().get_nodes_in_group("pony_navigation"): svc0 = s0
	print("LEAD goal for %s: %s, walkable %s, closest %s" % [id, goal, svc0.call("is_walkable", goal, actor.get("profile")), svc0.call("closest", goal, actor.get("profile"), 1.0)])
	var t := 0.0
	var next_log := 0.0
	while t < float(_arg("--seconds", "120")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var p := actor.global_position
		var back := -actor.global_basis.z; back.y = 0
		if back.length() > 0.1: player.global_position = p - back.normalized() * 2.5 + Vector3.UP * 0.2
		var r := str(nav.get("reason"))
		if r != _last_reason:
			_last_reason = r
			print("LEAD   %.1fs reason -> %s (request %s, chunks %s)" % [t, r, nav.get("_request"), ((_svc() as Object).get("grid") as Object).get("chunks").size() if _svc() != null else -1])
		if t >= next_log:
			next_log += 1.0
			var v := Vector2(actor.get("velocity").x, actor.get("velocity").z).length()
			var svc: Node = null
			for s: Node in get_tree().get_nodes_in_group("pony_navigation"): svc = s
			var jobs: Variant = svc.get("_jobs") if svc != null else null
			var chunks: Variant = (svc.get("grid") as Object).get("chunks") if svc != null and svc.get("grid") != null else null
			print("LEAD %3.0fs at %s v %.2f state %s reason '%s' request %s path %d journey %s via %d | jobs %s chunks %s | %s | fps %d physics %.1f ms" % [t, p.snapped(Vector3.ONE * 0.01), v, nav.get("state"), nav.get("reason"), nav.get("_request"), (nav.get("path") as PackedVector3Array).size(), (nav.get("_journey_goal") as Vector3).snapped(Vector3.ONE * 0.1), (nav.get("_journey_via") as Array).size(), (jobs as Array).size() if jobs is Array else "?", (chunks as Dictionary).size() if chunks is Dictionary else "?", last_report, Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
		if last_report.begins_with("completed") or last_report.begins_with("failed"): break
	print("LEAD end: ", last_report)
	get_tree().quit()
