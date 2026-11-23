extends Node
## Carousel Boutique checks inside the real game (play test 2026-11-16): the front step's shadow flicker
## and the shop floor's furniture. Run through game.gd's `--lab` hook:
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title
##       --lab res://tools/town_planner/build/qc/lab_agent_c.gd [--lab-tag before]
## (set APPDATA to a scratch folder first so the test world stays out of your saves)
## - PROBE lines: every drawn surface at the front step (room frame metres), its shadow setting and draw
##   range, the heights where a straight-down ray meets each one, and any property change of geometry
##   near the door while the bursts run;
## - bursts of pictures at the step (inside the doorway looking out and down, outside looking at the door)
##   and pictures of the shop floor, saved to tools/town_planner/build/out/lab/agent_c/<tag>_*.png;
## - quits. Everything is printed with a LAB prefix.

const OUT := "res://tools/town_planner/build/out/lab/agent_c"
const BOUTIQUE := "Zones/PonyvilleTown/RNLScenery/Central/Boutique/rarityboutique_01"
## The step in the room frame (+Z out of the door, metres).
const STEP_BOX := AABB(Vector3(-1.3, -1.3, 4.2), Vector3(2.6, 1.8, 3.2))
## name, eye and target in the room frame
const STEP_VIEWS := [
	["step_in", Vector3(0.15, 1.65, 4.15), Vector3(0.0, -0.5, 6.3)],
	["step_out", Vector3(0.6, 1.0, 8.6), Vector3(0.0, 0.2, 5.0)],
	["step_close", Vector3(0.2, 1.5, 4.6), Vector3(0.0, -0.4, 5.9)],
]
const ROOM_VIEWS := [
	["room_door", Vector3(0.1, 1.7, 4.3), Vector3(0.0, 1.0, -1.5)],
	["room_above", Vector3(0.0, 3.9, 0.3), Vector3(0.0, 0.0, 0.0)],
	["room_left", Vector3(1.8, 1.7, 1.6), Vector3(-3.0, 0.6, 1.4)],
	["room_right", Vector3(-1.8, 1.7, 1.6), Vector3(3.0, 0.6, 1.8)],
	["room_back", Vector3(0.0, 1.7, -1.0), Vector3(0.0, 0.8, 4.5)],
	["room_chaise", Vector3(-1.0, 1.4, 1.2), Vector3(-4.2, 0.4, 0.0)],
	["room_shelf_right", Vector3(0.4, 1.6, 0.6), Vector3(2.9, 1.0, 2.9)],
	["room_shelf_left", Vector3(-0.4, 1.6, 0.6), Vector3(-2.9, 1.0, 2.9)],
	["room_shelf_edge", Vector3(1.2, 2.6, 4.2), Vector3(3.6, 0.6, 2.6)],
]
const BURST := 12
const BURST_GAP := 0.25

var game: Node
var frame: Node3D
var cam: Camera3D
var tag := "run"
var watched: Dictionary = {}   # GeometryInstance3D -> last state string


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		_watch()


func _go() -> void:
	if str(name) != "Lab":
		queue_free(); return
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--lab-tag" and i + 1 < args.size(): tag = args[i + 1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for i in 1200:
		if not is_instance_valid(game) or not ("player" in game):
			var scene := get_tree().current_scene
			game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(game):
		print("LAB no game scene; giving up"); get_tree().quit(); return
	var player: Node3D = game.get("player")
	var arrival: Variant = game.get("arrival")
	if arrival is Node and is_instance_valid(arrival) and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
		await get_tree().create_timer(3.0).timeout
	var tod := get_node_or_null("/root/TimeOfDay")
	if tod != null:
		tod.hours = 11.0; tod.paused = true
	var boutique := game.get_node_or_null(BOUTIQUE) as Node3D
	if boutique == null:
		print("LAB no boutique at ", BOUTIQUE); get_tree().quit(); return
	frame = boutique.get_node_or_null("BoutiqueRoomFrame") as Node3D
	if frame == null:
		print("LAB boutique not made walk-in"); get_tree().quit(); return
	print("LAB boutique frame origin ", frame.global_position, " basis z ", frame.global_basis.z)
	# Stand just inside the doorway, as the player did; the lab camera looks from the views.
	player.global_position = frame.to_global(Vector3(0, 0.05, 3.6))
	if "velocity" in player: player.set("velocity", Vector3.ZERO)
	cam = Camera3D.new(); cam.name = "LabCamera"; cam.far = 4000.0; cam.fov = 70.0
	game.add_child(cam)
	_set_view(STEP_VIEWS[0][1], STEP_VIEWS[0][2])
	await _wait(45.0)
	_probe_step()
	_probe_room()
	_collect_watch()
	# The player stood in the open doorway.
	var door := frame.get_node_or_null("BoutiqueDoor")
	if door != null and door.has_method("toggle_door"):
		door.call("toggle_door")
		await _wait(3.0)
		print("LAB door opening angle ", door.call("opening_angle"))
	for view: Array in STEP_VIEWS:
		_set_view(view[1], view[2])
		await _wait(2.0)
		for n in BURST:
			await _shot("%s_%s_%02d" % [tag, view[0], n])
			await _wait(BURST_GAP)
	# A head never holds still: the same views with a few millimetres of sway per frame.
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	for view: Array in STEP_VIEWS:
		for n in BURST:
			var sway := Vector3(rng.randf_range(-.02, .02), rng.randf_range(-.02, .02), rng.randf_range(-.02, .02))
			_set_view(view[1] + sway, view[2])
			await _wait(BURST_GAP)
			await _shot("%s_%s_sway_%02d" % [tag, view[0], n])
	# The same bursts with the sun moving (an hour a minute), as in play.
	if tod != null:
		tod.paused = false
		tod.set("day_length_minutes", 24.0)
	for view: Array in STEP_VIEWS:
		_set_view(view[1], view[2])
		await _wait(1.0)
		for n in BURST:
			await _shot("%s_%s_sun_%02d" % [tag, view[0], n])
			await _wait(BURST_GAP)
	if tod != null:
		tod.hours = 11.0; tod.paused = true
	# Out of the room's pictures: the player waits on the grass in front of the step.
	player.global_position = frame.to_global(Vector3(0, -0.3, 8.5))
	if "velocity" in player: player.set("velocity", Vector3.ZERO)
	for view: Array in ROOM_VIEWS:
		_set_view(view[1], view[2])
		await _wait(1.5)
		await _shot("%s_%s" % [tag, view[0]])
	print("LAB done")
	get_tree().quit()


func _set_view(eye: Vector3, target: Vector3) -> void:
	cam.look_at_from_position(frame.to_global(eye), frame.to_global(target), Vector3.UP)
	cam.make_current()


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT).path_join(label + ".png"))


func _state(gi: GeometryInstance3D) -> String:
	var mesh_id := 0
	if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null: mesh_id = (gi as MeshInstance3D).mesh.get_instance_id()
	return "vis=%s cast=%d range=%.1f-%.1f mesh=%d mat=%s" % [gi.is_visible_in_tree(), gi.cast_shadow,
		gi.visibility_range_begin, gi.visibility_range_end, mesh_id, str(gi.material_override)]


func _local_box(gi: GeometryInstance3D) -> AABB:
	return frame.global_transform.affine_inverse() * gi.global_transform * gi.get_aabb()


## Everything drawn near the door: watched for any change of visibility, shadow, range, mesh or material.
func _collect_watch() -> void:
	var near := AABB(Vector3(-8, -3, -6), Vector3(16, 14, 20))
	for node: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if gi.get_aabb().size.length() > 400.0: continue
		if _local_box(gi).intersects(near): watched[gi] = _state(gi)
	print("LAB PROBE watching ", watched.size(), " geometry instances near the door")


func _watch() -> void:
	for gi: Variant in watched.keys():
		if not is_instance_valid(gi):
			print("LAB PROBE CHANGE freed ", watched[gi]); watched.erase(gi); continue
		var now := _state(gi)
		if now != watched[gi]:
			print("LAB PROBE CHANGE t=%.2f %s: %s -> %s" % [Time.get_ticks_msec() / 1000.0, (gi as Node).get_path(), watched[gi], now])
			watched[gi] = now


func _probe_step() -> void:
	var to_frame := frame.global_transform.affine_inverse()
	var samples: Array[Vector2] = []
	for z: float in [4.3, 4.6, 4.9, 5.0, 5.2, 5.4, 5.5, 5.7, 6.0, 6.4, 6.8, 7.1]:
		for x: float in [-0.6, 0.0, 0.6]: samples.append(Vector2(x, z))
	for node: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if gi.get_aabb().size.length() > 400.0: continue
		var box := _local_box(gi)
		if not box.intersects(STEP_BOX): continue
		var info := "LAB PROBE STEP %s [%s] %s local box %s" % [gi.get_path(), gi.get_class(), _state(gi), box]
		if gi is MeshInstance3D: info += " layers=%d top_level=%s" % [gi.layers, gi.top_level]
		print(info)
		if not (gi is MeshInstance3D) or (gi as MeshInstance3D).mesh == null: continue
		var faces := (gi as MeshInstance3D).mesh.get_faces()
		if faces.size() > 900000: print("LAB PROBE   (too many faces to ray: ", faces.size() / 3, ")"); continue
		var xf := to_frame * gi.global_transform
		var local := PackedVector3Array(); local.resize(faces.size())
		for i in faces.size(): local[i] = xf * faces[i]
		var hits := PackedStringArray()
		for s: Vector2 in samples:
			var ys := PackedStringArray()
			for i in range(0, local.size(), 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(s.x, 3.0, s.y), Vector3.DOWN, local[i], local[i + 1], local[i + 2])
				if hit == null: hit = Geometry3D.ray_intersects_triangle(Vector3(s.x, 3.0, s.y), Vector3.DOWN, local[i + 2], local[i + 1], local[i])
				if hit != null and (hit as Vector3).y > -1.5 and (hit as Vector3).y < 0.6:
					var n := (local[i + 1] - local[i]).cross(local[i + 2] - local[i]).normalized()
					ys.append("%.4f(n.y %.2f)" % [(hit as Vector3).y, absf(n.y)])
			if not ys.is_empty(): hits.append("(%.1f,%.1f): %s" % [s.x, s.y, " ".join(ys)])
		if not hits.is_empty(): print("LAB PROBE   hits ", " | ".join(hits))
	# The sun and its shadow settings, for the bursts.
	for light: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var l := light as DirectionalLight3D
		print("LAB PROBE light %s visible=%s shadow=%s bias=%.3f normal_bias=%.3f max=%.0f mode=%d blur=%.2f" % [l.get_path(), l.visible, l.shadow_enabled, l.shadow_bias, l.shadow_normal_bias, l.directional_shadow_max_distance, l.directional_shadow_mode, l.shadow_blur])


## The shop floor's furniture (room frame metres), for the tidy-up.
func _probe_room() -> void:
	var interior := frame.get_node_or_null("UsableBoutique/BoutiqueInterior") as Node3D
	if interior == null: return
	for child: Node in interior.get_children():
		if not (child is Node3D): continue
		var n3 := child as Node3D
		var box := AABB(); var first := true
		for gi: Node in n3.find_children("*", "VisualInstance3D", true, false):
			var b := _local_box(gi as GeometryInstance3D) if gi is GeometryInstance3D else AABB()
			if b.size == Vector3.ZERO: continue
			box = b if first else box.merge(b); first = false
		if n3 is GeometryInstance3D: box = _local_box(n3 as GeometryInstance3D) if first else box.merge(_local_box(n3 as GeometryInstance3D))
		print("LAB ROOM %s at %s yaw %.1f box %s" % [n3.name, n3.position, rad_to_deg(n3.rotation.y), box])
	print("LAB ROOM stair foot ", (interior.get_meta("stair_path", []) as Array).slice(0, 2), " ground walk ", interior.get_meta("ground_walk_points", []))
	var chaise := interior.get_node_or_null("BoutiqueChaise") as Node3D
	if chaise != null:
		var cbox: AABB = AABB()
		var cfirst := true
		for gi: Node in chaise.find_children("*", "GeometryInstance3D", true, false):
			var b := _local_box(gi as GeometryInstance3D)
			cbox = b if cfirst else cbox.merge(b); cfirst = false
		var far := 0.0
		for i in 8: far = maxf(far, Vector2(cbox.get_endpoint(i).x, cbox.get_endpoint(i).z).length())
		print("LAB ROOM chaise farthest corner from the room's axis %.3f m (wall lining 4.68)" % far)
	var shelves := interior.get_node_or_null("BoutiqueShelves") as Node3D
	if shelves != null:
		for shelf: Node in shelves.get_children():
			var s3 := shelf as Node3D
			var visual := s3.get_node_or_null("ShelfVisual") as MeshInstance3D
			print("LAB ROOM shelf %s at %s yaw %.1f own box %s room box %s" % [s3.name, s3.position, rad_to_deg(s3.rotation.y), visual.get_aabb() if visual else AABB(), _local_box(visual) if visual else AABB()])
			if visual == null: continue
			var xf := frame.global_transform.affine_inverse() * visual.global_transform
			var corners := PackedStringArray()
			for i in 8:
				var p: Vector3 = xf * visual.get_aabb().get_endpoint(i)
				if p.y < 0.1: corners.append("(%.2f, %.2f) r %.3f" % [p.x, p.z, Vector2(p.x, p.z).length()])
			print("LAB ROOM shelf %s floor corners %s" % [s3.name, ", ".join(corners)])
