extends Node
## Every house's door approach (house_interiors: outside()), with the walk grid sampled round it: walkable for a canon
## pony or not, its floor against the terrain's height. Prints DOORS lines for the ones that are not walkable.
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
	await get_tree().create_timer(20.0).timeout
	var svc: Node = null
	for s: Node in get_tree().get_nodes_in_group("pony_navigation"): svc = s
	var pony: Node = null
	for nav: Node in get_tree().get_nodes_in_group("pony_navigators"): pony = nav.get("pony"); break
	if pony.has_method("set_body_scale"): pony.call("set_body_scale", 1.0)
	var profile: Resource = pony.get("profile")
	var homes: Array = get_tree().get_nodes_in_group("house_interiors").filter(func(h: Node) -> bool: return h.has_method("outside"))
	for h: Node in homes: svc.call("ensure_near", h.call("outside"), 3.0)
	await get_tree().create_timer(60.0).timeout
	var bad := 0
	for h: Node in homes:
		var at: Vector3 = h.call("outside")
		var ok: bool = svc.call("is_walkable", at, profile)
		var near: Vector3 = svc.call("closest", at, profile, 1.0)
		if not ok and not (near.is_finite() and Vector2(near.x - at.x, near.z - at.z).length() < 0.8):
			bad += 1
			print("DOORS not walkable: %s %s at %s terrain %.2f nearest %s" % [h.call("place_id") if h.has_method("place_id") else "?", h.call("label") if h.has_method("label") else "", at.snapped(Vector3.ONE * 0.01), WorldTerrain.instance.height_at(at), near.snapped(Vector3.ONE * 0.01)])
	print("DOORS %d homes, %d approaches not walkable" % [homes.size(), bad])
	get_tree().quit()
