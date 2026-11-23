extends SceneTree
## Build step 5b (after apply_scenery.gd): the three bridges to Town Hall, rounder (plan_scenery.py ROUND_BRIDGES).
## Each takes its scale from build/out/scenery_moves.json (a higher arch: 1.3 times the climb), and its own copy of the
## bridge model with the four posts reaching the ground under them (the "post_floors" plan_scenery.py found there;
## the model's posts end in flat feet 4.24 units under its node, its only vertices that low, and squashed to a
## bridge's height they stopped half way down the stream). A post is only ever lengthened. Safe to run again: it
## starts each copy from the model itself.
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/round_bridges.gd

const SCENE := "res://world/props/ponyville/rnl_scenery.scn"
const MOVES := "res://tools/town_planner/build/out/scenery_moves.json"
const MODEL := "res://world/props/rnl/rnl_ponyville_bridge/prefab.scn"
const OUT := "res://world/props/rnl/rnl_ponyville_bridge/round_%s.res"
const FOOT_Y := -4.2                # model units: under this, a vertex is a post's foot
const FEET := [Vector2(-5.905, 4.54), Vector2(5.905, 4.54), Vector2(-5.905, -4.55), Vector2(5.905, -4.55)]   # (x, z), plan_scenery.py POST_FEET


func _init() -> void:
	var moves: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOVES))
	var model: Node = (load(MODEL) as PackedScene).instantiate()
	var source: Mesh = (model.get_node("Mesh1") as MeshInstance3D).mesh
	var root: Node = (load(SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var done := 0
	for id: String in moves:
		var m: Dictionary = moves[id]
		if not m.has("post_floors"): continue
		var bridge := root.find_child(id, true, false) as Node3D
		if bridge == null: print("ROUND no ", id); continue
		var sc: Array = m.scale
		bridge.scale = Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
		var sy := float(sc[1])
		var node_y := float(m.y)
		var floors: Array = m.post_floors
		var arrays := source.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var moved := 0
		for i in vertices.size():
			var v := vertices[i]
			if v.y > FOOT_Y: continue
			var nearest := 0
			for f in FEET.size():
				if Vector2(v.x, v.z).distance_to(FEET[f]) < Vector2(v.x, v.z).distance_to(FEET[nearest]): nearest = f
			var want := (float(floors[nearest]) - node_y) / sy      # (the bridges have no roll: plan_scenery.py)
			if want < v.y: vertices[i].y = want; moved += 1
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, source.surface_get_material(0))
		mesh.resource_name = "Rounder %s (round_bridges.gd)" % id
		var path := OUT % id
		print("ROUND %s: scale %s, %d foot vertices lowered (post bottoms %s), save %d" % [id, bridge.scale, moved, floors, ResourceSaver.save(mesh, path)])
		root.set_editable_instance(bridge, true)
		var shown := bridge.get_node("Mesh1") as MeshInstance3D
		shown.mesh = load(path)
		_fill_feet(root, bridge, model, sy)
		done += 1
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK: err = ResourceSaver.save(packed, SCENE, ResourceSaver.FLAG_COMPRESS)
	print("ROUND bridges %d, save %d" % [done, err])
	model.free()
	quit()


## The space under each end of the deck, filled (collision only). The deck is a thin shell that meets the bank at its
## ends and climbs away from it; a pony walking onto it now and then went in under its edge instead, along the bank,
## and stood wedged under the deck (at 1.35, 0.9 m of deck over her) while her route led over it: about one crossing
## in five stalled 18 s (qc/lab_bridge_climb.gd --stalls). Each end gets a solid block from the deck's end inward to
## where the deck stands FILL_RISE above the bank, from just under the deck down to FILL_DEPTH below the bank: too
## low there for any pony, so nothing is lost but the pocket.
const FILL_RISE := 1.5          # metres above the bridge's foot
const FILL_DEPTH := 1.0         # metres under it
const FILL_UNDER := 0.03        # metres under the deck's surface
func _fill_feet(root: Node, bridge: Node3D, model: Node, sy: float) -> void:
	var old := bridge.get_node_or_null("FootFill")
	if old != null: old.free()
	# the deck's surface along the model's middle, from its collision (model units)
	var faces := PackedVector3Array()
	var solid := model.get_node("Solid") as StaticBody3D
	for cs: Node in solid.get_children():
		if cs is CollisionShape3D and (cs as CollisionShape3D).shape is ConcavePolygonShape3D:
			for v: Vector3 in ((cs as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces(): faces.append((cs as CollisionShape3D).transform * v)
	var width := 0.0
	for v: Vector3 in faces: width = maxf(width, absf(v.z))
	var deck := func(x: float) -> float:
		var top := -INF
		for i in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 20, 0), Vector3.DOWN, faces[i], faces[i + 1], faces[i + 2])
			if hit != null: top = maxf(top, (hit as Vector3).y)
		return top
	var rise := FILL_RISE / sy; var bottom := -FILL_DEPTH / sy; var under := FILL_UNDER / sy
	var body := StaticBody3D.new(); body.name = "FootFill"
	body.collision_layer = solid.collision_layer; body.collision_mask = solid.collision_mask
	bridge.add_child(body); body.owner = root
	for side: float in [-1.0, 1.0]:
		# from the end of the deck inward, in 0.1-unit steps, while it stays under `rise`
		var points: Array[Vector2] = []
		var x := 16.0 * side
		while absf(x) > 0.0:
			var y: float = deck.call(x)
			if is_finite(y):
				if y > rise: break
				points.append(Vector2(x, y - under))
			x -= side * 0.1
		if points.size() < 3: print("ROUND   %s: no deck end found on side %+.0f" % [bridge.name, side]); continue
		# a convex prism: the deck's chord on top (the arch lies above it), the floor FILL_DEPTH under the foot
		var a: Vector2 = points[0]; var b: Vector2 = points[-1]
		var hull := PackedVector3Array()
		for z: float in [-width, width]:
			hull.append_array([Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(b.x, bottom, z), Vector3(a.x, bottom, z)])
		var shape := ConvexPolygonShape3D.new(); shape.points = hull
		var cs := CollisionShape3D.new(); cs.name = "End%+.0f" % side; cs.shape = shape
		body.add_child(cs); cs.owner = root
		print("ROUND   %s foot fill %+.0f: model x %.2f to %.2f, deck %.2f to %.2f, floor %.2f" % [bridge.name, side, a.x, b.x, a.y + under, b.y + under, bottom])
