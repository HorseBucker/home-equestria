extends Node
## Town density check (2026-11-17) in the real game: which town loaded, its houses, gardens and kept homes.
##   godot --xr-mode off --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/lab_density.gd
## (APPDATA a scratch folder whose user://town_density.cfg sets [town] density; a user://town_homes.json there is the
## homes to keep). Prints DENSITY lines and quits.
var game: Node


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var watchdog := get_tree().create_timer(900.0)
	watchdog.timeout.connect(func() -> void: print("DENSITY watchdog: quitting"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(game): print("DENSITY no game"); get_tree().quit(); return
	var density := preload("res://world/towns/ponyville/town_density.gd")
	var town: Node = game.get_node("Zones/PonyvilleTown")
	var plots := 0; var vacant := 0; var lived := 0; var no_interior := 0
	for child: Node in town.get_children():
		if not str(child.name).begins_with("plot_"): continue
		plots += 1
		if child.has_meta("reserved_for"): lived += 1
		elif child.get_meta("vacant", false): vacant += 1
		if child.get_node_or_null("HouseInterior") == null: no_interior += 1
	var bg := town.get_node("BackgroundHouses").get_child_count()
	print("DENSITY town %s (meta %s): %d real (%d lived in, %d vacant, %d without an interior), %d background; at %.1f s" % [density.active,
		str(town.get_meta("town_density", "high")), plots, lived, vacant, no_interior, bg, Time.get_ticks_msec() / 1000.0])
	print("DENSITY restored homes: ", density.restored)
	for name: String in density.restored:
		var house := town.get_node_or_null(name) as Node3D
		if house == null: print("DENSITY   ", name, " missing"); continue
		var near: Array = []
		for pair: Array in density._houses(town):
			var other: Node3D = pair[0]
			if other != house and other.global_position.distance_to(house.global_position) < 14.0:
				near.append("%s %.1f m" % [other.name, other.global_position.distance_to(house.global_position)])
		print("DENSITY   %s at %s, interior %s; neighbours within 14 m: %s" % [name, house.global_position, house.get_node_or_null("HouseInterior") != null, near])
	# gardens: kit rows grouped by a house, and whether each such house is in this town
	var kit := preload("res://world/props/ponyville_kit/kit_spots.gd")
	kit._index()
	var groups := 0; var orphans: Array = []
	for owner: String in kit._by_owner:
		if not owner.begins_with("house:plot_"): continue
		groups += 1
		if town.get_node_or_null(owner.substr(6)) == null: orphans.append(owner)
	print("DENSITY gardens: %d real homes' gardens, kit rows %d; gardens of a home not in this town: %s" % [groups, kit._by_id.size(), orphans.slice(0, 10)])
	if "--grant" in OS.get_cmdline_user_args():
		# a pony gives the player a home: the world's home is remembered (town_homes.json)
		var arrival: Node = game.get("arrival")
		if arrival is Node and (arrival as Node).has_method("skip_to_free_home"): await (arrival as Node).skip_to_free_home()
		var given: Variant = arrival.call("grant_home", "twilight_sparkle") if arrival != null else null
		print("DENSITY granted: ", (given as Node).get_parent().name if given is Node else "nothing", " can_grant ", arrival.call("can_grant_home") if arrival != null else "")
		await get_tree().create_timer(2.0).timeout
		print("DENSITY town_homes.json: ", FileAccess.get_file_as_string(density.HOMES).replace("\n", " "))
	await get_tree().create_timer(20.0).timeout
	var interiors := get_tree().get_nodes_in_group("house_interiors").size()
	print("DENSITY house interiors %d, nodes %d" % [interiors, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	get_tree().quit()
