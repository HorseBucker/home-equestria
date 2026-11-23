extends Node
## The Golden Oak's loft: from the interior's middle outward (local directions --dirs "x,z;x,z"), where the loft floor
## ends and the wall stands (horizontal rays at loft height + 0.5 m, and rays down every 0.1 m). Prints LOFT lines.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	game.get("player").global_position = Vector3(-15, -10, -262)
	await get_tree().create_timer(25.0).timeout
	var inside: Node3D = get_tree().root.find_child("LibraryInterior", true, false)
	var loft := float(inside.get("loft_y"))
	print("LOFT interior at %s, basis yaw %.3f, loft_y %.2f, radius %.2f" % [inside.global_position, inside.global_basis.get_euler().y, loft, float(inside.get("radius"))])
	var space := get_viewport().get_world_3d().direct_space_state
	var args := OS.get_cmdline_user_args()
	for pair in args[args.find("--dirs") + 1].split(";"):
		var d := Vector3(float(pair.split(",")[0]), 0, float(pair.split(",")[1])).normalized()
		var from := inside.to_global(Vector3(0, loft + 0.5, 0) + d * 1.5)
		var to := inside.to_global(Vector3(0, loft + 0.5, 0) + d * 7.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
		var wall := (inside.to_local(hit.position) * Vector3(1, 0, 1)).length() if not hit.is_empty() else -1.0
		var floor_end := -1.0
		for k in 70:
			var r := 1.5 + k * 0.1
			var p := inside.to_global(Vector3(0, loft + 0.3, 0) + d * r)
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 0.6, 1))
			if down.is_empty() and floor_end < 0.0: floor_end = r
		print("LOFT dir (%.2f, %.2f): wall at r %.2f (%s), loft floor ends at r %.2f" % [d.x, d.z, wall, (hit.collider as Node).name if not hit.is_empty() else "-", floor_end])
	get_tree().quit()
