extends SceneTree
## Build step 5 (applying half): move, remove and copy the baked town scenery as plan_scenery.py decided
## (build/out/scenery_moves.json), in world/props/ponyville/rnl_scenery.scn (its baker is not in the source
## release, so the baked scene is edited directly; node names stay, so the game's attachments still find them).
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/apply_scenery.gd
## Run it on the rnl_scenery.scn from git.

const SCENE := "res://world/props/ponyville/rnl_scenery.scn"
const MOVES := "res://tools/town_planner/build/out/scenery_moves.json"


func _init() -> void:
	var moves: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOVES))
	var packed: PackedScene = load(SCENE)
	var root: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var by_name := {}
	for n in root.find_children("*", "Node3D", true, false):
		if moves.has(str(n.name)) and not by_name.has(str(n.name)): by_name[str(n.name)] = n
	# bridge copies first, from the old bridge before it moves
	var made := 0
	for id: String in moves:
		var m: Dictionary = moves[id]
		if m.action == "bridge" and m.get("copy_of") != null:
			var source: Node3D = by_name.get(str(m.copy_of))
			if source == null: print("no bridge to copy for ", id); continue
			var copy: Node3D = (load(source.scene_file_path) as PackedScene).instantiate()
			copy.name = id
			for meta in source.get_meta_list(): copy.set_meta(meta, source.get_meta(meta))
			source.get_parent().add_child(copy); copy.owner = root
			by_name[id] = copy; made += 1
	# plain copies (the springs' boulders), likewise from their sources before those are moved or removed
	var copied := 0
	for id: String in moves:
		var m: Dictionary = moves[id]
		if m.action != "copy": continue
		var source: Node3D = by_name.get(str(m.copy_of))
		if source == null:
			for n in root.find_children(str(m.copy_of), "Node3D", true, false): source = n; break
		if source == null or source.scene_file_path == "": print("nothing to copy for ", id); continue
		var copy: Node3D = (load(source.scene_file_path) as PackedScene).instantiate()
		copy.name = id
		for meta in source.get_meta_list(): copy.set_meta(meta, source.get_meta(meta))
		if copy.has_meta("ai_id"): copy.set_meta("ai_id", id)
		source.get_parent().add_child(copy); copy.owner = root
		copy.transform = Transform3D(Basis(Vector3.UP, float(m.yaw)).scaled(Vector3.ONE * float(m.size)), Vector3(float(m.x), float(m.y), float(m.z)))
		copied += 1
	var moved := 0; var removed := 0; var missing := []
	for id: String in moves:
		var m: Dictionary = moves[id]
		if m.action == "copy": continue
		var node: Node3D = by_name.get(id)
		if node == null: missing.append(id); continue
		# a building's own extras beside it (tools/rnl_scenery/build.gd: "<id>_foundation", "<id>_ramp")
		var extras: Array[Node3D] = []
		for sibling in node.get_parent().get_children():
			if sibling != node and sibling is Node3D and str(sibling.name).begins_with(id + "_"): extras.append(sibling)
		if m.action == "remove":
			for x in extras: x.get_parent().remove_child(x); x.free()
			node.get_parent().remove_child(node); node.free(); removed += 1
			continue
		var before := node.transform
		node.position = Vector3(float(m.x), float(m.y), float(m.z))
		if m.action == "bridge":
			node.rotation = Vector3(0.0, float(m.yaw), float(m.roll))
			node.scale = Vector3(float(m.scale[0]), float(m.scale[1]), float(m.scale[2]))
		elif m.get("level", false):
			node.rotation = Vector3(0.0, float(m.yaw), 0.0)
		else:
			node.rotation = Vector3(node.rotation.x, float(m.yaw), node.rotation.z)
		if m.has("nav_anchor"):
			# where ponies meet "at" this building (PlaceDirectory reads a NavigationAnchor child)
			var anchor := Marker3D.new(); anchor.name = "NavigationAnchor"
			node.add_child(anchor); anchor.owner = root
			anchor.position = node.transform.affine_inverse() * Vector3(float(m.nav_anchor[0]), node.position.y, float(m.nav_anchor[1]))
		var delta := node.transform * before.affine_inverse()
		for x in extras: x.transform = delta * x.transform
		moved += 1
	var out := PackedScene.new()
	var err := out.pack(root)
	if err == OK: err = ResourceSaver.save(out, SCENE, ResourceSaver.FLAG_COMPRESS)
	print("SCENERY moved %d, removed %d, bridges copied %d, rocks copied %d, not found %s; save %d" % [moved, removed, made, copied, missing, err])
	quit()
