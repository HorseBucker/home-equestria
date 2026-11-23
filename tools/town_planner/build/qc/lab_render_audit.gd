extends Node
## Render and collision audit of the loaded world (read-only). Groups every visible GeometryInstance3D by its source
## (the nearest ancestor saved as a scene file, else its path under the zone, two levels): instances, triangles
## (MultiMesh counted per instance), surfaces (each a draw call: Godot 4 does not batch separate MeshInstance3Ds),
## shadow casters, distance culling (visibility_range_end), LODs and unique materials. Then the colliders by shape type
## and source, and the renderer's own counts from fixed viewpoints. Prints AUDIT lines as TSV for a report.
const VIEWS := {"square_high": [Vector3(125, 25, -150), Vector3(125, -12, -230)], "street_eye": [Vector3(20, -10.3, -175), Vector3(120, -11, -190)],
	"market_eye": [Vector3(110, -10.3, -300), Vector3(130, -11, -270)], "overview": [Vector3(80, 90, -60), Vector3(80, -12, -220)]}

func _ready() -> void:
	_go.call_deferred()

func _tris(mesh: Mesh) -> int:
	var n := 0
	if mesh == null: return 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
		n += (idx.size() if not idx.is_empty() else verts.size()) / 3
	return n

var _mesh_tris := {}
func _mesh_tri_count(mesh: Mesh) -> int:
	if mesh == null: return 0
	var key := mesh.get_instance_id()
	if not _mesh_tris.has(key): _mesh_tris[key] = _tris(mesh)
	return _mesh_tris[key]

func _has_lods(mesh: Mesh) -> bool:
	if not mesh is ArrayMesh: return false
	var stored: Variant = mesh.get("_surfaces")
	if not stored is Array: return false
	for s: Variant in stored:
		if s is Dictionary and (s as Dictionary).has("lods") and not ((s as Dictionary).lods as Array).is_empty(): return true
	return false

func _source(node: Node, zone: Node) -> String:
	var up := node.get_parent()
	while up != null and up != zone:
		if not up.scene_file_path.is_empty() and up != get_tree().current_scene: return up.scene_file_path.get_file()
		up = up.get_parent()
	var path := str(zone.get_path_to(node)).split("/")
	return "/".join(path.slice(0, mini(2, path.size() - 1)))

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	game.get("player").global_position = Vector3(120, -10, -200)
	await get_tree().create_timer(25.0).timeout
	var zone: Node = get_tree().root.find_child("PonyvilleTown", true, false)
	print("AUDIT density\t%s" % preload("res://world/towns/ponyville/town_density.gd").current())
	var groups := {}
	var materials := {}
	for node: Node in zone.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if not g.is_visible_in_tree(): continue
		var key := _source(g, zone)
		var row: Dictionary = groups.get(key, {"inst": 0, "tris": 0, "surf": 0, "shadow": 0, "culled": 0, "lods": 0, "mm": 0, "meshes": {}})
		var tris := 0; var surf := 0; var count := 1; var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
			tris = _mesh_tri_count(mesh); surf = mesh.get_surface_count() if mesh else 0
			for s in surf:
				var mat := (g as MeshInstance3D).get_active_material(s)
				if mat: materials[mat.get_instance_id()] = true
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			var mm := (g as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			tris = _mesh_tri_count(mesh) * count; surf = mesh.get_surface_count() if mesh else 0
			row.mm += 1
		else: continue
		row.inst += count; row.tris += tris; row.surf += surf
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: row.shadow += count
		if g.visibility_range_end > 0.0: row.culled += count
		if mesh and _has_lods(mesh): row.lods += count
		if mesh: row.meshes[mesh.get_instance_id()] = true
		groups[key] = row
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a].tris > groups[b].tris)
	var total_t := 0; var total_s := 0
	for k: String in keys: total_t += int(groups[k].tris); total_s += int(groups[k].surf)
	print("AUDIT total\ttris %d\tsurfaces %d\tunique materials %d\tgroups %d" % [total_t, total_s, materials.size(), keys.size()])
	print("AUDIT geo\tsource\tinstances\ttris\tsurfaces\tshadow_casters\tvisibility_range\twith_lods\tmultimeshes\tunique_meshes")
	for k: String in keys.slice(0, 45):
		var r: Dictionary = groups[k]
		print("AUDIT geo\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d" % [k, r.inst, r.tris, r.surf, r.shadow, r.culled, r.lods, r.mm, r.meshes.size()])
	# colliders
	var shapes := {}
	for node: Node in zone.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		if cs.shape == null or cs.disabled: continue
		var body := cs.get_parent() as CollisionObject3D
		if body == null or body.collision_layer == 0: continue
		var kind := cs.shape.get_class()
		var faces := (cs.shape as ConcavePolygonShape3D).get_faces().size() / 3 if cs.shape is ConcavePolygonShape3D else ((cs.shape as ConvexPolygonShape3D).points.size() if cs.shape is ConvexPolygonShape3D else 0)
		var key := _source(cs, zone) + "\t" + kind
		var row: Dictionary = shapes.get(key, {"n": 0, "faces": 0})
		row.n += 1; row.faces += faces
		shapes[key] = row
	var sk := shapes.keys()
	sk.sort_custom(func(a, b): return shapes[a].faces > shapes[b].faces or (shapes[a].faces == shapes[b].faces and shapes[a].n > shapes[b].n))
	print("AUDIT col\tsource\tshape\tcount\tfaces_or_points")
	for k: String in sk.slice(0, 30): print("AUDIT col\t%s\t%d\t%d" % [k, shapes[k].n, shapes[k].faces])
	# what the renderer draws from fixed viewpoints
	var cam := Camera3D.new(); get_tree().current_scene.add_child(cam)
	cam.far = 1500.0
	for view: String in VIEWS:
		cam.global_position = VIEWS[view][0]; cam.look_at(VIEWS[view][1], Vector3.UP); cam.make_current()
		game.get("player").global_position = VIEWS[view][0] + Vector3(0, -1, 0) if view.ends_with("_eye") else Vector3(120, -10, -200)
		await get_tree().create_timer(3.0).timeout
		var obj := 0; var prim := 0; var draws := 0; var frames := 0; var ms := 0.0
		for i in 30:
			await get_tree().process_frame
			obj += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
			prim += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			ms += get_process_delta_time() * 1000.0; frames += 1
		print("AUDIT view\t%s\tobjects %d\tprimitives %d\tdraw calls %d\tframe %.1f ms" % [view, obj / frames, prim / frames, draws / frames, ms / frames])
	get_tree().quit()
