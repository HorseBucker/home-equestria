extends Node
## Every place id the day tables and routines name (--ids), resolved as a pony sent there resolves it (the place
## directory, else the walk grid's hot spots): where it lands and whether that is in the town (the plan's box) or
## out where the old map had things. Prints CHECK lines.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	await get_tree().create_timer(25.0).timeout
	var args := OS.get_cmdline_user_args()
	var places := preload("res://world/navigation/place_directory.gd")
	var svc: Node = null
	for s: Node in get_tree().get_nodes_in_group("pony_navigation"): svc = s
	var nav: Node = get_tree().get_nodes_in_group("pony_navigators")[0]
	for id: String in args[args.find("--ids") + 1].split(","):
		var e: Dictionary = places.find(get_tree(), id)
		var at: Vector3 = nav.call("command_location", id)
		var spot: Vector3 = svc.call("hot_spot_world", id, -12.0) if svc != null else Vector3.INF
		var source := "place directory" if not e.is_empty() else ("hot spot" if spot.is_finite() else "NOT FOUND")
		var inside_town := at.is_finite() and at.x > -120 and at.x < 460 and at.z > -400 and at.z < 120
		print("CHECK %s | %s | %s | %s" % [id, source, at.snapped(Vector3.ONE * 0.1) if at.is_finite() else "none", "in town" if inside_town else ("OUTSIDE the town" if at.is_finite() else "-")])
	# the day plan's spots (kit benches, gardens, log piles, mailboxes), each pony's own nearest
	var population: Node = get_tree().get_first_node_in_group("pony_populations")
	var spots: Script = preload("res://world/life/day/day_action.gd").SPOTS
	for pony: String in ["applejack", "fluttershy", "rarity", "lyra_heartstrings", "derpy_hooves", "carrot_top"]:
		for key: String in ["bench", "garden", "log_pile", "mailbox"]:
			var record: Dictionary = spots.resolve(population, pony, key)
			var at: Vector3 = record.get("approach", Vector3.INF)
			var inside_town := at.is_finite() and at.x > -120 and at.x < 460 and at.z > -400 and at.z < 120
			print("CHECK spot:%s for %s | %s | %s" % [key, pony, at.snapped(Vector3.ONE * 0.1) if at.is_finite() else "none", "in town" if inside_town else ("OUTSIDE the town" if at.is_finite() else "-")])
	get_tree().quit()
