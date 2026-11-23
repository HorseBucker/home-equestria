extends Node
## The place directory's entries whose id or label matches --match (comma separated words). Prints PLACE lines.
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
	var args := OS.get_cmdline_user_args()
	var words: PackedStringArray = args[args.find("--match") + 1].to_lower().split(",") if "--match" in args else PackedStringArray()
	for e: Dictionary in preload("res://world/navigation/place_directory.gd").entries(get_tree()):
		var text := (str(e.id) + " " + str(e.label) + " " + str(e.get("alt", ""))).to_lower()
		var hit := words.is_empty()
		for w in words: if w in text: hit = true
		if hit:
			var node: Node = e.get("node")
			print("PLACE %s | %s | %s | %s | interior_goal %s | node %s %s" % [e.id, e.label, e.kind, (e.position as Vector3).snapped(Vector3.ONE * 0.1), e.get("interior_goal", false), node.get_script().resource_path.get_file() if node != null and node.get_script() != null else "-", get_tree().root.get_path_to(node) if node != null else ""])
	get_tree().quit()
