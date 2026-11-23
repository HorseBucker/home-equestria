extends Node
## Cherry Berry fetching the balloon (balloon_fetch.gd, walk_balloon.gd): sets it down on open ground --away m from its
## pad (default 150), marks it away 7 hours, stands Anon --anon m from it (default 25: not asked; under 12: asked,
## answered --answer take/leave/later), then logs Cherry, the balloon and its rope every 3 s. Prints FETCH lines.
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
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance) and game.get("balloon") != null: break
		await _wait(0.25)
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	await _wait(20.0)
	var ship: Node3D = game.get("balloon")
	var home: Transform3D = ship.get("home")
	var fountain := Vector3(114, -12, -189.4)
	var away := float(_arg("--away", "150"))
	var space := get_viewport().get_world_3d().direct_space_state
	var spot := Vector3.INF
	for k in 60:
		var dir := Vector3(cos(k * 0.7), 0, sin(k * 0.7))
		var p := home.origin + dir * (away + (k % 5) * 6.0)
		var ok := true
		for o: Vector3 in [Vector3.ZERO, Vector3(4, 0, 0), Vector3(-4, 0, 0), Vector3(0, 0, 4), Vector3(0, 0, -4)]:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + o + Vector3.UP * 60, p + o + Vector3.DOWN * 60, 1, [ship.get_rid()]))
			if k < 3 and o == Vector3.ZERO: print("FETCH probe %s -> %s" % [p.round(), (hit.collider as Object).get_class() + " " + str((hit.collider as Node).name) if not hit.is_empty() else "nothing"])
			if not hit.is_empty() and not (hit.collider as Object).is_class("Terrain3D"): ok = false; break
			if WorldTerrain.instance.height_at(p + o) < -12.3: ok = false; break      # (not by a lake or stream)
			if o == Vector3.ZERO: p.y = WorldTerrain.instance.height_at(p)
		if ok: spot = p; break
	print("FETCH pad %s, balloon set down at %s (%.0f m)" % [home.origin.round(), spot.round(), Vector2(spot.x - home.origin.x, spot.z - home.origin.z).length()])
	game.get("player").global_position = spot + Vector3(float(_arg("--anon", "25")), 1.0, 0.0)
	await _wait(2.0)
	ship.call("restore", {"position": [spot.x, spot.y, spot.z], "yaw": 0.0})
	await _wait(3.0)
	var state: Dictionary = (game.get("world_context") as Object).get("state")
	var chose := "--chose" in OS.get_cmdline_user_args()      # her model picks [use: balloon_fetch] (no 6-hour wait)
	state["balloon_away_since"] = float(TimeOfDay.day) * 24.0 + float(TimeOfDay.hours) - (0.5 if chose else 7.0)
	var fetch: Node = get_tree().root.find_child("BalloonFetch", true, false)
	print("FETCH anon at %s, balloon at %s" % [game.get("player").global_position.round(), ship.global_position.round()])
	fetch.set("_wait", 0.1)
	var cherry: Node3D = null
	var answered := false
	var scale_arg := float(_arg("--scale", "0"))
	if scale_arg > 0.0:
		var pop_s: Node = get_tree().get_first_node_in_group("pony_populations")
		var cs: Node3D = (pop_s.get("live") as Dictionary).get("cherry_berry", {}).get("actor")
		if cs.has_method("set_body_scale"): cs.call("set_body_scale", scale_arg)
		else: cs.set("body_scale", scale_arg)
		print("FETCH cherry body_scale ", cs.get("body_scale"))
	_watch.call_deferred(ship)
	if chose:
		await _wait(16.0)
		var population0: Node = get_tree().get_first_node_in_group("pony_populations")
		var c0: Node3D = (population0.get("live") as Dictionary).get("cherry_berry", {}).get("actor")
		var mech0: Node = (load("res://world/mechanics/mechanics.gd") as Script).call("of", get_tree())
		var row: Dictionary = mech0.call("_ai_row", "cherry_berry", c0)
		print("FETCH her actions: ", row.get("keys", {}).get("stations", []))
		for line: Variant in row.get("lines", []): if str(line).contains("balloon"): print("FETCH line: ", line)
		print("FETCH dispatch: ", mech0.call("dispatch", "cherry_berry", c0, {"type": "use", "station_id": "balloon_fetch"}))
	for i in 200:
		await _wait(3.0)
		var population: Node = get_tree().get_first_node_in_group("pony_populations")
		var live: Dictionary = population.get("live")
		cherry = live.get("cherry_berry", {}).get("actor") if live.has("cherry_berry") else null
		if bool(fetch.get("_asking")) and not answered and _arg("--answer", "take") == "none":
			answered = true
			var mech: Node = (load("res://world/mechanics/mechanics.gd") as Script).call("of", get_tree())
			print("FETCH asked; not answering. Her offered actions while she waits: ", mech.call("_ai_row", "cherry_berry", cherry).get("keys", {}) if mech != null and mech.has_method("_ai_row") else "?")
		if bool(fetch.get("_asking")) and not answered:
			answered = true
			await _wait(2.0)
			print("FETCH asked; answering ", _arg("--answer", "take"))
			fetch.call("_answered", _arg("--answer", "take"))
		var rope := ship.find_child("BalloonRope", true, false) != null or (cherry != null and cherry.find_child("BalloonRope", true, false) != null)
		var d := Vector2(ship.global_position.x - home.origin.x, ship.global_position.z - home.origin.z).length()
		print("FETCH %3ds cherry %s | balloon %s, %.0f m from pad, %.1f m up, rope %s | %s" % [i * 3, cherry.global_position.round() if cherry else "-", ship.global_position.round(), d,
			ship.global_position.y - WorldTerrain.instance.height_at(ship.global_position), rope, cherry.get_meta("life_intent", "") if cherry else ""])
		if d < 2.0 and bool(ship.get("landed")) and i > 3: print("FETCH home"); break
		if i > 3 and not rope and cherry != null and not str(cherry.get_meta("life_intent", "")).contains("balloon") and d > 2.0 and i > 100: break
	get_tree().quit()


## Every rendered frame while the rope is on: the balloon's frame-to-frame step (smooth = no spikes), and pictures.
func _watch(ship: Node3D) -> void:
	var shots := _arg("--shots", "")
	var last := Vector3.INF
	var steps: Array[float] = []
	var shot_at := [1.0, 4.0, 12.0, 20.0, 30.0]
	var shot_i := 0
	var on_for := 0.0
	var tag := _arg("--scale", "1")
	while is_instance_valid(ship):
		await get_tree().process_frame
		var tow: Node = get_tree().root.find_child("BalloonTow", true, false)
		if tow == null:
			if not steps.is_empty():
				steps.sort()
				print("FRAMES %d, step median %.3f m, p95 %.3f m, max %.3f m" % [steps.size(), steps[steps.size() / 2], steps[int(steps.size() * 0.95)], steps[-1]])
				steps.clear()
			last = Vector3.INF; continue
		on_for += get_process_delta_time()
		var at := ship.global_position
		if last.is_finite(): steps.append(at.distance_to(last))
		last = at
		if steps.size() % 240 == 239:
			var sorted := steps.slice(steps.size() - 239); sorted.sort()
			var ratio: float = sorted[-1] / maxf(sorted[sorted.size() / 2], 0.0001)
			print("FRAMES %s: step median %.3f m, max %.3f m (max/median %.1f)" % [tow.get("mode"), sorted[sorted.size() / 2], sorted[-1], ratio])
		if not shots.is_empty() and shot_i < shot_at.size() and on_for >= shot_at[shot_i]:
			var cherry: Node3D = tow.get("actor")
			var drawn: Transform3D = cherry.get_global_transform_interpolated()
			var bite: Vector3 = tow.call("_bite", drawn)
			var cam := Camera3D.new(); get_tree().current_scene.add_child(cam)
			var s := float(cherry.get("body_scale"))
			for view in 3:
				var side: Vector3 = [drawn.basis.x, -drawn.basis.z, (drawn.basis.x - drawn.basis.z + drawn.basis.y * 0.6)][view].normalized()
				cam.global_position = bite + side * 0.9 * s + Vector3.UP * 0.15 * s
				cam.look_at(bite + Vector3.UP * 0.1 * s, Vector3.UP); cam.fov = 40.0; cam.make_current()
				await get_tree().process_frame; await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(shots.path_join("rope_%s_%d_%s.png" % [tag, shot_i, ["side", "front", "three"][view]]))
			cam.queue_free()
			var main: Variant = get_viewport().get_camera_3d()
			print("FETCH shot %d at %.0fs (%s) bite-to-lip %.3f m" % [shot_i, on_for, tow.get("mode"), bite.distance_to(tow.call("_bone_at", drawn, true))])
			shot_i += 1
