extends Node
## Quality control inside the real game (play test 2026-11-17): Cherry Berry giving Anon a balloon
## ride when asked ([use: balloon_ride] through mechanics.gd), and a pony Anon carries into the
## basket staying aboard (balloon.gd, modChad's Balloon Boarding folded in).
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/lab_agent_e2.gd
## Pictures: tools/town_planner/build/out/lab/agent_e2_*.png; output lines start "LAB"; quits itself.

const OUT := "res://tools/town_planner/build/out/lab"
const ID := "cherry_berry"
var game: Node
var cam: Camera3D
var ship: CharacterBody3D
var population: Node


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		# The pause menu opens after a spell without input (pause_menu.gd _check_idle): keep it shut.
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused:
			get_tree().paused = false
			var menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
			if is_instance_valid(menu) and (menu as Object).has_method("close"): menu.call("close")
		await get_tree().process_frame


func _shot(label: String, eye: Vector3, look: Vector3) -> void:
	var before: Camera3D = get_viewport().get_camera_3d()
	get_tree().paused = false
	cam.look_at_from_position(eye, look, Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT).path_join("agent_e2_" + label + ".png"))
	print("LAB SHOT ", label, " paused ", get_tree().paused)
	if is_instance_valid(before) and before != cam: before.make_current()


func _put_player(local: Vector3) -> void:
	var body: Node3D = game.inventory.player_body
	body.global_position = ship.to_global(local)
	if "velocity" in body: body.set("velocity", Vector3.ZERO)


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if str(name) != "Lab":
		queue_free(); return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var watchdog := get_tree().create_timer(1200.0)
	watchdog.timeout.connect(func() -> void: print("LAB watchdog: quitting"); get_tree().quit())
	for i in 1200:
		if not is_instance_valid(game) or not ("player" in game):
			var scene := get_tree().current_scene
			game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.5)
	if not is_instance_valid(game):
		print("LAB no game scene"); get_tree().quit(); return
	var arrival: Variant = game.get("arrival")
	if arrival is Node and is_instance_valid(arrival) and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
		await _wait(3.0)
	var tod := get_node_or_null("/root/TimeOfDay")
	tod.hours = 10.0   # outside her afternoon step window: a ride works any daylight hour
	ship = game.get("balloon") as CharacterBody3D
	population = game.get("population")
	cam = Camera3D.new(); cam.name = "LabCamera"; cam.far = 4000.0; cam.fov = 60.0
	game.add_child(cam)
	_put_player(Vector3(5.0, 0.5, -9.0))
	await _wait(40.0)
	var her: Node3D = population.live.get(ID, {}).get("actor")
	var mech: Node = get_tree().get_first_node_in_group("mechanics")
	if not is_instance_valid(her) or mech == null:
		print("LAB FAIL her ", her, " mechanics ", mech); get_tree().quit(); return
	var fly: Script = load("res://world/life/day/actions/fly_balloon.gd")
	# The refusals she would be told.
	print("LAB refusal at 10:00 clear: '", fly.call("ride_refusal", get_tree(), ID), "'")
	var weather: Node = get_tree().get_first_node_in_group("weather")
	var kind: String = weather.kind
	weather.kind = "storm"
	print("LAB refusal in a storm: '", fly.call("ride_refusal", get_tree(), ID), "'")
	weather.kind = kind
	mech.call("invalidate", ID)
	var row: Dictionary = mech.call("_ai_row", ID, her)
	print("LAB caps ", row.caps, " stations ", row.keys.get("stations"))
	for line: Variant in row.lines: print("LAB line ", line)
	# Carried in: the nearest other pony, held over the basket and set down, Anon beside it (not aboard).
	_put_player(Vector3(3.0, 0.5, -4.5))
	await _wait(3.0)
	var other: Node3D = null
	var best := INF
	for id: String in population.live:
		var body: Node3D = population.live[id].get("actor")
		if id == ID or id == "spike" or not is_instance_valid(body) or body.get("sleeping") == true: continue
		var d := body.global_position.distance_to(ship.global_position)
		if d < best: best = d; other = body
	if other == null: print("LAB no other pony"); get_tree().quit(); return
	print("LAB carried test with ", other.name, " from %.0f m" % best)
	# Carried the way the grabber does it (pony_hold_api.gd): picked up beside the basket, carried
	# over its wall from outside, let go over the deck with Anon's head outside the wall.
	var head := ship.to_global(Vector3(2.3, 1.7, 0.55))
	# Brought beside the basket first, as Anon would walk her over.
	other.reset_motion(Transform3D(other.global_basis, ship.to_global(Vector3(3.2, 0.1, 0.55))))
	await _wait(1.0)
	var from := other.global_position
	other.begin_hold(other.global_position + Vector3.UP * 0.3)
	for i in 60:
		var target := from.lerp(ship.to_global(Vector3(-0.3, 1.3, 0.55)), minf(1.0, float(i + 1) / 40.0))
		other.update_grab(target + Vector3.UP * 0.4, head)
		await _wait(0.05)
	await _wait(0.6)
	other.call("end_interaction")
	await _wait(0.5)
	print("LAB released: in basket %s local %s held %s" % [ship.contains(other.global_position, 0.3), ship.to_local(other.global_position), other.get("_held")])
	var aboard := false
	for r: Dictionary in ship.passengers: aboard = aboard or r.actor == other
	print("LAB carried: aboard %s, in basket %s, meta %s" % [aboard, ship.contains(other.global_position), other.has_meta("balloon_passenger")])
	await _shot("carried", ship.to_global(Vector3(2.2, 3.2, -3.4)), ship.global_position + Vector3.UP * 0.6)
	await _wait(8.0)
	aboard = false
	for r: Dictionary in ship.passengers: aboard = aboard or r.actor == other
	print("LAB carried after 12 s with Anon beside: aboard %s" % aboard)
	_put_player(Vector3(14.0, 0.5, -18.0))
	await _wait(6.0)
	aboard = false
	for r: Dictionary in ship.passengers: aboard = aboard or r.actor == other
	print("LAB carried after Anon walked off: aboard %s, in basket %s, at %s" % [aboard, ship.contains(other.global_position), other.global_position])
	print("LAB done"); get_tree().quit()
