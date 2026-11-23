extends Node
## Quality control inside the real game (play test 2026-11-16): drinking at the Town Square fountain at
## every pony size (world/life/day/actions/fountain_drinker.gd, fountain_drink_pose.gd), eyes shut,
## interruptions, and the fountain's water in winter.
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --lab res://tools/town_planner/build/qc/lab_agent_f.gd
## (set APPDATA to a scratch folder first). One pony is resized to each size and given the step through
## DayRunner.inject_now; pictures go to tools/town_planner/build/out/lab/agent_f_*.png; LAB lines; quits itself.

const OUT := "res://tools/town_planner/build/out/lab"
const SIZES := [["canon", 1.0], ["jrhnbr", 1.35], ["same", 1.7], ["hoers", 2.3], ["foal", 0.62]]
var game: Node
var cam: Camera3D
var water: Node3D
var runner: Node
var population: Node
var player: Node3D
## `--film` (with Godot's `--write-movie <file>.avi --fixed-fps 30`): a camera follows each drink from her side,
## and LAB film lines give each drink's first and last frame for cutting clips (2026-11-18 play test round 2).
var film := false


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		_park_player()
		# the pause menu opens after a spell without input (pause_menu.gd): keep it shut for the pictures
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		await get_tree().process_frame


## Something in the opening puts the player back at the start: keep him by the fountain so the
## ponies there stay streamed in.
func _park_player() -> void:
	if not is_instance_valid(player) or not is_instance_valid(water): return
	var spot := water.global_position + Vector3(10.0, 0.5, 10.0)
	if player.global_position.distance_to(spot) < 6.0: return
	if player.has_method("teleport"): player.call("teleport", spot)
	else: player.global_position = spot
	if "velocity" in player: player.set("velocity", Vector3.ZERO)
	print("LAB parked the player by the fountain")


func _shot(label: String, eye: Vector3, look: Vector3) -> void:
	cam.look_at_from_position(eye, look, Vector3.UP)
	cam.make_current()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT).path_join("agent_f_" + label + ".png"))


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if str(name) != "Lab":
		queue_free(); return
	get_tree().create_timer(1500.0).timeout.connect(func() -> void: print("LAB watchdog: quitting"); get_tree().quit())
	for i in 1200:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.5)
	if not is_instance_valid(game): print("LAB no game"); get_tree().quit(); return
	player = game.get("player")
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
		await _wait(3.0)
	var tod := get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.hours = 11.0; tod.paused = true
	water = get_tree().get_first_node_in_group("town_fountains") as Node3D
	# `--sink 0.2`: the fountain set this much lower first (trying a lower rim, 2026-11-18)
	var lab_args := OS.get_cmdline_user_args()
	if "--sink" in lab_args and water != null:
		(water.get_parent() as Node3D).position.y -= float(lab_args[lab_args.find("--sink") + 1])
		print("LAB fountain sunk by ", lab_args[lab_args.find("--sink") + 1])
	if water == null: print("LAB FAIL no fountain"); get_tree().quit(); return
	var c := water.global_position
	print("LAB fountain node y %.3f, terrain under its rim %.3f, rim top %.3f, water %.3f" % [water.get_parent().global_position.y,
		WorldTerrain.instance.height_at(c + Vector3(3.5, 0, 0)), water.to_global(Vector3(0, 0.97, 0)).y, water.to_global(Vector3(0, 0.94, 0)).y])
	player.global_position = c + Vector3(10.0, 0.5, 10.0)
	cam = Camera3D.new(); cam.far = 3000.0; cam.fov = 50.0
	game.add_child(cam)
	await _wait(40.0)
	population = game.get("population")
	runner = get_tree().get_first_node_in_group("day_runner")
	var id := ""
	var best := INF
	for key: String in population.live:
		var b: Node3D = population.live[key].get("actor")
		if not is_instance_valid(b) or b.get("neck_link") == null or not runner.can_inject(key, true): continue
		var identity: Resource = b.get("identity")
		if identity != null and (identity.get("filly") == true or identity.get("stallion") == true): continue
		var d := b.global_position.distance_to(c)
		if d < best: best = d; id = key
	if id.is_empty(): print("LAB FAIL no pony"); get_tree().quit(); return
	print("LAB pony %s; player at %s (%.1f m from the fountain), anchor %s, release distance %s, region %s/%s" % [id, player.global_position, player.global_position.distance_to(c),
		population.get("anchor"), population.call("release_distance", id) if population.has_method("release_distance") else "?",
		population.live[id].get("region"), population.call("residence_region", id) if population.has_method("residence_region") else "?"])
	var only: PackedStringArray = []
	var args := OS.get_cmdline_user_args()
	film = "--film" in args
	if "--sizes" in args: only = args[args.find("--sizes") + 1].split(",")
	for size: Array in SIZES:
		if not only.is_empty() and not only.has(str(size[0])): continue
		_body(id).set_body_scale(float(size[1]))
		await _drink(id, str(size[0]), "")
	_body(id).set_body_scale(1.0)
	await _drink(id, "cut", "command")
	await _drink(id, "chat", "chat")
	# Winter: liquid water, and the step still starts.
	var season: Node = get_tree().get_first_node_in_group("season_state")
	if season != null and season.has_method("pin"):
		season.call("pin", "winter", 1.0)
		season.call("tick")
	await _wait(8.0)
	print("LAB winter: season %s ice %.2f, fountain iced %s, ice_kind %s" % [season.call("season") if season != null else "?", float(season.call("ice")) if season != null else -1.0,
		water.call("iced"), water.material.get_shader_parameter("ice_kind")])
	var g: float = WorldTerrain.instance.height_at(c + Vector3(5, 0, 3))
	await _shot("winter", Vector3(c.x + 5.0, g + 2.2, c.z + 3.0), c + Vector3(0, 0.75, 0))
	await _drink(id, "winter", "")
	print("LAB done")
	get_tree().quit()


## The film camera: three-quarters from her side, a little above her, looking at her and the rim.
var _film_side := Vector3.ZERO
func _film(body: Node3D) -> void:
	var c := water.global_position
	var out := Vector3(body.global_position.x - c.x, 0.0, body.global_position.z - c.z).normalized()
	if _film_side == Vector3.ZERO: _film_side = out.cross(Vector3.UP).normalized()
	var s := float(body.get("body_scale"))
	var middle := body.global_position - out * 0.35 * s + Vector3.UP * 0.55 * s
	var eye := middle + _film_side * 2.6 * s + out * 1.6 * s + Vector3.UP * 0.5 * s
	cam.look_at_from_position(eye, middle, Vector3.UP)
	cam.make_current()


func _body(id: String) -> Node3D:
	return population.live.get(id, {}).get("actor") as Node3D


func _drink(id: String, label: String, cut: String) -> void:
	var c := water.global_position
	var body := _body(id)
	var nav: Node = body.get_node("Navigator")
	print("LAB [%s] pony at %s, %.1f m from the fountain" % [label, body.global_position, body.global_position.distance_to(c)])
	if body.global_position.distance_to(c) > 40.0:
		nav.stay()
		for spot: Dictionary in water.call("drink_spots"):
			var a: Vector3 = spot.approach
			var at: Vector3 = nav.command_support(a + (a - c).normalized() * 4.0)
			if at.is_finite() and at.distance_to(a) < 6.0:
				print("LAB [%s] brought her to %s" % [label, at])
				body.global_position = at + Vector3(0, 0.1, 0)
				if "velocity" in body: body.set("velocity", Vector3.ZERO)
				break
		await _wait(2.0)
	var step := {"action": "drink_fountain", "handler": "drink_at_fountain", "target": "landmark:fountain_01",
		"phrase": "have a drink at the {target}", "reason": "for the lab", "minutes": 4.0, "hours": 1.0}
	# Why a start would refuse (the runner drops a refused step without a word).
	var trial: RefCounted = load("res://world/life/day/actions/drink_at_fountain.gd").new()
	var ctx := {"id": id, "actor": body, "nav": nav, "step": step, "runner": runner, "population": population, "night_rest": null, "tree": get_tree()}
	var could: bool = trial.start(ctx)
	print("LAB [%s] trial start %s reason '%s' interruption '%s'" % [label, could, trial.get("reason"), body.call("action_interruption_reason") if body.has_method("action_interruption_reason") else ""])
	trial.stop(ctx)
	print("LAB [%s] size %s" % [label, load("res://world/life/day/actions/fountain_drink_pose.gd").size_report(body, water.to_global(Vector3(0, 0.97, 0)).y - body.global_position.y)])
	var ok: bool = runner.inject_now(id, step)
	print("LAB [%s] scale %.2f inject %s" % [label, float(body.get("body_scale")), ok])
	var shots := {}
	var last := ""
	var started := Time.get_ticks_msec()
	var cut_at := -1
	var why := ""
	var seen := false
	while Time.get_ticks_msec() - started < 110000:
		await get_tree().process_frame
		_park_player()
		body = _body(id)
		if not is_instance_valid(body): print("LAB [%s] body gone" % label); await _wait(1.0); continue
		nav = body.get_node("Navigator")
		var card: Dictionary = runner.cards.get(id, {})
		var action: RefCounted = card.get("action")
		var drinker: Node = body.get_node_or_null("FountainDrink")
		if action != null or drinker != null: seen = true
		if drinker != null and not str(drinker.get("outcome")).is_empty() and not shots.has("outcome"):
			shots.outcome = true
			var p0: Node = drinker.get("pose")
			print("LAB [%s] drinker %s '%s' kind '%s' probe %s" % [label, drinker.get("outcome"), drinker.get("reason"), drinker.get("kind"), _probe_text(p0.get("probe") if p0 != null else drinker.get_meta("probe", {}))])
		if action != null and action.get("reason") != null and not str(action.get("reason")).is_empty(): why = str(action.get("reason"))
		var stage := str(drinker.get("stage")) if drinker != null else ("action:" + str(action.get("_phase")) if action != null and action.get("_phase") != null else "none")
		if stage != last:
			var extra := ""
			if drinker != null and drinker.get("pose") != null:
				var p: Node = drinker.get("pose")
				if stage == "approach": extra = " kind %s probe %s" % [drinker.get("kind"), _probe_text(p.get("probe"))]
			if stage == "none" and action == null: extra = " (step ended; reason '%s')" % why
			print("LAB [%s] stage %s at %.1f s%s" % [label, stage, (Time.get_ticks_msec() - started) / 1000.0, extra])
			last = stage
		if drinker == null:
			if action == null and (seen or Time.get_ticks_msec() - started > 20000): break
			continue
		var pose: Node = drinker.get("pose")
		if pose == null: continue
		var rear := float(drinker.get("_rear"))
		var hoof1: float = (drinker.get("_hooves") as Array)[1]
		if film:
			if not shots.has("film"):
				shots.film = true
				print("LAB film [%s] start frame %d" % [label, Engine.get_frames_drawn()])
			_film(body)
			continue
		if stage == "up" and hoof1 >= 0.5 and not shots.has("up"):
			shots.up = true; await _pictures(label + "_stepup", body, pose, false)
		if stage == "sip" and not shots.has("sip"):
			shots.sip = true; await _pictures(label + "_sip", body, pose, true)
			if cut == "command": cut_at = Time.get_ticks_msec()
			if cut == "chat": body.set("conversation_target", player); cut_at = Time.get_ticks_msec()
		if stage == "down" and hoof1 <= 0.5 and not shots.has("down"):
			shots.down = true; await _pictures(label + "_stepdown", body, pose, false)
		if cut == "command" and cut_at > 0 and Time.get_ticks_msec() - cut_at > 600 and str(nav.command_owner).begins_with("day:"):
			nav.stay(); nav.command_owner = "lab:cut"
			nav.go_to(nav.command_support(body.global_position + (body.global_position - c).normalized() * 6.0), 0)
			print("LAB [cut] took her navigator mid-sip at r %.2f" % _r(body.global_position))
		if cut == "chat" and cut_at > 0 and Time.get_ticks_msec() - cut_at > 4000 and body.get("conversation_target") != null:
			print("LAB [chat] stage during chat: %s, eyes touch %s" % [stage, _eyes(body)])
			body.set("conversation_target", null)
	if film:
		for i in 45:
			await get_tree().process_frame
			if is_instance_valid(_body(id)): _film(_body(id))
		print("LAB film [%s] end frame %d" % [label, Engine.get_frames_drawn()])
	await _wait(3.0)
	body = _body(id)
	if not is_instance_valid(body): print("LAB [%s] body gone after" % label); return
	print("LAB [%s] after: r %.2f, nav owner '%s', slot %s, pose node %s, drinker %s, eyes touch %s, speed %.2f" % [label, _r(body.global_position), nav.command_owner,
		body.get("activity_mouth_pose"), body.get("skeleton").get_node_or_null("FountainDrinkPose"), body.get_node_or_null("FountainDrink"), _eyes(body), float(body.get("actual_speed"))])
	if cut == "command":
		nav.stay(); nav.command_owner = ""
		await _wait(2.0)


func _eyes(body: Node3D) -> bool:
	var expressions: Object = body.get("expressions")
	return expressions != null and (expressions.get("_touches") as Dictionary).has("fountain_drink")


func _r(p: Vector3) -> float:
	var c := water.global_position
	return Vector2(p.x - c.x, p.z - c.z).length()


func _probe_text(probe: Variant) -> String:
	if not probe is Dictionary: return "?"
	var t := "shoulder %.2f rim %.2f |" % [float(probe.get("standing_shoulder", 0)), float(probe.get("rim_height", 0))]
	for k: String in ["lean", "rear"]:
		var row: Dictionary = probe.get(k, {})
		t += " %s: adv %.2f pitch %.0f mouth gap %.3f above water %.3f FL rim %.3f r %.2f RL gnd %.3f chest %.3f |" % [k, float(row.get("advance", 0)), rad_to_deg(float(row.get("pitch", 0))),
			float(row.get("mouth_gap", -1)), float(row.get("mouth_above_water", -1)), float(row.get("FL_over_rim", -1)), float(row.get("FL_r", -1)), float(row.get("RL_over_ground", -1)), float(row.get("chest_clear", -1))]
	return t


func _pictures(label: String, body: Node3D, pose: Node, all: bool) -> void:
	var m: Dictionary = pose.get("metrics")
	var aff: Node = body.get_node_or_null("Affection")
	var mouth: Vector3 = aff.mouth_point() if aff != null else Vector3.INF
	var wy: float = water.to_global(Vector3(0, 0.94, 0)).y
	print("LAB [%s] visible mouth %.3f above water at r %.2f; pose mouth gap %.3f; FL/FR over rim %.3f/%.3f at r %.2f/%.2f; RL/RR over ground %.3f/%.3f; chest clear %.3f (r %.2f, %.2f over rim); eyes shut %s" % [label,
		mouth.y - wy, _r(mouth), float(m.get("mouth_gap", -1)), float(m.get("FL_over_rim", -1)), float(m.get("FR_over_rim", -1)), float(m.get("FL_r", -1)), float(m.get("FR_r", -1)),
		float(m.get("RL_over_ground", -1)), float(m.get("RR_over_ground", -1)), float(m.get("chest_clear", -1)), float(m.get("chest_r", -1)), float(m.get("chest_over_rim", -1)), _eyes(body)])
	var s := float(body.get("body_scale"))
	var c := water.global_position
	var out := body.global_position - c; out.y = 0.0; out = out.normalized()
	var side := Vector3(-out.z, 0.0, out.x)
	var look := body.global_position - out * 0.35 * s + Vector3.UP * 0.55 * s
	await _shot(label + "_side", look + side * 2.4 * s + Vector3.UP * 0.15 * s, look)
	if all:
		await _shot(label + "_front", look - out * 2.2 * s + Vector3.UP * 0.7 * s, look)
		await _shot(label + "_3q", look + (side * 1.6 - out * 1.3) * s + Vector3.UP * 0.8 * s, look)
		if mouth.is_finite():
			await _shot(label + "_face", mouth + (side * 0.45 - out * 0.35 + Vector3.UP * 0.2) * s, mouth + Vector3.UP * 0.06 * s)
