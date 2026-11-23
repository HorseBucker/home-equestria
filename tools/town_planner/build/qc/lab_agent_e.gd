extends Node
## Quality control inside the real game (play test 2026-11-16): Cherry Berry flying Ponyville's
## hot-air balloon (world/life/day/actions/fly_balloon.gd, world/vehicles/balloon/pony_pilot.gd).
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/lab_agent_e.gd
## (needs a window; set APPDATA to a scratch folder first). Skips the arrival story, puts the player
## in the balloon's basket, starts her flight step through DayRunner.inject_now and follows it to the
## landing: positions, the greatest distance from the Town Hall, the least clearance, the activity
## text the dialogue gets, a save snapshot taken mid-flight; then a second flight cut short by her
## bedtime. Pictures: tools/town_planner/build/out/lab/agent_e_*.png; output lines start "LAB"; quits.

const OUT := "res://tools/town_planner/build/out/lab"
const TOWN: Vector3 = preload("res://world/audio/soundscape.gd").TOWN
const ID := "cherry_berry"
var game: Node
var cam: Camera3D
var ship: CharacterBody3D
var runner: Node
var population: Node


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await get_tree().process_frame


func _shot(label: String, eye: Vector3, look: Vector3) -> void:
	var before: Camera3D = get_viewport().get_camera_3d()
	cam.look_at_from_position(eye, look, Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT).path_join("agent_e_" + label + ".png"))
	print("LAB SHOT ", label)
	if is_instance_valid(before) and before != cam: before.make_current()


func _cherry() -> Node3D:
	return population.live.get(ID, {}).get("actor") if population != null else null


func _activity(tag: String) -> void:
	var her := _cherry()
	if not is_instance_valid(her): print("LAB TEXT ", tag, ": no body"); return
	print("LAB TEXT ", tag, " life_intent: ", her.get_meta("life_intent", "<none>"))
	print("LAB TEXT ", tag, " day_plan: ", her.get_meta("day_plan", "<none>"))
	var director: Node = game.get("director")
	if is_instance_valid(director) and director.get("characters") is Dictionary and (director.characters as Dictionary).has(ID):
		var block: String = director.situation_block(ID)
		for line: String in block.split("\n"):
			if line.contains("balloon") or line.contains("activity") or line.contains("plans") or line.contains("Where you stand"): print("LAB TEXT ", tag, " | ", line)
	else:
		print("LAB TEXT ", tag, ": director has no character entry")


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if str(name) != "Lab":
		queue_free(); return
	var watchdog := get_tree().create_timer(1700.0)
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
	tod.hours = 13.0
	ship = game.get("balloon") as CharacterBody3D
	population = game.get("population")
	runner = get_tree().get_first_node_in_group("day_runner")
	if ship == null or population == null or runner == null:
		print("LAB FAIL balloon ", ship, " population ", population, " runner ", runner); get_tree().quit(); return
	var weather: Node = get_tree().get_first_node_in_group("weather")
	print("LAB weather ", weather.get("kind") if weather != null else "none")
	print("LAB balloon at ", ship.global_position, " home ", ship.home.origin, " landed ", ship.landed, " %.0f m from the Town Hall" % Vector2(ship.global_position.x - TOWN.x, ship.global_position.z - TOWN.z).length())
	cam = Camera3D.new(); cam.name = "LabCamera"; cam.far = 4000.0; cam.fov = 60.0
	game.add_child(cam)
	player.global_position = ship.to_global(Vector3(4.0, 0.5, -6.0))
	if "velocity" in player: player.set("velocity", Vector3.ZERO)
	await _wait(40.0)
	var her := _cherry()
	if not is_instance_valid(her):
		print("LAB Cherry Berry not live; assignments ", population.config.assignments.get(ID, "?")); get_tree().quit(); return
	print("LAB Cherry at ", her.global_position, " %.1f m from the balloon" % her.global_position.distance_to(ship.global_position))
	# Brought near if far, so the walk is short.
	if her.global_position.distance_to(ship.global_position) > 50.0:
		var nav: Node = her.get_node("Navigator")
		nav.stay()
		var at: Vector3 = nav.command_support(ship.to_global(Vector3(8.0, 0.0, -10.0)))
		if at.is_finite():
			her.global_position = at + Vector3.UP * 0.1
			print("LAB brought her to ", at)
		await _wait(3.0)
	_activity("before")
	await _shot("pad", ship.to_global(Vector3(9.0, 2.5, -12.0)), ship.global_position + Vector3.UP * 3.0)
	# The player in the basket: he rides along.
	player.global_position = ship.to_global(Vector3(0.75, 0.4, -0.45))
	if "velocity" in player: player.set("velocity", Vector3.ZERO)
	await _wait(1.5)
	print("LAB player aboard: ", ship.holds_player(game.inventory.player_body))
	var step := {"action": "balloon_flight", "handler": "fly_balloon", "target": "landmark:airballoon_01",
		"phrase": "take Ponyville's hot-air balloon up for a flight over the town", "reason": "for the lab", "minutes": 60.0, "hours": 3.0}
	print("LAB can_inject ", runner.can_inject(ID, true), " inject ", runner.inject_now(ID, step))
	await _follow("one", true, 900.0)
	print("LAB player aboard after landing: ", ship.holds_player(game.inventory.player_body), " at ", game.inventory.player_body.global_position)
	await _wait(6.0)
	_activity("after")
	her = _cherry()
	if is_instance_valid(her):
		await _shot("after", her.global_position + Vector3(4.0, 2.0, -5.0), her.global_position + Vector3.UP * 0.8)
	# Second flight without the player, cut short by bedtime once up.
	player.global_position = ship.to_global(Vector3(12.0, 0.5, -14.0))
	await _wait(10.0)
	print("LAB second: can_inject ", runner.can_inject(ID, true), " inject ", runner.inject_now(ID, step))
	await _follow("two", false, 600.0)
	print("LAB done"); get_tree().quit()


## Follows the flight until the step ends. `bedtime_cut`: false sets the clock to her turn-home hour
## once she is cruising.
func _follow(tag: String, with_player: bool, limit: float) -> void:
	var pilot: Node = ship.get_node_or_null("PonyPilot")
	var last_state := "?"
	var started := Time.get_ticks_msec()
	var log_left := 0.0
	var saved := false
	var cut := false
	var shots: Dictionary = {}
	var min_basket_gap := INF
	while Time.get_ticks_msec() - started < limit * 1000.0:
		await _wait(0.5)
		if pilot == null: pilot = ship.get_node_or_null("PonyPilot")
		var card: Dictionary = runner.cards.get(ID, {})
		var action: RefCounted = card.get("action")
		var phase := str(action.get("_phase")) if action != null and str(action.get_script().resource_path).ends_with("fly_balloon.gd") else "none"
		var state := str(pilot.get("state")) if pilot != null else ""
		var her := _cherry()
		var t := (Time.get_ticks_msec() - started) / 1000.0
		var key := phase + "/" + state
		if key != last_state:
			print("LAB %s PHASE %s at %.1f s; her %s; balloon %s; reason '%s'" % [tag, key, t, her.global_position if is_instance_valid(her) else Vector3.INF, ship.global_position, action.get("reason") if action != null else ""])
			last_state = key
			_activity(tag + ":" + key)
		if is_instance_valid(her) and pilot != null and state in ["preflight", "climb", "cruise", "return", "descend"]:
			var local := ship.to_local(her.global_position)
			min_basket_gap = minf(min_basket_gap, local.y)
			if not ship.contains(her.global_position, 0.1): print("LAB WARN %s she is not in the basket: local %s" % [tag, local])
		log_left -= 0.5
		if log_left <= 0.0 and pilot != null and pilot.call("away"):
			log_left = 5.0
			var g: float = WorldTerrain.instance.height_at(ship.global_position)
			print("LAB %s FLY t %.0f state %s at %s, %.0f m from the Town Hall, %.1f m above the ground, speed %.1f, her local %s, where '%s'" % [tag, t, state, ship.global_position, Vector2(ship.global_position.x - TOWN.x, ship.global_position.z - TOWN.z).length(), ship.global_position.y - g, ship.velocity.length(), ship.to_local(her.global_position) if is_instance_valid(her) else Vector3.INF, pilot.call("_where_now")])
		# Pictures at each stage.
		var stage := phase if phase in ["travel", "check", "ramp"] else state
		if not shots.has(stage) and stage in ["check", "ramp", "preflight", "climb", "cruise", "return", "descend", "landed"]:
			shots[stage] = true
			var at := ship.global_position
			if stage in ["check", "ramp", "preflight", "landed"]:
				await _shot(tag + "_" + stage, ship.to_global(Vector3(6.0, 3.0, -9.0)), at + Vector3.UP * 1.0)
				await _shot(tag + "_" + stage + "_close", ship.to_global(Vector3(2.2, 3.2, -2.8)), at + Vector3.UP * 0.6)
			else:
				var g2: float = WorldTerrain.instance.height_at(at)
				await _shot(tag + "_" + stage + "_ground", Vector3(at.x + 30.0, g2 + 2.0, at.z + 30.0), at + Vector3.UP * 4.0)
				await _shot(tag + "_" + stage + "_near", ship.to_global(Vector3(3.5, 3.5, -4.5)), at + Vector3.UP * 0.7)
		if state == "cruise" and not shots.has("cruise_late") and pilot.get("route_index") >= 2:
			shots["cruise_late"] = true
			await _shot(tag + "_cruise_late_near", ship.to_global(Vector3(3.5, 3.5, -4.5)), ship.global_position + Vector3.UP * 0.7)
			await _shot(tag + "_cruise_late_wide", ship.global_position + Vector3(-60.0, 25.0, -60.0), ship.global_position)
		if with_player and state == "cruise" and not saved and t > 70.0:
			saved = true
			var doc: Dictionary = game.saves.snapshot()
			print("LAB SAVE mid-flight: balloon ", doc.get("balloon"), " player ", doc.get("position"), " cherry ", (doc.get("residents", {}) as Dictionary).get(ID, {}).get("position"), " home ", ship.home.origin)
		if not with_player and state == "cruise" and not cut and t > 40.0:
			cut = true
			var tod := get_node_or_null("/root/TimeOfDay")
			var home_by := float(pilot.get("turn_home_at"))
			print("LAB bedtime test: clock ", tod.hours, " -> ", home_by + 0.05)
			tod.hours = fmod(home_by + 0.05, 24.0)
		if phase == "none" and state in ["done", ""] and t > 5.0:
			break
	if pilot != null:
		print("LAB %s RESULT state %s, greatest distance from the Town Hall %.0f m, least clearance over ground/roofs %.1f m, highest %.0f m above the ground, visited %s, player rode %s, cut '%s', lowest local y of her %.2f" % [tag, pilot.get("state"), float(pilot.get("max_town_distance")), float(pilot.get("min_clearance")), float(pilot.get("max_height")), pilot.get("visited"), pilot.get("player_rode"), pilot.get("cut_reason"), min_basket_gap])
		print("LAB %s balloon at %s, home %s, off %.2f m, gate open %s, landed %s; route %s" % [tag, ship.global_position, ship.home.origin, Vector2(ship.global_position.x - ship.home.origin.x, ship.global_position.z - ship.home.origin.z).length(), ship.gate_open, ship.landed, pilot.get("route")])
	var her2 := _cherry()
	if is_instance_valid(her2):
		print("LAB %s her after: %s metas passenger %s pilot %s nav owner '%s' nav processing %s" % [tag, her2.global_position, her2.has_meta("balloon_passenger"), her2.has_meta("balloon_pilot"), her2.get_node("Navigator").command_owner, her2.get_node("Navigator").is_physics_processing()])
	var card2: Dictionary = runner.cards.get(ID, {})
	print("LAB %s card index %s of %d" % [tag, card2.get("index"), (card2.get("steps", []) as Array).size()])
