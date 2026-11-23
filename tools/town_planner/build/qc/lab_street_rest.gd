extends Node
## street_rest.gd: the paint read at a few known points (street, path, grass, market square), and where a pony resting
## on a street would step to. Prints STREET lines.
const STREET := preload("res://world/characters/navigation/street_rest.gd")

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
	await get_tree().create_timer(15.0).timeout
	var points := {"street by Hayburger": Vector3(-10, -12, -180), "Riverside Path middle": Vector3(255.5, -12, -297.0),
		"grass by the fountain": Vector3(104, -12, -183), "market square": Vector3(129, -12, -282), "Town Hall square": Vector3(140, -12, -190)}
	for key: String in points:
		var p: Vector3 = points[key]
		p.y = WorldTerrain.instance.height_at(p)
		print("STREET %-22s texture %d, street to rest on: %s" % [key, STREET.texture_at(p), STREET.on_street(get_tree(), p)])
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var executors: Dictionary = (director.get("actions") as Object).get("executors")
	var nav: Node = (executors.values()[0] as Node).get("navigator")
	var at: Vector3 = points["street by Hayburger"]; at.y = WorldTerrain.instance.height_at(at)
	game.get("player").global_position = at + Vector3(0, 1, 6)
	await get_tree().create_timer(3.0).timeout
	var service: Variant = nav.get("_service")
	print("STREET nav of %s, service %s" % [nav.get("pony").name if nav.get("pony") else "?", service])
	for r: float in [2.0, 5.0, 9.5, 14.0, 20.0]:
		var kinds := []
		for k in 12:
			var p := at + Vector3(cos(TAU * k / 12.0), 0, sin(TAU * k / 12.0)) * r
			kinds.append(STREET.texture_at(p))
		var snap: Variant = service.closest(at + Vector3(r, 0, 0), nav.get("pony").get("profile"), 1.0) if service != null else null
		print("STREET ring %.1f m: textures %s, walk grid at +x: %s" % [r, kinds, snap])
	var grass := STREET.grass_near(nav, at)
	print("STREET from the street by Hayburger, grass at %s (%.1f m), texture %d" % [grass, grass.distance_to(at) if grass.is_finite() else -1.0, STREET.texture_at(grass) if grass.is_finite() else -1])
	get_tree().quit()
