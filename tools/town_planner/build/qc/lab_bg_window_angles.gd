extends Node
## Steep-angle pictures of background houses' windows and doors (the 2026-11-22 play test's see-through gaps): for each
## design, its windows and front door, from 50 degrees to either side and from below, 3 m off. Positions come from the
## real design (its Glass and DoorReveal parts) through the background house's transform. --shots DIR --tag NAME.
## Prints BGWIN lines.
const HOUSES := {"a": Vector2(58.76, -163.02), "b": Vector2(45.21, -188.81), "c": Vector2(71.59, -203.43), "e": Vector2(-10.4, -140.85),
	"f": Vector2(-4.19, -147.55), "g": Vector2(74, -164.97), "h": Vector2(54.21, -231.05)}
const SCENES := {"a": "house_a.tscn", "b": "house_b.tscn", "c": "house_c.tscn", "e": "house_e.scn", "f": "house_f.scn", "g": "house_g.scn", "h": "house_h.scn"}

func _ready() -> void:
	_go.call_deferred()

func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	return args[args.find(name) + 1] if name in args else fallback

func _to_house(node: Node, house: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != house:
		if n is Node3D: xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	game.get("player").global_position = Vector3(30, -10, -170)
	await get_tree().create_timer(20.0).timeout
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.set("hours", 11.0)
	var cam := Camera3D.new(); get_tree().current_scene.add_child(cam); cam.fov = 60.0
	var shots := _arg("--shots", ""); var tag := _arg("--tag", "x")
	var only := _arg("--only", "")
	for key: String in HOUSES:
		if not only.is_empty() and not key in only: continue
		var want: Vector2 = HOUSES[key]
		var bg: Node3D = null; var best := 1e9
		for n: Node in get_tree().root.find_children("*", "Node3D", true, false):
			if not n.has_meta("background_house"): continue
			var d := Vector2((n as Node3D).global_position.x - want.x, (n as Node3D).global_position.z - want.y).length()
			if d < best: best = d; bg = n
		if bg == null or best > 3.0: print("BGWIN no house near ", want); continue
		var design: Node = (load("res://world/towns/ponyville/" + SCENES[key]) as PackedScene).instantiate()
		var targets := []      # [name, centre in house space, outward]
		for m: Node in design.find_children("*", "MeshInstance3D", true, false):
			var n := str(m.name)
			if not (n.ends_with("Glass") or n == "DoorReveal"): continue
			var box: AABB = _to_house(m, design) * (m as MeshInstance3D).mesh.get_aabb()
			var c := box.get_center()
			var out := Vector3(signf(c.x), 0, 0) if box.size.x < box.size.z else Vector3(0, 0, signf(c.z))
			targets.append([n, c, out])
		design.free()
		var xf := bg.global_transform
		var count := 0
		for t: Array in targets:
			if count >= 8 and t[0] != "DoorReveal": continue
			count += 1
			var at: Vector3 = xf * (t[1] as Vector3)
			var out: Vector3 = (xf.basis * (t[2] as Vector3)).normalized()
			var side := out.cross(Vector3.UP).normalized()
			var views := {"l": (out + side * 1.2).normalized() * 3.0 + Vector3.UP * 0.3, "r": (out - side * 1.2).normalized() * 3.0 + Vector3.UP * 0.3,
				"low": (out * 1.0 + Vector3.DOWN * 0.9).normalized() * 3.0, "high": (out * 1.0 + Vector3.UP * 1.0).normalized() * 3.0}
			for v: String in views:
				var from: Vector3 = at + views[v]
				game.get("player").global_position = from + Vector3(0, -40, 0)
				cam.global_position = from; cam.look_at(at, Vector3.UP); cam.make_current()
				await get_tree().create_timer(0.6).timeout
				get_viewport().get_texture().get_image().save_png(shots.path_join("win_%s_%s_%s_%s.png" % [key, t[0], v, tag]))
		print("BGWIN %s %d targets" % [key, targets.size()])
	get_tree().quit()
