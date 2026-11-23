extends Node
## Quality control inside the real game (its `--lab` hook: game.gd adds this node to the fully booted world).
##   godot --xr-mode off --path <project> -- --new-game --skip-title --lab res://tools/town_planner/build/qc/town_lab.gd
## (needs a window; set APPDATA to a scratch folder first so the test world stays out of your saves)
## It waits for the world, then:
## - CHECK lines: what stands at the world's origin (things left unplaced end up there), how far each town
##   landmark, the wagon, the easel, the cider stand and the dock stand above or below the ground, how many homes
##   and ponies there are;
## - walks the player through the views below, lets the town stream in, and saves a picture of each to
##   tools/town_planner/build/out/lab/<name>.png, with the frame's draw calls, triangles and GPU/CPU render time;
## - quits. Everything is printed with a LAB prefix.

const OUT := "res://tools/town_planner/build/out/lab"
## name, where the player stands (x, z), camera height above the ground there, what it looks at (x, height above
## the ground there, z)
const VIEWS := [
	["marigold_townhall", Vector2(232, -98), 22.0, Vector3(135, 3, -176)],
	# fifth round (plan V14)
	["r5_bg_h_door", Vector2(49.5, -223.4), 1.7, Vector3(54.2, 1.6, -231.1)],
	["r5_bg_h_close", Vector2(51.6, -226.8), 1.5, Vector3(54.2, 1.3, -231.1)],
	["r5_real_h_door", Vector2(69.3, -233.2), 1.7, Vector3(63.3, 1.6, -239.9)],
	["r5_boutique", Vector2(96, -110), 1.7, Vector3(106, 1.5, -96)],
	["r5_fountain", Vector2(119.5, -193.5), 1.2, Vector3(114, 0.3, -189.4)],
	["r5_library_path", Vector2(-5.5, -246.5), 7.0, Vector3(-8.5, 0, -257)],
	["r5_station_path", Vector2(-41, -250), 4.0, Vector3(-52, 0.5, -254)],
	["r5_bridge_house", Vector2(244, -316), 8.0, Vector3(236, 0, -326)],
	["r5_town_air", Vector2(20, -110), 70.0, Vector3(95, 0, -215)],
	["r5_crops", Vector2(300, -182), 7.0, Vector3(288, 0, -196)],
	["r5_street", Vector2(88, -186), 1.7, Vector3(20, 2, -177)],
	["r5_dirt_road", Vector2(250, -300), 3.0, Vector3(262, 0, -322)],
	["r5_mayor", Vector2(100, -160), 9.0, Vector3(90, 1, -147)],
	["r5_bg_a_door", Vector2(79.7, -183.6), 1.7, Vector3(78.8, 1.5, -193.6)],
	["r5_bg_b_door", Vector2(43.9, -183.9), 1.7, Vector3(45.5, 1.5, -174.0)],
	["r5_bg_c_door", Vector2(18.5, -180.0), 1.7, Vector3(20.3, 1.5, -170.1)],
	["r5_bg_e_door", Vector2(50.9, -225.6), 1.7, Vector3(45.6, 1.5, -217.1)],
	["r5_bg_f_door", Vector2(172.0, -258.1), 1.7, Vector3(172.0, 1.5, -248.1)],
	["r5_bg_g_door", Vector2(35.1, -262.5), 1.7, Vector3(42.0, 1.5, -255.3)],
	["r7_bg_g_front", Vector2(36.8, -260.7), 1.5, Vector3(39.9, 1.2, -257.5)],
	["r7_bg_g_angle", Vector2(35.0, -256.9), 1.5, Vector3(39.9, 1.2, -257.5)],
	["r7_bg_e_front", Vector2(49.6, -223.5), 1.5, Vector3(47.2, 1.2, -219.7)],
	["r7_bg_e_angle", Vector2(45.4, -224.3), 1.5, Vector3(47.2, 1.2, -219.7)],
	# fourth round
	["r4_hall_above", Vector2(118, -182), 20.0, Vector3(133, 0, -177)],
	["r4_hall_walk", Vector2(117, -182.5), 1.7, Vector3(135.5, 2, -175.9)],
	["r4_library_path", Vector2(-4, -239), 6.0, Vector3(-9, 0, -257)],
	["r4_station", Vector2(-41, -250), 1.7, Vector3(-55, 2, -247)],
	["r4_station_above", Vector2(-44, -247), 18.0, Vector3(-51, 0, -247)],
	["r4_barn", Vector2(-8, 34), 1.7, Vector3(-27.4, 3, 51.5)],
	["r4_barn_side", Vector2(-48, 40), 1.7, Vector3(-27.4, 2, 51.5)],
	["r4_stage", Vector2(226, -168), 1.7, Vector3(214.2, 1.5, -161.8)],
	["r4_stage_back", Vector2(204, -152), 1.7, Vector3(214.2, 1.5, -161.8)],
	# third play test
	["r3_hall_front", Vector2(119.5, -181.6), 1.7, Vector3(135.5, 3, -175.9)],
	["r3_hall_steps", Vector2(125.5, -180.5), 2.2, Vector3(132, 0.3, -177.2)],
	["r3_hall_side", Vector2(141, -154), 1.7, Vector3(135.5, 2, -175.9)],
	["r3_hall_back", Vector2(158, -168), 1.7, Vector3(135.5, 2, -175.9)],
	["r3_plaza_above", Vector2(128, -148), 48.0, Vector3(128, 0, -172)],
	["r3_library", Vector2(-4, -245), 1.7, Vector3(-15.5, 5, -267)],
	["r3_library_above", Vector2(-6, -248), 26.0, Vector3(-13, 0, -261)],
	["r3_well", Vector2(81, -219), 1.7, Vector3(74, 1, -228)],
	["r3_c_house", Vector2(31, -150), 3.0, Vector3(26.6, 0, -158.5)],
	["r3_lake_street_bush", Vector2(123, -224), 1.7, Vector3(117, 0.5, -217.5)],
	["r3_spa_pot", Vector2(151, -203), 1.7, Vector3(146, 0.5, -209)],
	["r3_cottage_behind", Vector2(392, 32), 6.0, Vector3(404, 1, 6)],
	["r3_bridge_west", Vector2(102, -9), 3.0, Vector3(91, 0, -14.4)],
	["r3_bridge_mid", Vector2(187, -58), 3.0, Vector3(176, 0, -50.3)],
	["r3_bridge_east", Vector2(255, -30), 3.0, Vector3(262, 0, -41.5)],
	["town_square", Vector2(118, -160), 1.7, Vector3(135, 5, -176)],
	["hall_bunting", Vector2(150, -132), 13.0, Vector3(136, 7, -176)],
	["hall_grass", Vector2(110, -172), 10.0, Vector3(135, 0, -176)],
	["bunting_house", Vector2(120, -153), 1.7, Vector3(106, 7, -143)],
	["fountain_benches", Vector2(126, -196), 6.0, Vector3(114, 0.5, -189.4)],
	["main_street", Vector2(88, -186), 1.7, Vector3(20, 2, -177)],
	["street_texture", Vector2(60, -183.5), 1.7, Vector3(38, 0, -180)],
	["street_from_above", Vector2(70, -184), 16.0, Vector3(70.2, 0, -184.5)],
	["library_street", Vector2(80, -206), 1.7, Vector3(20, 3, -240)],
	["market_above", Vector2(134.5, -250), 18.0, Vector3(134.5, 0, -282)],
	["uptown_row", Vector2(178, -258), 1.7, Vector3(179, 2, -330)],
	["leaning_houses", Vector2(163, -312), 1.7, Vector3(182, 5, -318)],
	["town_air", Vector2(20, -110), 60.0, Vector3(100, 0, -225)],
	["library_door", Vector2(-3, -243), 1.7, Vector3(-21, 3, -254.5)],
	["library_balloon", Vector2(8, -238), 9.0, Vector3(-18, 2, -256)],
	["library_south", Vector2(-24, -228), 1.7, Vector3(-21, 4, -254.5)],
	["hayburger", Vector2(-10, -170), 1.7, Vector3(-12, 3, -189)],
	["party_cannon", Vector2(32, -128), 3.0, Vector3(23, 0, -140)],
	["boutique_door", Vector2(92, -119), 1.7, Vector3(104, 3, -98)],
	["schoolyard", Vector2(60, -38), 7.0, Vector3(33, 2, -50)],
	["school_fence", Vector2(51.5, -74), 1.7, Vector3(50, 1, -40)],
	["school_path", Vector2(51.5, -50), 1.7, Vector3(30.5, 3, -50)],
	["school_above", Vector2(48, -50), 22.0, Vector3(47.9, 0, -50.4)],
	["clubhouse", Vector2(-18, -13), 2.5, Vector3(-45, 3, -8)],
	["barn", Vector2(-6, 34), 1.7, Vector3(-24, 3, 49)],
	["sweet_apple_acres", Vector2(8, 66), 5.0, Vector3(-27.4, 6, 51.5)],
	["south_bridge", Vector2(52, -100), 2.5, Vector3(50.7, -1, -86.5)],
	["east_bridge", Vector2(150, -176), 2.0, Vector3(170, 0, -176)],
	["west_bridge", Vector2(-44, -177), 1.8, Vector3(-56, 0, -174)],
	["riverside_bridges", Vector2(234, -301), 3.5, Vector3(247, 0, -296)],
	["fair_bridge", Vector2(184, -232), 2.0, Vector3(196, 0, -216)],
	["meadow_footbridge", Vector2(82, -12), 2.0, Vector3(92, 0, -14)],
	["river_flow", Vector2(150, -147), 5.0, Vector3(145, -1, -137)],
	["hospital", Vector2(16, -288), 1.7, Vector3(16, 4, -305)],
	["trixie_fair", Vector2(190, -176), 3.0, Vector3(206, 2, -160)],
	["farmhouse", Vector2(352, -168), 1.7, Vector3(358.7, 5, -187.3)],
	["carrot_fields", Vector2(350, -174), 7.0, Vector3(392, 0, -190)],
	["carrot_fields_west", Vector2(304, -182), 6.0, Vector3(275, 0, -200)],
	["carrot_beds_close", Vector2(366, -186), 1.7, Vector3(380, 0, -190)],
	["flower_meadow", Vector2(300, -236), 1.9, Vector3(340, 0, -280)],
	["flower_meadow_above", Vector2(285, -222), 26.0, Vector3(345, 0, -285)],
	["cloudominium", Vector2(380, -190), 1.7, Vector3(430, 62, -215)],
	["cottage_bridge", Vector2(398, -37), 2.2, Vector3(404, 0, -23)],
	["cottage_door", Vector2(418, -17), 1.7, Vector3(411, 1, -4)],
	["fluttershy_cottage", Vector2(396, -8), 2.0, Vector3(408, 3, 1)],
	["henhouse", Vector2(419, 24), 2.2, Vector3(428, 1, 11.5)],
	["cottage_hill", Vector2(430, -2), 9.0, Vector3(415, 0, 30)],
	["songbird_spring", Vector2(404, -40), 8.0, Vector3(434, -1, -23)],
	["origin", Vector2(8, 8), 3.0, Vector3(0, 0, 0)],
	["marigold_townhall_again", Vector2(232, -98), 22.0, Vector3(135, 3, -176)],
]

var game: Node


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await get_tree().process_frame


func _ground(x: float, z: float) -> float:
	if is_instance_valid(WorldTerrain.instance):
		var h: float = WorldTerrain.instance.height_at(Vector3(x, 0, z))
		if is_finite(h): return h
	return NAN


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only := PackedStringArray()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--lab-views" and i + 1 < args.size(): only = args[i + 1].split(",")
	# the world: a player and the terrain, then time for the town to stream in
	# the title screen puts a lab on the root before the game scene exists (and game.gd may add another): one is enough
	if str(name) != "Lab":
		queue_free(); return
	for i in 1200:
		if not is_instance_valid(game) or not ("player" in game):
			var scene := get_tree().current_scene
			game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.5)
	if not is_instance_valid(game):
		print("LAB no game scene; giving up"); get_tree().quit(); return
	var player: Node3D = game.get("player")
	if player == null:
		print("LAB no player; giving up"); get_tree().quit(); return
	print("LAB world up after ", Time.get_ticks_msec() / 1000, " s; player at ", player.global_position)
	# a new world opens on the arrival story's black screen: take its own "skip the opening" (he wakes in the library)
	var arrival: Variant = game.get("arrival")
	if arrival is Node and is_instance_valid(arrival) and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
		await _wait(3.0)
		print("LAB arrival skipped; player at ", player.global_position, " (the library door is the code's GOLDEN_OAK)")
	var tod := get_node_or_null("/root/TimeOfDay")
	if tod != null:
		tod.hours = 11.0; tod.paused = true
	var cam := Camera3D.new(); cam.name = "LabCamera"; cam.far = 4000.0; cam.fov = 70.0
	game.add_child(cam)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var first := true
	# `--lab-winter`: the views in winter (the season stepped on until it is winter, as F1 does; a preview snow lies)
	var winter_tag := ""
	if OS.get_cmdline_user_args().has("--lab-winter"):
		var season_node: Node = get_tree().get_first_node_in_group("season_state")
		for step in 4:
			if season_node == null or str(season_node.call("season")) == "winter": break
			season_node.call("step_season", 1)
		print("LAB season: ", season_node.call("season") if season_node != null else "none", ", snow cover ", season_node.call("snow_cover") if season_node != null else 0.0)
		await _wait(10.0)
		winter_tag = "winter_"

	for view: Array in VIEWS:
		if not only.is_empty() and not only.has(str(view[0])): continue
		var at: Vector2 = view[1]
		var h := _ground(at.x, at.y)
		player.global_position = Vector3(at.x, (h if is_finite(h) else 0.0) + 0.4, at.y)
		if "velocity" in player: player.set("velocity", Vector3.ZERO)
		await _wait(50.0 if first else 7.0)
		h = _ground(at.x, at.y)
		var eye := Vector3(at.x, (h if is_finite(h) else player.global_position.y) + float(view[2]), at.y)
		var look: Vector3 = view[3]
		var lh := _ground(look.x, look.z)
		cam.look_at_from_position(eye, Vector3(look.x, (lh if is_finite(lh) else h) + look.y, look.z), Vector3.UP)
		cam.make_current()
		await _wait(1.5)
		if first:
			first = false
			_checks()
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path(OUT).path_join(winter_tag + str(view[0]) + ".png"))
		var rid := get_viewport().get_viewport_rid()
		print("LAB VIEW %s: %d draw calls, %d triangles, gpu %.1f ms, cpu render %.1f ms, fps %d" % [view[0],
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.viewport_get_measured_render_time_gpu(rid), RenderingServer.viewport_get_measured_render_time_cpu(rid),
			Engine.get_frames_per_second()])
	print("LAB done")
	get_tree().quit()


func _world(n: Node3D) -> Vector3:
	return n.global_position if n.is_inside_tree() else Vector3.INF


func _checks() -> void:
	var town: Node = game.get_node_or_null("Zones/PonyvilleTown")
	print("LAB CHECK town node: ", town != null)
	# what stands at the origin
	var stack: Array[Node] = [get_tree().root]
	var near := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is Node3D and n.is_inside_tree() and (n is VisualInstance3D or n is CollisionObject3D):
			var p := (n as Node3D).global_position
			if Vector2(p.x, p.z).length() < 4.0 and absf(p.y) < 60.0 and not (n is Camera3D) and not (n is Light3D):
				near += 1
				if near <= 40: print("LAB CHECK at the origin: ", n.get_path(), " [", n.get_class(), "] ", p)
	print("LAB CHECK things at the origin: ", near)
	# how things stand on the ground
	var named := {"TrixieWagon": null, "PaintingStation": null, "OrchardNotice": null, "CiderStand": null, "CiderPress": null, "FishingDock": null}
	stack = [get_tree().root]
	var stands: Array[Node3D] = []
	while not stack.is_empty():
		var n2: Node = stack.pop_back()
		for c in n2.get_children(): stack.append(c)
		if n2 is Node3D:
			var nm := str(n2.name)
			var script: Script = n2.get_script()
			var sp := script.resource_path if script != null else ""
			if named.has(nm) or sp.ends_with("cider_stand.gd") or sp.ends_with("cider_press.gd") or sp.ends_with("fishing_dock.gd") or sp.ends_with("planting_plot.gd"):
				stands.append(n2)
	for n3 in stands:
		var p3 := n3.global_position
		var h3 := _ground(p3.x, p3.z)
		print("LAB CHECK %s (%s): at (%.1f, %.2f, %.1f), ground %.2f, above ground %+.2f" % [n3.name, n3.get_path(), p3.x, p3.y, p3.z, h3, p3.y - h3])
	if town != null:
		var scenery: Node = town.get_node_or_null("RNLScenery")
		var odd := 0
		if scenery != null:
			for group in scenery.get_children():
				for part in group.get_children():
					for item in part.get_children():
						if not (item is Node3D): continue
						var p4: Vector3 = (item as Node3D).global_position
						var h4 := _ground(p4.x, p4.z)
						if is_finite(h4) and absf(p4.y - h4) > 1.2 and not str(item.name).contains("_ramp") and not str(item.name).contains("_foundation"):
							odd += 1
							print("LAB CHECK scenery off the ground: %s at (%.1f, %.2f, %.1f), %+.2f from the ground" % [item.name, p4.x, p4.y, p4.z, p4.y - h4])
		print("LAB CHECK scenery more than 1.2 m off the ground: ", odd)
		var plots := 0; var floating := 0
		for c2 in town.get_children():
			if str(c2.name).begins_with("plot_") and c2 is Node3D:
				plots += 1
				var p5: Vector3 = (c2 as Node3D).global_position
				var h5 := _ground(p5.x, p5.z)
				if is_finite(h5) and absf(p5.y - h5) > 0.35:
					floating += 1; print("LAB CHECK home off the ground: %s %+.2f" % [c2.name, p5.y - h5])
		print("LAB CHECK real homes in the scene: ", plots, "; off the ground: ", floating)
	print("LAB CHECK house interiors: ", get_tree().get_nodes_in_group("house_interiors").size())
	var population: Variant = game.get("population")
	if population is Node and "houses" in population:
		var houses: Dictionary = population.get("houses")
		print("LAB CHECK ponies with a home: ", houses.size())
	var farm: Node = get_tree().get_first_node_in_group("apple_orchards")
	if farm != null: print("LAB CHECK orchard trees: ", (farm.get("orchard_trees") as Array).size(), " built ", farm.get("_built"))
