extends Node
## Quality control inside the real game (play test 2026-11-16): how far a standing pony's muzzle reaches
## through the mouth-reach pose (world/minigames/apple_bucking/gather_mouth_pose.gd), for the fountain drink.
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --lab res://tools/town_planner/build/qc/lab_agent_b_reach.gd
## Takes the nearest free pony, stands her on open ground, and asks the pose for targets ahead of her
## (forward x height above her feet); prints where the mouth got to and saves a side picture of a few.

const OUT := "res://tools/town_planner/build/out/lab"
const GATHER := preload("res://world/minigames/apple_bucking/gather_mouth_pose.gd")
var game: Node


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await get_tree().process_frame


func _go() -> void:
	if str(name) != "Lab":
		queue_free(); return
	get_tree().create_timer(700.0).timeout.connect(func() -> void: print("LAB watchdog"); get_tree().quit())
	for i in 1200:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.5)
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
	var tod := get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.hours = 11.0; tod.paused = true
	var water := get_tree().get_first_node_in_group("town_fountains") as Node3D
	var c := water.global_position
	var player: Node3D = game.get("player")
	player.global_position = c + Vector3(9.0, 0.5, 9.0)
	await _wait(45.0)
	var population: Node = game.get("population")
	var runner: Node = get_tree().get_first_node_in_group("day_runner")
	var body: Node3D = null
	var best := INF
	for id: String in population.live:
		var b: Node3D = population.live[id].get("actor")
		if not is_instance_valid(b) or b.get("neck_link") == null or not runner.can_inject(id, true): continue
		var d := b.global_position.distance_to(c)
		if d < best: best = d; body = b
	if body == null: print("LAB no pony"); get_tree().quit(); return
	var nav: Node = body.get_node("Navigator")
	nav.stay()
	nav.command_owner = "lab:reach"
	nav.wander_enabled = false
	var stand: Vector3 = nav.command_support(c + Vector3(-9.0, 0.0, 0.0))
	body.global_position = stand + Vector3(0, 0.05, 0)
	nav.face_point = stand + Vector3(-5.0, 0.0, 0.0)
	await _wait(4.0)
	nav.face_point = Vector3.INF
	if body.has_method("face_direction"): body.face_direction(Vector3.ZERO)
	var pose: RefCounted = GATHER.new()
	pose.set("actor", body)
	body.set("activity_mouth_pose", pose)
	var aff: Node = body.get_node("Affection")
	var feet := body.global_position
	var fwd: Vector3 = -body.global_basis.z; fwd.y = 0.0; fwd = fwd.normalized()
	var m0: Vector3 = aff.mouth_point()
	print("LAB pony %s scale %s; rest mouth %.2f ahead, %.2f up" % [body.name, body.get("body_scale"), (m0 - feet).dot(fwd), m0.y - feet.y])
	var cam := Camera3D.new(); cam.fov = 50.0; game.add_child(cam)
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	for h: float in [0.55, 0.75, 0.95, 1.1]:
		for f: float in [0.5, 0.7, 0.9, 1.1]:
			var goal := feet + fwd * f + Vector3.UP * h
			var t := 0.0
			while t < 1.4:
				pose.call("reach_to", goal, "lab:reach")
				await get_tree().physics_frame
				t += get_physics_process_delta_time()
			var m: Vector3 = aff.mouth_point()
			print("LAB REACH target %.2f ahead %.2f up -> mouth %.2f ahead %.2f up, gap %.2f, amount %.2f crouch %.2f" % [f, h, (m - feet).dot(fwd), m.y - feet.y, m.distance_to(goal), pose.get("amount"), pose.get("crouch_amount")])
			if (h == 0.95 and f == 0.9) or (h == 0.75 and f == 0.7) or (h == 1.1 and f == 1.1):
				cam.look_at_from_position(feet + fwd * 0.4 + side * 2.4 + Vector3.UP * 0.7, feet + fwd * 0.4 + Vector3.UP * 0.6, Vector3.UP)
				cam.make_current()
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT).path_join("agent_b_reach_%d_%d.png" % [int(f * 100), int(h * 100)]))
	pose.call("release", "lab:reach")
	print("LAB done")
	get_tree().quit()
