extends Node
## Quality control inside the real game (play test 2026-11-16): the Town Square fountain's water and
## ponies drinking from it (world/water/fountain_water.gd, world/life/day/actions/drink_at_fountain.gd).
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --lab res://tools/town_planner/build/qc/lab_agent_b.gd
## (needs a window; set APPDATA to a scratch folder first so the test world stays out of your saves)
## Waits for the world, skips the arrival story, photographs the fountain from eye height and from above,
## checks each drinking spot against a pony's walk grid, then has the two ponies nearest the fountain
## (brought over if far) start the drink step through DayRunner.inject_now, the entry a [use] or a test
## takes into the day cards, and photographs them walking up and drinking. Pictures go to
## tools/town_planner/build/out/lab/agent_b_*.png; everything printed has a LAB prefix; it quits itself.

const OUT := "res://tools/town_planner/build/out/lab"
const PONIES := 2
var game: Node
var cam: Camera3D


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await get_tree().process_frame


func _shot(label: String, eye: Vector3, look: Vector3) -> void:
	cam.look_at_from_position(eye, look, Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT).path_join("agent_b_" + label + ".png"))
	print("LAB SHOT ", label)


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if str(name) != "Lab":
		queue_free(); return
	var watchdog := get_tree().create_timer(900.0)
	watchdog.timeout.connect(func() -> void: print("LAB watchdog: quitting"); get_tree().quit())
	for i in 1200:
		if not is_instance_valid(game) or not ("player" in game):
			var scene := get_tree().current_scene
			game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.5)
	if not is_instance_valid(game):
		print("LAB no game scene; giving up"); get_tree().quit(); return
	var player: Node3D = game.get("player")
	var arrival: Variant = game.get("arrival")
	if arrival is Node and is_instance_valid(arrival) and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
		await _wait(3.0)
	var tod := get_node_or_null("/root/TimeOfDay")
	if tod != null:
		tod.hours = 11.0; tod.paused = true
	var water := get_tree().get_first_node_in_group("town_fountains") as Node3D
	if water == null:
		print("LAB FAIL no fountain water in the town"); get_tree().quit(); return
	var c := water.global_position
	print("LAB fountain water at ", c, " surface y ", water.to_global(Vector3(0, water.WATER_Y, 0)).y, " ice ", water.ice, " frozen ", water.frozen, " iced ", water.iced())
	var world_water: Node = WorldWater.instance
	print("LAB material registered with WorldWater: ", world_water != null and world_water.water_materials.has(water.material))
	player.global_position = c + Vector3(9.0, 0.5, 9.0)
	if "velocity" in player: player.set("velocity", Vector3.ZERO)
	cam = Camera3D.new(); cam.name = "LabCamera"; cam.far = 4000.0; cam.fov = 60.0
	game.add_child(cam)
	await _wait(45.0)
	var ground: float = WorldTerrain.instance.height_at(c + Vector3(6, 0, 4))
	await _shot("eye", Vector3(c.x + 6.0, ground + 1.7, c.z + 4.0), c + Vector3(0, 0.9, 0))
	await _shot("eye_close", Vector3(c.x + 3.9, ground + 1.6, c.z + 1.2), c + Vector3(0, 0.85, 0))
	await _shot("above", c + Vector3(0.0, 11.0, 0.5), c + Vector3(0, 0.9, 0))

	# The ponies: the nearest first, brought within 14 m if farther.
	var population: Node = game.get("population")
	var runner: Node = get_tree().get_first_node_in_group("day_runner")
	if population == null or runner == null:
		print("LAB FAIL population ", population, " runner ", runner); get_tree().quit(); return
	var ids: Array = []
	for id: String in population.live:
		var body: Node3D = population.live[id].get("actor")
		if is_instance_valid(body) and body.is_inside_tree() and body.get_node_or_null("Navigator") != null: ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return (population.live[a].actor as Node3D).global_position.distance_to(c) < (population.live[b].actor as Node3D).global_position.distance_to(c))
	print("LAB live ponies: ", ids.size(), " nearest: ", ids.slice(0, 6))
	var chosen: Array = []
	for id: String in ids:
		if chosen.size() >= PONIES: break
		if not runner.can_inject(id, true): print("LAB skip ", id, ": runner says not free"); continue
		chosen.append(id)
	if chosen.is_empty():
		print("LAB FAIL no free pony"); get_tree().quit(); return
	# The spots against the first pony's walk grid.
	var nav0: Node = (population.live[chosen[0]].actor as Node3D).get_node("Navigator")
	var spots: Array = water.drink_spots()
	for i: int in spots.size():
		var a: Vector3 = spots[i].approach
		var w: Vector3 = nav0.command_support(a)
		print("LAB SPOT %d approach %s walkable %s off %.2f m, %.2f m from centre" % [i, a, w, Vector2(w.x - a.x, w.z - a.z).length() if w.is_finite() else INF, Vector2(a.x - c.x, a.z - c.z).length()])
	var k := 0
	for id: String in chosen:
		var body: Node3D = population.live[id].actor
		if body.global_position.distance_to(c) > 60.0:
			var nav: Node = body.get_node("Navigator")
			nav.stay()
			var at: Vector3 = nav.command_support(c + Vector3(-10.0 + 4.0 * k, 0.0, 8.0))
			if not at.is_finite(): print("LAB no ground to bring ", id, " to"); continue
			body.global_position = at + Vector3(0, 0.1, 0)
			if "velocity" in body: body.set("velocity", Vector3.ZERO)
			print("LAB brought ", id, " to ", at)
		k += 1
	await _wait(4.0)
	var step := {"action": "drink_fountain", "handler": "drink_at_fountain", "target": "landmark:fountain_01",
		"phrase": "have a drink at the {target}", "reason": "for the lab", "minutes": 4.0, "hours": 1.0}
	for id: String in chosen:
		print("LAB inject ", id, ": ", runner.inject_now(id, step))
	# Follow them: phases, pictures while walking and drinking.
	var seen: Dictionary = {}
	var walked: Dictionary = {}
	var drank: Dictionary = {}
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 150000:
		await _wait(0.25)
		var all_done := true
		for id: String in chosen:
			var card: Dictionary = runner.cards.get(id, {})
			var action: RefCounted = card.get("action")
			var body: Node3D = population.live.get(id, {}).get("actor")
			var phase := "none"
			if action != null and action.get_script() != null and str(action.get_script().resource_path).ends_with("drink_at_fountain.gd"):
				phase = str(action.get("_phase"))
			elif seen.has(id):
				phase = "ended"
			if phase != str(seen.get(id, "")):
				var extra := ""
				if action != null and action.get("reason") != null: extra = " reason '%s'" % action.get("reason")
				if is_instance_valid(body):
					var aff0: Node = body.get_node_or_null("Affection")
					var m0: Vector3 = aff0.mouth_point() if aff0 != null and aff0.has_method("mouth_point") else Vector3.INF
					extra += "; %.2f m from the centre, mouth %s (%.2f above her feet)" % [Vector2(body.global_position.x - c.x, body.global_position.z - c.z).length(), m0, m0.y - body.global_position.y]
				print("LAB PHASE %s %s at %.1f s, at %s, nav state %s%s" % [id, phase, (Time.get_ticks_msec() - started) / 1000.0, body.global_position if is_instance_valid(body) else Vector3.INF, body.get_node("Navigator").state if is_instance_valid(body) else -1, extra])
				if phase == "ended":
					print("LAB card index now ", card.get("index"), "; step ", (card.steps[int(card.index) - 1] as Dictionary).get("handler") if int(card.get("index", 0)) > 0 else "")
				seen[id] = phase
			if phase in ["travel", "align", "drink", "lift"] or (phase == "none" and Time.get_ticks_msec() - started < 20000): all_done = false
			if not is_instance_valid(body): continue
			if phase == "travel" and not walked.has(id) and body.global_position.distance_to(c) < 9.0:
				walked[id] = true
				var gb: float = WorldTerrain.instance.height_at(body.global_position)
				await _shot("walk_" + id, body.global_position + Vector3(3.0, 0.0, 3.0) + Vector3(0, gb - body.global_position.y + 1.6, 0), body.global_position + Vector3(0, 0.6, 0))
			if phase == "drink" and action.get("_phase_seconds") > 2.4 and not drank.has(id):
				drank[id] = true
				var spot: Dictionary = action.get("_spot")
				var out: Vector3 = (body.global_position - c); out.y = 0.0; out = out.normalized()
				var side := Vector3(-out.z, 0.0, out.x)
				var mouth := Vector3.INF
				var aff: Node = body.get_node_or_null("Affection")
				if aff != null and aff.has_method("mouth_point"): mouth = aff.mouth_point()
				var pose: RefCounted = body.get("activity_mouth_pose")
				print("LAB DRINK %s: stands %.2f m from the centre, mouth %s, sip point %s, mouth to sip %.2f m, pose gap %s amount %s, sipper %s" % [id,
					Vector2(body.global_position.x - c.x, body.global_position.z - c.z).length(), mouth, spot.sip,
					mouth.distance_to(spot.sip) if mouth.is_finite() else INF, pose.get("gap") if pose != null else "none", pose.get("amount") if pose != null else "none",
					body.get_node_or_null("FountainSip") != null])
				var look: Vector3 = spot.sip.lerp(body.global_position + Vector3(0, 0.6, 0), 0.4)
				await _shot("drink_side_" + id, look + side * 2.3 + Vector3(0, 0.35, 0), look)
				await _shot("drink_front_" + id, look - out * 2.6 + Vector3(0, 1.0, 0), look)
				await _wait(1.1)
				await _shot("drink_sip_" + id, look + side * 2.3 + Vector3(0, 0.35, 0), look)
		if all_done and seen.size() == chosen.size(): break
	await _wait(2.0)
	for id: String in chosen:
		var body: Node3D = population.live.get(id, {}).get("actor")
		if is_instance_valid(body):
			print("LAB AFTER %s: owner '%s', mouth pose %s, intent '%s'" % [id, body.get_node("Navigator").command_owner, body.get("activity_mouth_pose"), body.get_meta("life_intent", "")])
	print("LAB done: walked ", walked.keys(), " drank ", drank.keys())
	get_tree().quit()
