extends RefCounted
## Pause menu > Support > "Get unstuck" (player bug board #37: climbing in through a Golden Oak
## window left a player inside the tree, and the save could not go on until he got out). Puts the
## player outside the front door of the nearest house, else on the ground where he stands.
const REACH := 40.0

## What happened, for the Support page's status line.
static func run(game: Node) -> String:
	var body: Node3D = game.get("player") as Node3D if is_instance_valid(game) else null
	if body == null or not body.is_inside_tree() or not body.has_method("teleport"): return "Nothing to move right now."
	var here := body.global_position
	var nearest: Node3D = null
	var best := REACH
	for house: Node in body.get_tree().get_nodes_in_group("house_interiors"):
		if not (house is Node3D) or not house.has_method("outside"): continue
		var centre: Vector3 = house.center() if house.has_method("center") else (house as Node3D).global_position
		if here.distance_to(centre) < best: best = here.distance_to(centre); nearest = house
	var target := Vector3.INF
	if nearest != null:
		target = nearest.outside()
	elif WorldTerrain.instance != null:
		var ground: float = WorldTerrain.instance.height_at(here)
		if is_finite(ground): target = Vector3(here.x, ground, here.z)
	if not target.is_finite(): return "No safe ground found nearby. Try the map to travel instead."
	if "flying" in body: body.flying = false
	body.teleport(target + Vector3.UP * .3)
	print("[unstuck] %s -> %s" % [here.round(), target.round()])
	return "Moved you outside the nearest front door." if nearest != null else "Moved you onto the ground."
