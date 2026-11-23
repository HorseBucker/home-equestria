extends Node
## Each pony's avoidance agent against her size (pony_navigator.gd sync_agent_size): radius and height against her
## profile's, at load and after every pony is resized to 1.35 (JRHNBR) and back to 1.0. Prints AGENT lines.
func _ready() -> void:
	_go.call_deferred()

func _check(label: String) -> void:
	var off := 0; var total := 0; var sample := ""
	for nav: Node in get_tree().get_nodes_in_group("pony_navigators"):
		var agent := nav.get("agent") as NavigationAgent3D
		var pony := nav.get("pony") as Node
		if agent == null or not is_instance_valid(pony) or pony.get("profile") == null: continue
		total += 1
		var p: Resource = pony.get("profile")
		if not is_equal_approx(agent.radius, float(p.radius)) or not is_equal_approx(agent.height, float(p.clearance)):
			off += 1
			if sample.length() < 400: sample += " %s(agent %.3f/%.3f, body %.3f/%.3f, scale %.2f)" % [pony.name, agent.radius, agent.height, p.radius, p.clearance, float(pony.get("body_scale"))]
	var radii := {}
	for nav: Node in get_tree().get_nodes_in_group("pony_navigators"):
		var agent := nav.get("agent") as NavigationAgent3D
		if agent != null: radii[snappedf(agent.radius, 0.01)] = int(radii.get(snappedf(agent.radius, 0.01), 0)) + 1
	print("AGENT %s: %d ponies, %d mismatched%s; agent radii %s" % [label, total, off, sample, radii])

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	game.get("player").global_position = Vector3(110, -10, -260)
	await get_tree().create_timer(40.0).timeout
	_check("at load")
	for size: float in [1.35, 1.0]:
		for nav: Node in get_tree().get_nodes_in_group("pony_navigators"):
			var pony := nav.get("pony") as Node
			if is_instance_valid(pony) and pony.has_method("set_body_scale"): pony.set_body_scale(size)
		await get_tree().create_timer(1.0).timeout
		_check("after set_body_scale(%.2f)" % size)
	get_tree().quit()
