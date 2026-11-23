extends Node
## The three Town Hall bridges (bridge_03, _04, _07): scale, each part's world box (posts' feet), the ground under
## each part, and the deck's profile along the span by rays down the middle (height, slope). Prints BRIDGE lines.
const IDS := ["bridge_03", "bridge_04", "bridge_07"]
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
	game.get("player").global_position = Vector3(165, -10, -170)
	await get_tree().create_timer(30.0).timeout
	var space: PhysicsDirectSpaceState3D = get_tree().current_scene.get_world_3d().direct_space_state
	for id: String in IDS:
		var b := get_tree().root.find_child(id, true, false) as Node3D
		if b == null: print("BRIDGE no ", id); continue
		print("BRIDGE %s at %s basis scale %s scene %s" % [id, b.global_position, b.global_basis.get_scale(), b.scene_file_path])
		for m: Node in b.find_children("*", "", true, false):
			if m is MeshInstance3D:
				var box: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
				var c := box.get_center()
				print("BRIDGE   part %s: bottom %.2f top %.2f centre (%.1f, %.1f) size %s ground %.2f" % [b.get_path_to(m), box.position.y, box.end.y, c.x, c.z, box.size.snapped(Vector3.ONE * 0.01), WorldTerrain.instance.height_at(c)])
			elif m is CollisionShape3D:
				print("BRIDGE   shape %s %s" % [b.get_path_to(m), (m as CollisionShape3D).shape.get_class()])
		var axis := b.global_basis.x.normalized()
		var prev := INF
		var line := ""
		var steepest := 0.0
		for k in range(-40, 41):
			var at := b.global_position + axis * (k * 0.25)
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 8.0, at + Vector3.DOWN * 8.0))
			if hit.is_empty(): continue
			var y: float = (hit.position as Vector3).y
			var ground := WorldTerrain.instance.height_at(at)
			if is_finite(prev):
				var deg := rad_to_deg(atan2(absf(y - prev), 0.25))
				steepest = maxf(steepest, deg)
				if k % 4 == 0: line += " %.2f:%.2f(%.0f°,g%.2f)" % [k * 0.25, y, deg, ground]
			prev = y
		print("BRIDGE   deck steepest %.1f°; along span:%s" % [steepest, line])
	get_tree().quit()
