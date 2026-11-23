extends Node
## mitty's schoolhouse mod (school.pck, 2026-11-23) in the overhauled town: a Monday from 7:30, the clock running.
## Every SAMPLE seconds prints SCHOOL lines: the mod's class (its members, and for each of its foals and Cheerilee
## where she stands: in the mod's classroom, at its door, in the overhaul's schoolyard, or how far off), who holds
## her navigator ("schoolhouse:" the mod, "day:" the overhaul's routine), and the overhaul's own yard class
## (school.gd's "school_class" meta). The player waits in the classroom from 9:05 (the mod teaches only with him
## there). Quits by itself.
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/lab_school_mod.gd

const SAMPLE := 20.0
const MOD_FOALS := ["cheerilee", "apple_bloom", "sweetie_belle", "scootaloo", "diamond_tiara", "silver_spoon", "dinky_doo", "ruby_pinch", "archer", "noi"]
const ROOM := AABB(Vector3(-4.88, 0.3, -7.99), Vector3(9.76, 4.5, 14.77))
var game: Node


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		await get_tree().process_frame


func _mod() -> Node:
	for node: Node in get_tree().root.find_children("*", "Node", true, false):
		var s := node.get_script() as Script
		if s != null and s.resource_path in ["res://world/towns/ponyville/schoolhouse/classroom.gd", "res://mods/schoolhouse/main.gd"]: return node
	return null


func _copies() -> String:
	var out: Array = []
	for node: Node in get_tree().root.find_children("*", "Node", true, false):
		var s := node.get_script() as Script
		if s != null and s.resource_path == "res://world/towns/ponyville/schoolhouse/classroom.gd": out.append("overhaul")
		elif s != null and s.resource_path == "res://mods/schoolhouse/main.gd": out.append("standalone")
	return ", ".join(PackedStringArray(out))


func _go() -> void:
	var watchdog := get_tree().create_timer(1500.0)
	watchdog.timeout.connect(func() -> void: print("SCHOOL watchdog: quitting"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(game): print("SCHOOL no game"); get_tree().quit(); return
	var player: Node3D = game.get("player")
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	var day := int(tod.get("day"))
	tod.set("day", day + posmod(1 - day, 7))       # the next Monday (day 0 is a Sunday)
	# `--holiday`: the first weekday of the Hearth's Warming holidays instead (no school: day_planner.gd school_day)
	if OS.get_cmdline_user_args().has("--holiday"):
		var calendar: Node = get_tree().get_first_node_in_group("town_calendar")
		for d in range(day, day + 400):
			tod.set("day", d)
			if posmod(d, 7) < 1 or posmod(d, 7) > 5 or calendar == null: continue
			var ids: Array = (calendar.call("today_events") as Array).map(func(e: Dictionary) -> String: return str(e.get("id", "")))
			if "hearths_warming" in ids: print("SCHOOL holiday test: day %d is a weekday of Hearth's Warming" % d); break
	tod.set("hours", 7.5)
	await _wait(3.0)
	var mod := _mod()
	print("SCHOOL day %d (weekday %d), running copies: [%s]" % [int(tod.get("day")), posmod(int(tod.get("day")), 7), _copies()])
	var school: Node3D = null
	for n: Node in game.find_children("schoolhouse_01", "", true, false): school = n as Node3D
	if school == null: print("SCHOOL no schoolhouse_01"); get_tree().quit(); return
	print("SCHOOL schoolhouse_01 at %s yaw %.0f; mod classroom %s" % [school.global_position, rad_to_deg(school.global_rotation.y),
		"built" if school.get_node_or_null("SchoolInterior") != null else "not built"])
	player.global_position = school.global_transform * Vector3(0, 0.5, 16.0)
	var in_room := false
	for k in 40:
		await _wait(SAMPLE)
		var h := float(tod.get("hours"))
		if h >= 9.08 and not in_room and school.get_node_or_null("SchoolInterior") != null:
			player.global_position = school.global_transform * Vector3(0.0, 1.2, 3.0)
			in_room = true
		var members: Variant = mod.get("_members") if mod != null else null
		var line := "SCHOOL %05.2f h  mod class %d" % [h, (members as Dictionary).size() if members is Dictionary else -1]
		var yard := 0
		for actor: Node in get_tree().get_nodes_in_group("ponies") if not get_tree().get_nodes_in_group("ponies").is_empty() else []:
			if actor.has_meta("school_class"): yard += 1
		var population: Variant = game.get("population")
		var live: Dictionary = (population as Node).get("live") if is_instance_valid(population) else {}
		for id: String in live:
			var a: Variant = (live[id] as Dictionary).get("actor")
			if is_instance_valid(a) and (a as Node).has_meta("school_class"): yard += 1
		line += "  overhaul yard class %d" % yard
		print(line)
		var extras: Array = mod.get("_extras") if mod != null and mod.get("_extras") is Array else []
		line = "SCHOOL         at the back: %s" % str(extras)
		print(line)
		for id: String in MOD_FOALS + extras:
			var row: Variant = live.get(id)
			var a: Variant = (row as Dictionary).get("actor") if row is Dictionary else null
			if not is_instance_valid(a): print("SCHOOL     %-14s not spawned" % id); continue
			var actor := a as Node3D
			var local := school.global_transform.affine_inverse() * actor.global_position
			var where := "in the classroom" if ROOM.grow(0.3).has_point(local) else ("at the door" if local.distance_to(Vector3(0, local.y, 10.8)) < 3.0 else "%.0f m from the school" % Vector2(local.x, local.z).length())
			var nav: Node = actor.get_node_or_null("Navigator")
			print("SCHOOL     %-14s %-26s owner %-26s seated %s yard %s" % [id, where, str(nav.get("command_owner")) if nav != null else "-", str(actor.has_meta("seated")), str(actor.has_meta("school_class"))])
		if h > 10.0 or (h > 9.7 and k > 0 and OS.get_cmdline_user_args().has("--short")): break
	get_tree().quit()
