extends Node
## Probe (play test 2026-11-16, agent D): what the schoolhouse, the Crusaders' clubhouse and the carrot
## farmhouse look like at run time (place entries, children, anchors, mesh bounds), for the school,
## crusade and tend_fields day steps. Prints LAB lines and quits.
const PLACES := preload("res://world/navigation/place_directory.gd")
var game: Node

func _ready() -> void:
	_go.call_deferred()

func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await get_tree().process_frame

func _go() -> void:
	var watchdog := get_tree().create_timer(600.0)
	watchdog.timeout.connect(func() -> void: print("LAB watchdog: quitting"); get_tree().quit())
	for i in 1200:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.5)
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
	await _wait(5.0)
	for id: String in ["landmark:schoolhouse_01", "landmark:cutiemarkcrusaders_clubhouse_01", "landmark:sweetappleacres_carrot_farmhouse_01", "landmark:windmill_01", "landmark:bridge_02", "landmark:fountain_01", "landmark:trainstation_01", "landmark:ponyville_market", "landmark:appleacres_barned_01"]:
		var e: Dictionary = PLACES.find(get_tree(), id)
		print("LAB PLACE ", id, " label '", e.get("label", ""), "' at ", e.get("position", Vector3.INF), " node ", (e.get("node") as Node).get_path() if e.get("node") is Node else "none")
		var node: Node3D = e.get("node") as Node3D
		if node == null: continue
		print("LAB   transform ", node.global_transform)
		for child: Node in node.get_children():
			print("LAB   child ", child.name, " ", child.get_class(), " ", (child as Node3D).position if child is Node3D else "")
		print("LAB   metas ", node.get_meta_list())
	var population: Node = game.get("population")
	for id: String in ["golden_harvest", "cheerilee", "apple_bloom", "noi", "spike"]:
		var house: Node3D = population.home_house(id) if population.has_method("home_house") else null
		print("LAB HOME ", id, " ", house.get_path() if house != null else "none", " ", population.home_position(id, true) if population.has_method("home_position") else "")
	get_tree().quit()
