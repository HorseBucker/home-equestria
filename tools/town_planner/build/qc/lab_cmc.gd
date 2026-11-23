extends Node
## Quality control inside the real game (play test 2026-11-17): the Crusaders' meet-up and outing at a
## sprint, anywhere in Ponyville, and one of them stopped as a chat stops her and let go again.
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --lab res://tools/town_planner/build/qc/lab_cmc.gd
## (needs a window; set APPDATA to a scratch folder first). A Monday at 14:55: prints each Crusader's
## phase, speed, sprint flag and activity text every few seconds; once they are under way Sweetie Belle is
## stopped the way day_runner.gd stops a step for a chat and held 25 s, then let go; pictures go to
## tools/town_planner/build/out/lab/cmc_*.png. Quits by itself.

const OUT := "res://tools/town_planner/build/out/lab"
const PLACES := preload("res://world/navigation/place_directory.gd")
const CMC := ["apple_bloom", "sweetie_belle", "scootaloo"]
var game: Node
var cam: Camera3D
var population: Node
var runner: Node
var tod: Node
var player: Node3D


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		await get_tree().process_frame


func _shot(label: String, eye: Vector3, look: Vector3) -> void:
	cam.look_at_from_position(eye, look, Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT).path_join("cmc_" + label + ".png"))
	cam.clear_current(true)
	print("LAB SHOT ", label)


func _body(id: String) -> Node3D:
	var body: Variant = population.live.get(id, {}).get("actor")
	return body as Node3D if is_instance_valid(body) and (body as Node3D).is_inside_tree() else null


func _move_player(to: Vector3) -> void:
	var ground: float = WorldTerrain.instance.height_at(to)
	player.global_position = Vector3(to.x, (ground if is_finite(ground) else to.y) + 0.5, to.z)
	if "velocity" in player: player.set("velocity", Vector3.ZERO)


func _phase(id: String) -> String:
	var card: Dictionary = runner.cards.get(id, {})
	var action: Variant = card.get("action")
	if action != null and action.get("_phase") != null: return str(action.get("_phase"))
	return "essence" if not (card.get("essence", {}) as Dictionary).is_empty() else "-"


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var watchdog := get_tree().create_timer(1500.0)
	watchdog.timeout.connect(func() -> void: print("LAB watchdog: quitting"); get_tree().quit())
	for i in 1200:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(game): print("LAB no game"); get_tree().quit(); return
	player = game.get("player")
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
		await _wait(3.0)
	population = game.get("population")
	runner = get_tree().get_first_node_in_group("day_runner")
	tod = get_node_or_null("/root/TimeOfDay")
	cam = Camera3D.new(); cam.name = "LabCamera"; cam.far = 4000.0; cam.fov = 60.0
	game.add_child(cam)
	var club: Node3D = PLACES.find(get_tree(), "landmark:cutiemarkcrusaders_clubhouse_01").get("node") as Node3D
	if club == null: print("LAB no clubhouse"); get_tree().quit(); return
	tod.day = 1; tod.hours = 14.5; tod.paused = false
	_move_player(club.global_position + Vector3(18, 0, 12))
	await _wait(20.0)
	tod.hours = 14.95
	for id: String in CMC:
		var card: Dictionary = runner.cards.get(id, {})
		for s: Dictionary in card.get("steps", []):
			if str(s.get("handler", "")) == "crusade": print("LAB STEP %s goal %s item '%s' places %d" % [id, s.get("goal"), s.get("item"), (s.get("places", []) as Array).size()])
	var started := Time.get_ticks_msec()
	var stopped_at := -1
	var released := false
	var shots := {}
	var top_speed := {}
	while Time.get_ticks_msec() - started < 600000:
		await _wait(3.0)
		var line := "LAB %.2f h" % float(tod.hours)
		var phases: Array = []
		for id: String in CMC:
			var body := _body(id)
			var card_: Dictionary = runner.cards.get(id, {})
			var nav: Variant = card_.get("ctx", {}).get("nav") if card_.get("ctx") is Dictionary else null
			var speed := Vector2(body.velocity.x, body.velocity.z).length() if body is CharacterBody3D else 0.0
			top_speed[id] = maxf(float(top_speed.get(id, 0.0)), speed)
			phases.append(_phase(id))
			line += " | %s %s %.1f m/s sprint %s '%s'" % [id, _phase(id), speed, nav.get("sprint") if is_instance_valid(nav) else "-", body.get_meta("life_intent", "") if body != null else "unloaded"]
		print(line)
		var lead := _body(CMC[0])
		if lead == null: lead = _body(CMC[2])
		if (stopped_at < 0 or released) and lead != null and lead.global_position.distance_to(player.global_position) > 45.0: _move_player(lead.global_position + Vector3(14, 0, 10))
		if phases.count("wait") >= 2 and not shots.has("meet") and lead != null:
			shots.meet = true; await _shot("meet", lead.global_position + Vector3(6, 3, 6), lead.global_position)
		if phases.count("outing") >= 2 and not shots.has("run") and lead != null:
			shots.run = true; await _wait(2.0); await _shot("run", lead.global_position + Vector3(7, 3, 5), lead.global_position)
		# A chat with Sweetie Belle as the game holds one: the player beside her, her last word fresh (the director's
		# chat_last), for 25 s; then he walks off (day_runner.gd stops her step and starts it again after the chat).
		var director: Node = game.get("director")
		if stopped_at < 0 and phases.count("outing") >= 2 and _phase("sweetie_belle") == "outing" and director != null:
			var body := _body("sweetie_belle")
			if body != null and (director.characters as Dictionary).has("sweetie_belle"):
				stopped_at = Time.get_ticks_msec()
				print("LAB CHAT sweetie_belle at ", body.global_position)
		if stopped_at > 0 and not released:
			var body2 := _body("sweetie_belle")
			if body2 != null:
				if Time.get_ticks_msec() - stopped_at < 25000:
					_move_player(body2.global_position + Vector3(1.6, 0, 0.8))
					director.characters["sweetie_belle"].chat_last = director._now()
				else:
					released = true
					_move_player(body2.global_position + Vector3(25, 0, 18))
					print("LAB CHAT sweetie_belle let go")
					if lead != null: await _shot("waiting", lead.global_position + Vector3(7, 3, 5), lead.global_position)
		if phases.count("crusading") >= 3 or (released and phases.count("crusading") >= 2 and Time.get_ticks_msec() - stopped_at > 120000):
			var d := _body(CMC[0]); if d == null: d = _body(CMC[1])
			if d != null: await _shot("there", d.global_position + Vector3(6, 3, 6), d.global_position)
			break
	print("LAB top speeds ", top_speed)
	print("LAB done")
	get_tree().quit()
