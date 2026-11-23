extends "res://tools/town_planner/build/qc/lab_agent_d.gd"
## The schoolyard class with the foals' bodies (play test 2026-11-16, agent D). The population does not
## put a pony in right beside the player, so the player waits ~90 m off (by the Crusaders' clubhouse)
## on a Monday morning until the pupils are out as bodies in the yard, then walks over: positions,
## postures, spacing, pictures (agent_d_class2_*.png) and what a pupil reads. Quits by itself.

func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if str(name) != "Lab":
		queue_free(); return
	var watchdog := get_tree().create_timer(1500.0)
	watchdog.timeout.connect(func() -> void: print("LAB watchdog: quitting"); get_tree().quit())
	for i in 1200:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.5)
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
	tod.day = 1; tod.hours = 7.4; tod.paused = false
	_move_player(club.global_position + Vector3(-15, 0, 10))
	var pupils := ["apple_bloom", "archer", "diamond_tiara", "dinky_doo", "noi", "ruby_pinch", "scootaloo", "silver_spoon", "sweetie_belle"]
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 600000:
		await _wait(10.0)
		var seated := 0
		for id: String in pupils:
			if str(_routine(id, "school").get("phase", "")) == "class": seated += 1
		print("LAB %.2f h: %d of %d pupils in class as bodies, cheerilee %s" % [float(tod.hours), seated, pupils.size(), _routine("cheerilee", "school").get("phase", "-")])
		if seated >= 7 and float(tod.hours) > 8.3: break
	_move_player(school.global_position + Vector3(0, 0, 26))
	await _wait(8.0)
	_status(pupils + ["cheerilee"], "school")
	_spacing(pupils + ["cheerilee"], "class")
	var layout: Dictionary = SCHOOL._layouts.get(school.get_instance_id(), {})
	var teach: Vector3 = layout.get("teacher", school.global_position)
	var middle: Vector3 = layout.get("class", school.global_position)
	var axis := (middle - teach); axis.y = 0.0; axis = axis.normalized()
	var side := Vector3(-axis.z, 0, axis.x)
	await _shot("class2_side", middle + side * 9.0 + Vector3(0, 2.5, 0) - axis * 1.0, (teach + middle) * 0.5)
	await _shot("class2_behind", middle + axis * 7.0 + Vector3(0, 2.8, 0), teach)
	await _shot("class2_above", (teach + middle) * 0.5 + Vector3(0, 18.0, 0.5), (teach + middle) * 0.5)
	await _shot("class2_wide", (teach + middle) * 0.5 + side * 22.0 + axis * 10.0 + Vector3(0, 12.0, 0), (teach + middle) * 0.5)
	_awareness("dinky_doo")
	_awareness("cheerilee")
	print("LAB done")
	get_tree().quit()
