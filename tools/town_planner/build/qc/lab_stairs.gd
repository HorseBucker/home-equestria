extends Node
## A height profile along a line (--from x,z --to x,z, every 0.1 m): the highest solid surface under each point (rays
## down, layer 1) and the terrain's height; for steps a pony must climb. Prints STAIR lines; quits.
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
	var f := args[args.find("--from") + 1].split(","); var t := args[args.find("--to") + 1].split(",")
	var a := Vector3(float(f[0]), 0, float(f[1])); var b := Vector3(float(t[0]), 0, float(t[1]))
	game.get("player").global_position = a + Vector3(0, 3, 4)
	await get_tree().create_timer(30.0).timeout
	var space := get_viewport().get_world_3d().direct_space_state
	var n := int(a.distance_to(b) / 0.1)
	var last := NAN
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, float(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--top") + 1]) if "--top" in OS.get_cmdline_user_args() else -10.0, p.z), Vector3(p.x, -14.0, p.z), 1))
		var y: float = hit.position.y if not hit.is_empty() else NAN
		var what: String = str((hit.collider as Node).get_path()).get_file() if not hit.is_empty() else "-"
		if is_nan(last) or absf(y - last) > 0.005:
			print("STAIR %.1f m: %.3f (terrain %.3f) %s" % [a.distance_to(p), y, WorldTerrain.instance.height_at(p), what])
		last = y
	get_tree().quit()
