extends Node
## Trees near a spot (--at x,z, --reach m): BiomeFoliage tree_canopies' roots and crowns. Prints TREE lines; quits.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var args := OS.get_cmdline_user_args()
	var at := args[args.find("--at") + 1].split(",")
	var reach := float(args[args.find("--reach") + 1]) if "--reach" in args else 15.0
	var spot := Vector3(float(at[0]), 0, float(at[1]))
	game.get("player").global_position = spot + Vector3(0, 3, 0)
	await get_tree().create_timer(40.0).timeout
	spot.y = WorldTerrain.instance.height_at(spot)
	var foliage := WorldTerrain.instance.get_node_or_null("BiomeFoliage")
	for t: Dictionary in foliage.tree_canopies(spot + Vector3(0, 8, 0), reach + 10.0):
		var root: Vector3 = t.get("root", Vector3.INF)
		print("TREE root (%.2f, %.2f, %.2f) crown %s radius %.1f, %.1f m from the spot" % [root.x, root.y, root.z, t.position, t.radius, Vector2(root.x - spot.x, root.z - spot.z).length()])
	get_tree().quit()
