extends Node
## place_spread.gd at the day tables' landmarks: each anchor, whether something is built over it, and where 10 ponies
## would stand (all open, all apart?). Also which landmarks lie near Carrot Top's field. Prints SPREAD lines;
## --shots DIR saves a picture of the market from above with 10 markers.
const SPREAD := preload("res://world/life/day/place_spread.gd")
const PLACES := preload("res://world/navigation/place_directory.gd")

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
	await get_tree().create_timer(10.0).timeout
	var tables: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/life/day/day_tables.json"))
	var targets: Array = []
	for key: String in ["outing", "view", "reading_spot", "nap_spot", "wrap_up_spots", "shop", "food"]:
		for t: Variant in tables.targets[key].get("places", []):
			if str(t).begins_with("landmark:") and not str(t) in targets: targets.append(str(t))
	var player: Node3D = game.get("player")
	var space := get_viewport().get_world_3d().direct_space_state
	for t: String in targets:
		var anchor := PLACES.resolve(get_tree(), t)
		if not anchor.is_finite(): print("SPREAD %s unresolved" % t); continue
		player.global_position = anchor + (Vector3(0, 0.5, 0) if t == "landmark:town_hall" else Vector3(0, 2, 30))   # (collision near the camera)
		await get_tree().create_timer(1.2).timeout
		var covered := SPREAD.covered(space, anchor)
		var spots: Array[Vector3] = []
		for i in 10:
			SPREAD.release("lab_%d" % i)
		for i in 10:
			SPREAD.last_misses = {}
			spots.append(SPREAD.point(get_tree(), "lab_%d" % i, t, anchor))
			if spots[-1] == anchor: print("SPREAD   %s: no spot, %s" % [t, SPREAD.last_misses])
		var same := 0; var bad := 0; var near := INF
		for i in spots.size():
			if spots[i] == anchor: same += 1
			elif (SPREAD._floor_clear(space, spots[i]) != "clear") if t == "landmark:town_hall" else SPREAD.covered(space, spots[i]): bad += 1
			for j in range(i + 1, spots.size()): near = minf(near, Vector2(spots[i].x - spots[j].x, spots[i].z - spots[j].z).length())
		print("SPREAD %-36s anchor %s covered %s | 10 ponies: %d on the anchor, %d covered, closest pair %.1f m, farthest %.1f m" % [t, anchor.round(), covered, same, bad, near,
			spots.map(func(p): return Vector2(p.x - anchor.x, p.z - anchor.z).length()).max()])
	for e: Dictionary in PLACES.entries(get_tree()):
		var p: Vector3 = e.position
		if Vector2(p.x - 287.0, p.z + 198.0).length() < 60.0: print("SPREAD near the carrot field: %s (%s) at %s" % [e.id, e.label, p.round()])
	get_tree().quit()
