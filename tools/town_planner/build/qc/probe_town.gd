extends SceneTree
## Quality control: what stands where in the built town scene, without running the game.
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/probe_town.gd -- [near x z r]... [name substring]...
## Prints every node within r metres of each "near" point, and for each name substring the matching nodes with
## their world position, scale and the world box of their meshes.

func _world(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var at: Node = n
	while at != null:
		if at is Node3D: t = (at as Node3D).transform * t
		at = at.get_parent()
	return t

func _box(n: Node) -> AABB:
	var out := AABB(); var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var at: Node = stack.pop_back()
		for c in at.get_children(): stack.append(c)
		if at is MeshInstance3D and (at as MeshInstance3D).mesh != null:
			var b: AABB = _world(at) * (at as MeshInstance3D).mesh.get_aabb()
			if first: out = b; first = false
			else: out = out.merge(b)
	return out

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var nears: Array = []; var names: Array[String] = []
	var i := 0
	while i < args.size():
		if args[i] == "near": nears.append([float(args[i + 1]), float(args[i + 2]), float(args[i + 3])]); i += 4
		else: names.append(args[i]); i += 1
	var root: Node = (load("res://world/towns/ponyville/town.tscn") as PackedScene).instantiate()
	var all: Array[Node] = root.find_children("*", "Node3D", true, false)
	for n in all:
		var w := _world(n)
		var path := str(root.get_path_to(n))
		for near: Array in nears:
			if Vector2(w.origin.x - near[0], w.origin.z - near[1]).length() <= near[2] and n.get_child_count() == 0 or (Vector2(w.origin.x - near[0], w.origin.z - near[1]).length() <= near[2] and n.scene_file_path != ""):
				print("NEAR %s,%s: %s [%s] at %s scene %s" % [near[0], near[1], path, n.get_class(), w.origin, n.scene_file_path])
		for s in names:
			if str(n.name).contains(s):
				var b := _box(n)
				print("NAME %s [%s] at %s scale %s box y %.2f..%.2f x %.1f..%.1f z %.1f..%.1f scene %s" % [path, n.get_class(), w.origin, w.basis.get_scale(), b.position.y, b.end.y, b.position.x, b.end.x, b.position.z, b.end.z, n.scene_file_path])
	quit()
