extends Node
## Quality control inside the real game (play test 2026-11-16, agent D): the new routines.
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --lab res://tools/town_planner/build/qc/lab_agent_d.gd
## (needs a window; set APPDATA to a scratch folder first). Skips the arrival story, sets the clock to
## a Monday at 07:20 (a school day; the cards roll again for the new day, routines included) and lets
## the day run: the player waits in the schoolyard while the foals and Cheerilee come to school
## (unloaded ponies walk as essence and stream in near him), then the clock jumps to Carrot Top's
## afternoon in her fields, then to school letting out and the Crusaders' clubhouse meet-up and outing.
## Prints which ponies have which routine, where each stands, the yard layout, and the activity text the
## dialogue layer reads (life_intent, day_plan, town_talk.doing, the situation block when available);
## pictures go to tools/town_planner/build/out/lab/agent_d_*.png. Quits by itself.

const OUT := "res://tools/town_planner/build/out/lab"
const PLANNER := preload("res://world/life/day/day_planner.gd")
const TOWN_TALK := preload("res://world/ai/memory/town_talk.gd")
const PLACES := preload("res://world/navigation/place_directory.gd")
const SCHOOL := preload("res://world/life/day/actions/school.gd")
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
	while Time.get_ticks_msec() < until: await get_tree().process_frame


func _shot(label: String, eye: Vector3, look: Vector3) -> void:
	cam.look_at_from_position(eye, look, Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT).path_join("agent_d_" + label + ".png"))
	cam.clear_current(true)   # back to the player's camera: it is the population's streaming anchor
	print("LAB SHOT ", label)


func _body(id: String) -> Node3D:
	var body: Variant = population.live.get(id, {}).get("actor")
	return body as Node3D if is_instance_valid(body) and (body as Node3D).is_inside_tree() else null


func _move_player(to: Vector3) -> void:
	var ground: float = WorldTerrain.instance.height_at(to)
	player.global_position = Vector3(to.x, (ground if is_finite(ground) else to.y) + 0.5, to.z)
	if "velocity" in player: player.set("velocity", Vector3.ZERO)


func _routine(id: String, handler: String) -> Dictionary:
	var card: Dictionary = runner.cards.get(id, {})
	var steps: Array = card.get("steps", [])
	# The step of this handler for the hour: the last one that has started (else the first).
	var pick := -1
	for i in steps.size():
		if str(steps[i].get("handler", "")) != handler: continue
		if pick < 0 or float(steps[i].start) <= float(tod.hours): pick = i
	for i in steps.size():
		if i == pick:
			var running: bool = int(card.index) == i and card.get("action") != null
			var essence: bool = int(card.index) == i and not (card.get("essence", {}) as Dictionary).is_empty()
			var phase := str(card.action.get("_phase")) if running else ("essence" if essence else ("done" if i < int(card.index) else "later"))
			return {"step": steps[i], "phase": phase, "index": i, "card_index": card.index}
	return {}


func _status(ids: Array, handler: String) -> void:
	for id: String in ids:
		var r := _routine(id, handler)
		var body := _body(id)
		var action: Variant = runner.cards.get(id, {}).get("action")
		if action != null and action.get("reason") != null and not str(action.get("reason")).is_empty(): print("LAB REASON %s %s" % [id, action.get("reason")])
		print("LAB STATUS %s %s: %s, phase %s, at %s, posture %s" % [handler, id, "routine" if not r.is_empty() else "NO ROUTINE", r.get("phase", "-"),
			body.global_position if body != null else "unloaded", body.posture_status().get("kind", "?") if body != null and body.has_method("posture_status") else "-"])


func _awareness(id: String) -> void:
	var body := _body(id)
	print("LAB AWARE %s doing: '%s'" % [id, TOWN_TALK.doing(get_tree(), id)])
	if body == null: print("LAB AWARE %s (unloaded)" % id); return
	print("LAB AWARE %s life_intent: '%s'" % [id, body.get_meta("life_intent", "")])
	print("LAB AWARE %s day_plan: '%s'" % [id, body.get_meta("day_plan", "")])
	var director: Node = game.get("director")
	if director != null and director.has_method("situation_block") and "characters" in director and (director.characters as Dictionary).has(id):
		var block := str(director.situation_block(id))
		for line: String in block.split("\n"):
			if line.contains("Time:") or line.contains("activity intention") or line.contains("plans for today"): print("LAB SITUATION %s %s" % [id, line])


## Spacing check: nopony on top of another (centres under 0.9 m apart) among `ids` that are loaded.
func _spacing(ids: Array, label: String) -> void:
	var worst := INF
	var pair := ""
	for a: String in ids:
		for b: String in ids:
			if a >= b: continue
			var pa := _body(a); var pb := _body(b)
			if pa == null or pb == null: continue
			var d := Vector2(pa.global_position.x - pb.global_position.x, pa.global_position.z - pb.global_position.z).length()
			if d < worst: worst = d; pair = a + "/" + b
	print("LAB SPACING %s closest pair %s %.2f m" % [label, pair, worst])


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if str(name) != "Lab":
		queue_free(); return
	var watchdog := get_tree().create_timer(2400.0)
	watchdog.timeout.connect(func() -> void: print("LAB watchdog: quitting"); get_tree().quit())
	for i in 1200:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.5)
	if not is_instance_valid(game):
		print("LAB no game scene; giving up"); get_tree().quit(); return
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
	var school: Node3D = PLACES.find(get_tree(), "landmark:schoolhouse_01").get("node") as Node3D
	var club: Node3D = PLACES.find(get_tree(), "landmark:cutiemarkcrusaders_clubhouse_01").get("node") as Node3D
	var farm: Node3D = PLACES.find(get_tree(), "landmark:sweetappleacres_carrot_farmhouse_01").get("node") as Node3D
	print("LAB school ", school, " club ", club, " farm ", farm)
	if school == null: get_tree().quit(); return

	# A Monday morning (day 0 is a Sunday): the new day's cards roll with the routines.
	var day := 1
	tod.day = day; tod.hours = 7.2; tod.paused = false
	var calendar: Node = get_tree().get_first_node_in_group("town_calendar")
	print("LAB day %d is %s, school day %s, season %s" % [day, PLANNER.weekday_name(day), PLANNER.school_day(day), calendar.season_name(day) if calendar != null else "?"])
	for d in 8: print("LAB WEEK day %d %s school %s" % [d, PLANNER.weekday_name(d), PLANNER.school_day(d)])
	_move_player(school.global_position + Vector3(0, 0, 22))
	# Hold the clock while the town around the school streams in (each pony loads on a thread).
	tod.paused = true
	var t_stream := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_stream < 150000:
		await _wait(10.0)
		var foals := ["apple_bloom", "sweetie_belle", "scootaloo", "dinky_doo", "noi", "archer"].filter(func(f): return _body(f) != null)
		print("LAB streaming: %d live, foals loaded %s" % [population.live.size(), foals])
		if foals.size() >= 4: break
	tod.paused = false
	var pupils: Array = []
	for id: String in population.config.assignments.keys():
		var r := _routine(id, "school")
		if not r.is_empty(): pupils.append(id)
	print("LAB school routine for: ", pupils)
	for id: String in pupils:
		var r := _routine(id, "school")
		print("LAB ROUTINE %s role %s start %.2f until %.2f end %.2f text '%s'" % [id, r.step.get("role"), r.step.start, r.step.until, r.step.end, runner._text(r.step)])
	for id: String in CMC + ["golden_harvest", "cheerilee", "spike"]:
		var card: Dictionary = runner.cards.get(id, {})
		var texts: Array = []
		for s: Dictionary in card.get("steps", []): texts.append("%s@%.2f" % [s.get("handler"), float(s.start)])
		print("LAB CARD %s: %s" % [id, texts])
	# The yard layout, against the first loaded body's walk grid.
	var probe: Node3D = null
	for id: String in population.live.keys():
		probe = _body(id)
		if probe != null and probe.get_node_or_null("Navigator") != null: break
	if probe != null:
		var layout: Dictionary = SCHOOL.layout_for(school, probe.get_node("Navigator"))
		print("LAB YARD teacher %s class %s pupils %d: %s" % [layout.get("teacher"), layout.get("class"), (layout.get("pupils", []) as Array).size(), layout.get("pupils")])
	# Let the morning run until the class is together (or 08:45).
	var started := Time.get_ticks_msec()
	while float(tod.hours) < 9.0 and Time.get_ticks_msec() - started < 480000:
		await _wait(10.0)
		var settled := 0
		for id: String in pupils:
			if str(_routine(id, "school").get("phase", "")) == "class": settled += 1
		print("LAB %.2f h: %d of %d in class" % [float(tod.hours), settled, pupils.size()])
		if settled == pupils.size(): break
	_status(pupils, "school")
	_spacing(pupils, "class")
	var layout2: Dictionary = SCHOOL._layouts.get(school.get_instance_id(), {})
	var teach: Vector3 = layout2.get("teacher", school.global_position)
	var middle: Vector3 = layout2.get("class", school.global_position)
	var axis := (middle - teach); axis.y = 0.0; axis = axis.normalized()
	var side := Vector3(-axis.z, 0, axis.x)
	await _shot("class_side", middle + side * 9.0 + Vector3(0, 3.0, 0) - axis * 1.0, (teach + middle) * 0.5)
	await _shot("class_behind", middle + axis * 8.0 + Vector3(0, 3.5, 0), teach)
	await _shot("class_above", (teach + middle) * 0.5 + Vector3(0, 22.0, 0.5), (teach + middle) * 0.5)
	await _shot("yard_wide", school.global_position + side * 30.0 + Vector3(0, 14.0, 0), (teach + middle) * 0.5)
	_awareness("cheerilee")
	_awareness(str(pupils[0]) if not pupils.is_empty() else "apple_bloom")

	# Carrot Top's afternoon in her fields.
	if farm != null:
		tod.hours = 13.7
		_move_player(farm.global_position + Vector3(0, 0, 25))
		var t0 := Time.get_ticks_msec()
		var shots := 0
		while Time.get_ticks_msec() - t0 < 240000 and shots < 3:
			await _wait(8.0)
			var r := _routine("golden_harvest", "tend_fields")
			var body := _body("golden_harvest")
			var action: Variant = runner.cards.get("golden_harvest", {}).get("action")
			print("LAB CARROT %.2f h phase %s at %s worked %s" % [float(tod.hours), r.get("phase", "-"), body.global_position if body != null else "unloaded", action.get("_worked") if action != null and action.get("_worked") != null else "-"])
			if body != null and str(r.get("phase", "")) in ["inspect", "pour"]:
				var spot: Dictionary = action.get("_spot")
				var bed: Vector3 = spot.get("position", body.global_position)
				var out := body.global_position - bed; out.y = 0; out = out.normalized() if out.length() > 0.1 else Vector3.FORWARD
				await _shot("carrot_%d" % shots, body.global_position + out * 3.0 + Vector3(-out.z, 0, out.x) * 2.0 + Vector3(0, 1.6, 0), body.global_position + Vector3(0, 0.5, 0))
				shots += 1
				await _wait(6.0)
		_awareness("golden_harvest")

	# School lets out; the Crusaders meet at the clubhouse.
	tod.hours = 14.7
	await _wait(8.0)
	_status(pupils, "school")
	if club != null:
		_move_player(club.global_position + Vector3(20, 0, 15))
		tod.hours = 14.95
		var t1 := Time.get_ticks_msec()
		var met := false
		var left := false
		while Time.get_ticks_msec() - t1 < 480000:
			await _wait(6.0)
			var phases: Array = []
			for id: String in CMC: phases.append(str(_routine(id, "crusade").get("phase", "-")))
			print("LAB CMC %.2f h phases %s" % [float(tod.hours), phases])
			_status(CMC, "crusade")
			if not met and phases.count("wait") >= 2:
				met = true
				var a := _body(CMC[0]); var c: Vector3 = a.global_position if a != null else club.global_position
				_spacing(CMC, "meet")
				await _shot("cmc_meet", c + Vector3(6, 3, 6), c)
				_awareness(CMC[1])
			if not left and phases.count("outing") >= 2:
				left = true
				var b := _body(CMC[0]); if b == null: b = _body(CMC[1])
				if b != null:
					await _wait(4.0)
					await _shot("cmc_running", b.global_position + Vector3(7, 3, 5), b.global_position)
					_awareness(CMC[2])
			if phases.count("crusading") >= 2:
				var d := _body(CMC[0]); if d == null: d = _body(CMC[1])
				_spacing(CMC, "crusading")
				if d != null: await _shot("cmc_there", d.global_position + Vector3(6, 3, 6), d.global_position)
				_awareness(CMC[0])
				break
			# The outing can lead far: follow the group.
			var lead := _body(CMC[0])
			if lead != null and lead.global_position.distance_to(player.global_position) > 60.0: _move_player(lead.global_position + Vector3(15, 0, 10))
	# Fishing and the fountain (task 4): what a pony on those steps reads.
	for id: String in population.config.assignments.keys():
		var card: Dictionary = runner.cards.get(id, {})
		for s: Dictionary in card.get("steps", []):
			if str(s.get("handler")) in ["fish_at_dock", "drink_at_fountain"]:
				print("LAB OTHER %s %s text '%s'" % [id, s.handler, runner._text(s)])
				break
	print("LAB crusade failures: ", preload("res://world/life/day/actions/crusade.gd").failures)
	print("LAB done")
	get_tree().quit()
