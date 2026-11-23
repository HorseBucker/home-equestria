extends Node
## Every house a pony can be inside: does each loaded pony fit through its doorway (house fits())? Prints FIT lines.
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
	var ponies: Array[Node3D] = []
	for n: Node in get_tree().root.find_children("*", "CharacterBody3D", true, false):
		if n.get("profile") != null and n.get("profile") is Resource and "clearance" in n.get("profile"): ponies.append(n as Node3D)
	var houses: Array[Node] = []
	for g: String in ["house_interiors", "homes", "pony_homes"]:
		for h: Node in get_tree().get_nodes_in_group(g):
			if h.has_method("fits") and not h in houses: houses.append(h)
	print("FIT %d ponies, %d houses" % [ponies.size(), houses.size()])
	for h: Node in houses:
		var bad: Array[String] = []
		for p: Node3D in ponies:
			if not bool(h.call("fits", p.get("profile"))): bad.append("%s(%.2f)" % [p.name, float(p.get("body_scale")) if p.get("body_scale") != null else 0.0])
		var sx := (h as Node3D).global_basis.x.length(); var sy := (h as Node3D).global_basis.y.length()
		var up: Node = h
		while up != null and up.scene_file_path.is_empty(): up = up.get_parent()
		var dw: float = float(h.get("door_width")) * sx if h.get("door_width") != null else -1.0
		print("FITX %s %s door %.2f fits_canon %s fits_1.35 %s" % [up.scene_file_path if up != null else "?", (h as Node3D).global_position.round(), dw, dw > 0.98, dw > 0.45 * 1.35 * 2.0 + 0.08])
		print("FIT %s at %s scale (%.2f, %.2f) door %.2f m x %.2f m | refuses %d: %s" % [h.name, (h as Node3D).global_position.round(), sx, sy,
			float(h.get("door_width")) * sx if h.get("door_width") != null else -1.0, 0.20 * sy, bad.size(), ", ".join(bad.slice(0, 12))])
	for p: Node3D in ponies:
		var prof: Resource = p.get("profile")
		if p.name == "CherryBerry": print("FIT CherryBerry radius %.3f clearance %.3f body_scale %s at %s" % [prof.radius, prof.clearance, str(p.get("body_scale")), p.global_position.round()])
	get_tree().quit()
