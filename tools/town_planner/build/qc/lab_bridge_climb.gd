extends Node
## How a higher arch slows a pony crossing a bridge: bridge_04 raised in height by each factor in --heights (its
## walk grid resampled), a pony walked from bank to bank and timed over the deck (and her slowest speed on it), at
## each size in --sizes. Prints CLIMB lines.
var game: Node
func _ready() -> void:
	_go.call_deferred()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	return args[args.find(name) + 1] if name in args else fallback

func _go() -> void:
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.25)
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	var bridge := get_tree().root.find_child(_arg("--bridge", "bridge_04"), true, false) as Node3D
	var axis := bridge.global_basis.x; axis.y = 0; axis = axis.normalized()
	var half := 0.0
	for m: Node in bridge.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		for k in 8: half = maxf(half, absf((box.get_endpoint(k) - bridge.global_position).dot(axis)))
	half = minf(half, bridge.global_basis.x.length() * 16.0)
	var a := bridge.global_position - axis * (half + 4.0); var b := bridge.global_position + axis * (half + 4.0)
	a.y = WorldTerrain.instance.height_at(a); b.y = WorldTerrain.instance.height_at(b)
	game.get("player").global_position = bridge.global_position + Vector3(0, 3, 14)
	await _wait(25.0)
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var executors: Dictionary = (director.get("actions") as Object).get("executors")
	var id := "golden_harvest" if executors.has("golden_harvest") else str(executors.keys()[0])
	var actor: Node3D = executors[id].get("actor")
	var nav: Node = actor.get_node("Navigator")
	nav.set("command_owner", "lab"); nav.set("wander_enabled", false)
	var base_scale := bridge.scale
	if "--backface" in OS.get_cmdline_user_args():
		for cs: Node in bridge.find_children("*", "CollisionShape3D", true, false):
			var shape := (cs as CollisionShape3D).shape
			if shape is ConcavePolygonShape3D:
				print("CLIMB backface_collision was ", (shape as ConcavePolygonShape3D).backface_collision)
				var copy := shape.duplicate() as ConcavePolygonShape3D
				copy.backface_collision = true
				(cs as CollisionShape3D).shape = copy
	var deck_half := 0.0
	# the deck's own ends: where its surface leaves the bank (rays down along the axis)
	var space: PhysicsDirectSpaceState3D = bridge.get_world_3d().direct_space_state
	print("CLIMB bridge %s half span %.2f, base scale %s" % [bridge.name, half, base_scale])
	for size_text: String in _arg("--sizes", "1.0,1.35").split(","):
		var size := float(size_text)
		if actor.has_method("set_body_scale"): actor.call("set_body_scale", size)
		for h_text: String in _arg("--heights", "1.0,1.25,1.5,1.75").split(","):
			var h := float(h_text)
			bridge.scale = Vector3(base_scale.x, base_scale.y * h, base_scale.z)
			await _wait(0.5)
			for service: Node in get_tree().get_nodes_in_group("pony_navigation"):
				if service.has_method("notify_geometry_changed"): service.call("notify_geometry_changed", AABB(bridge.global_position - Vector3(half + 6, 6, half + 6), Vector3(half * 2 + 12, 12, half * 2 + 12)))
			await _wait(4.0)
			# the deck's steepest slope now
			var prev := INF; var steepest := 0.0; var top := -INF
			for k in range(-int(half * 4), int(half * 4) + 1):
				var at := bridge.global_position + axis * (k * 0.25)
				var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 10.0, at + Vector3.DOWN * 10.0))
				if hit.is_empty(): continue
				var y: float = (hit.position as Vector3).y
				top = maxf(top, y)
				if is_finite(prev): steepest = maxf(steepest, rad_to_deg(atan2(absf(y - prev), 0.25)))
				prev = y
			for leg in int(_arg("--legs", "2")):
				var from := a if leg % 2 == 0 else b; var to := b if leg % 2 == 0 else a
				if actor.has_method("reset_motion"): actor.call("reset_motion", Transform3D(Basis.IDENTITY, from + Vector3.UP * 0.3))
				await _wait(2.0)
				nav.call("go_to", to, int(_arg("--gait", "0")))
				var t_in := -1.0; var t_out := -1.0; var slowest := INF; var t := 0.0
				var flat_speed := 0.0; var flat_n := 0
				while t < 60.0:
					await get_tree().physics_frame
					t += get_physics_process_delta_time()
					var p := actor.global_position
					var along := (p - bridge.global_position).dot(axis) * (1.0 if leg % 2 == 0 else -1.0)
					var v := Vector2(actor.get("velocity").x, actor.get("velocity").z).length() if actor.get("velocity") != null else 0.0
					if along < -half - 0.5 and along > -half - 3.5 and v > 0.2: flat_speed += v; flat_n += 1
					if t_in < 0.0 and along > -half: t_in = t
					if t_in >= 0.0 and t_out < 0.0:
						if along > half: t_out = t
						elif along > -half + 1.0 and along < half - 1.0: slowest = minf(slowest, v)
					if Vector2(p.x - to.x, p.z - to.z).length() < 1.0: break
					if "--trace" in OS.get_cmdline_user_args() and Engine.get_physics_frames() % 120 == 0 and (not "--stalls" in OS.get_cmdline_user_args() or (v < 0.4 and absf(along) < half)):
						var above: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.2, p + Vector3.UP * 4.0))
						var below: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.2, p + Vector3.DOWN * 2.0))
						var pts: PackedVector3Array = nav.get("path")
						var near_pts := []
						for q: Vector3 in pts:
							if q.distance_to(p) < 4.0: near_pts.append(q.snapped(Vector3.ONE * 0.1))
						print("CLIMB   t %.1f at %s along %.2f v %.2f state %s floor %s above %s below %s path %d near %s" % [t, p.snapped(Vector3.ONE * 0.01), along, v, nav.get("state"), actor.call("is_on_floor"), (above.position as Vector3).snapped(Vector3.ONE * 0.01) if not above.is_empty() else "-", (below.position as Vector3).snapped(Vector3.ONE * 0.01) if not below.is_empty() else "-", pts.size(), near_pts])
				var crossing := t_out - t_in if t_out > 0.0 and t_in >= 0.0 else -1.0
				var flat := flat_speed / maxi(flat_n, 1)
				print("CLIMB size %.2f height x%.2f: rise %.2f m, steepest %.1f deg; leg %d deck %.2f s (flat pace %.2f m/s would take %.2f s), slowest %.2f m/s" % [size, h, top - bridge.global_position.y, steepest, leg, crossing, flat, half * 2.0 / maxf(flat, 0.01), slowest])
	get_tree().quit()
