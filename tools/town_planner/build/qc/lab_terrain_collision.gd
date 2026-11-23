extends Node
## How far round the player the ground has collision: rays straight down at growing distances in four directions
## from --at x,z (where the player stands). Also Terrain3D's collision settings. Prints TCOL lines.
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
	var args := OS.get_cmdline_user_args()
	var f := (args[args.find("--at") + 1] if "--at" in args else "0,-192").split(",")
	var at := Vector3(float(f[0]), 0, float(f[1])); at.y = WorldTerrain.instance.height_at(at)
	game.get("player").global_position = at + Vector3.UP * 0.5
	await get_tree().create_timer(30.0).timeout
	var t3d: Node = WorldTerrain.instance.get("terrain")
	for prop in ["collision_mode", "collision_shape_size", "collision_radius", "collision_layer", "collision_target"]:
		if t3d != null and prop in t3d: print("TCOL terrain3d %s = %s" % [prop, t3d.get(prop)])
	print("TCOL player at ", (game.get("player") as Node3D).global_position.snapped(Vector3.ONE * 0.01))
	var space: PhysicsDirectSpaceState3D = get_tree().current_scene.get_world_3d().direct_space_state
	for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var line := "TCOL dir %s:" % dir
		for d: int in [1, 4, 8, 12, 16, 24, 32, 48, 64]:
			var p: Vector3 = at + dir * float(d)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0, 1))
			line += " %dm:%s" % [d, ("T" if (hit.collider as Object) == t3d or (hit.collider as Object).is_class("Terrain3D") else "o") if not hit.is_empty() else "-"]
		print(line)
	get_tree().quit()
