extends SceneTree
## Quality control: the railway's baked track (world/railway/track.scn): its top-level pieces, and which of
## them lie inside a box (x0 x1 z0 z1 on the command line).
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/qc/probe_track.gd -- -300 500 -588 188
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var box := Rect2(float(a[0]), float(a[2]), float(a[1]) - float(a[0]), float(a[3]) - float(a[2]))
	var track: Node3D = (load("res://world/railway/track.scn") as PackedScene).instantiate()
	var kinds := {}
	var inside := 0
	for c in track.get_children():
		var key := str(c.name).rstrip("0123456789_") + " [" + c.get_class() + "]"
		kinds[key] = int(kinds.get(key, 0)) + 1
		var b := AABB(); var first := true
		var stack: Array = [[c, (c as Node3D).transform if c is Node3D else Transform3D.IDENTITY]]
		while not stack.is_empty():
			var item: Array = stack.pop_back()
			var n: Node = item[0]; var x: Transform3D = item[1]
			for k in n.get_children(): stack.append([k, x * (k as Node3D).transform if k is Node3D else x])
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var bb: AABB = x * (n as MeshInstance3D).mesh.get_aabb()
				b = bb if first else b.merge(bb); first = false
		if not first and box.intersects(Rect2(b.position.x, b.position.z, b.size.x, b.size.z)):
			inside += 1
			if inside <= 60: print("IN ", c.name, " [", c.get_class(), "] x ", snappedf(b.position.x, 1), "..", snappedf(b.end.x, 1), " z ", snappedf(b.position.z, 1), "..", snappedf(b.end.z, 1), " children ", c.get_child_count(), " meta ", c.get_meta_list())
	print("TRACK children ", track.get_child_count(), " kinds ", kinds)
	print("TRACK pieces touching the box: ", inside)
	quit()
