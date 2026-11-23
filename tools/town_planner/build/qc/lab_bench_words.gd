extends Node
## A pony by the fountain's benches: what she is told about a seat near her, then sat on one (at --scale, default 1.35)
## and what she is told then (pony_awareness.gd rest_words / seat_near). Prints SEAT lines; quits.
const AWARE := preload("res://world/ai/pony_awareness.gd")
var game: Node

func _ready() -> void:
	_go.call_deferred()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _go() -> void:
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.25)
	var water := get_tree().get_first_node_in_group("town_fountains") as Node3D
	var fountain := water.get_parent() as Node3D
	game.get("player").global_position = fountain.global_position + Vector3(10.0, 0.5, 8.0)
	await _wait(25.0)
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var executors: Dictionary = (director.get("actions") as Object).get("executors")
	var id := "lyra_heartstrings" if executors.has("lyra_heartstrings") else str(executors.keys()[0])
	var actor: Node3D = executors[id].get("actor")
	var scale := float(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--scale") + 1]) if "--scale" in OS.get_cmdline_user_args() else 1.35
	print("SEAT %s body_scale before %s" % [id, actor.get("body_scale")])
	if actor.has_method("set_body_scale"): actor.call("set_body_scale", scale)
	elif actor.get("body_scale") != null: actor.set("body_scale", scale)
	var spot := fountain.global_position + Vector3(-9.0, 0, -1.0)
	var lyras: Node3D = null
	if "--lyras" in OS.get_cmdline_user_args():
		for seat: Node in get_tree().get_nodes_in_group("pony_seats"):
			if str(seat.get_parent().name).to_lower().begins_with("lyrasbench"): lyras = seat; break
		print("SEAT lyra's bench seat: ", lyras.global_position if lyras else "none")
		if lyras != null:
			spot = lyras.global_position - lyras.global_basis.z * 1.6
			game.get("player").global_position = lyras.global_position - lyras.global_basis.z * 5.0 + Vector3.UP * 0.5
			await _wait(4.0)
	if actor.has_method("reset_motion"): actor.call("reset_motion", Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.2))
	await _wait(3.0)
	var nav: Node = actor.get_node("Navigator"); nav.set("command_owner", "lab")
	print("SEAT standing: rest '%s', seat near '%s'" % [AWARE.rest_words(actor), AWARE.seat_near(actor)])
	var seating: Node = get_tree().get_first_node_in_group("pony_seating")
	print("SEAT sit -> ", seating.call("sit", actor, 30.0, lyras))
	for i in 40:
		await _wait(1.0)
		if i % 5 == 4 or str(seating.call("phase", actor)) == "seated":
			print("SEAT %2ds phase %s: rest '%s'" % [i + 1, seating.call("phase", actor), AWARE.rest_words(actor)])
			if str(seating.call("phase", actor)) == "seated" and str(actor.posture_status().kind) == "sit":
				await _wait(2.0)
				var shots := OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--shots") + 1] if "--shots" in OS.get_cmdline_user_args() else ""
				if not shots.is_empty():
					var seat_node: Node3D = seating.call("seat_of", actor)
					var cam := Camera3D.new(); get_tree().current_scene.add_child(cam)
					var side: Vector3 = seat_node.global_basis.x.normalized()
					var scale_s := float(actor.get("body_scale"))
					cam.global_position = actor.global_position + side * 2.6 * scale_s + Vector3.UP * 0.9 * scale_s
					cam.look_at(actor.global_position + Vector3.UP * 0.7 * scale_s, Vector3.UP); cam.fov = 50.0; cam.make_current()
					await _wait(0.3)
					get_viewport().get_texture().get_image().save_png(shots.path_join("bench_%s.png" % str(scale_s)))
				break
	get_tree().quit()
