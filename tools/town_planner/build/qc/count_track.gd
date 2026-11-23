extends SceneTree
## Quality control: what the railway's track scene holds, inside and outside a box, for two files (before and after
## cut_track.gd): godot --headless --path <project> --script res://tools/town_planner/build/qc/count_track.gd -- x0 x1 z0 z1 <scene>...
func _world(n: Node, root: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var at: Node = n
	while at != null and at != root:
		if at is Node3D: x = (at as Node3D).transform * x
		at = at.get_parent()
	return x

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var x0 := float(a[0]); var x1 := float(a[1]); var z0 := float(a[2]); var z1 := float(a[3])
	for k in range(4, a.size()):
		var track: Node3D = (load(a[k]) as PackedScene).instantiate()
		var inside := 0; var outside := 0; var mm_nodes := 0; var labels_in := 0; var labels_out := 0; var hidden := 0
		var biggest := ""
		var most := 0
		for n in track.find_children("*", "", true, false):
			if n is Node3D and not (n as Node3D).visible: hidden += 1
			if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
				mm_nodes += 1
				var xm := _world(n, track); var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
				if mm.instance_count > most: most = mm.instance_count; biggest = str(track.get_path_to(n))
				for i in mm.instance_count:
					var c: Vector3 = xm * mm.get_instance_transform(i).origin
					if c.x >= x0 and c.x <= x1 and c.z >= z0 and c.z <= z1: inside += 1
					else: outside += 1
			elif n is GeometryInstance3D and not (n is MeshInstance3D):
				var c2 := _world(n, track).origin
				if c2.x >= x0 and c2.x <= x1 and c2.z >= z0 and c2.z <= z1: labels_in += 1
				else: labels_out += 1
		print("COUNT ", a[k].get_file(), " in ", a[k].get_base_dir().get_file(), ": multimesh nodes ", mm_nodes, ", instances inside ", inside, " outside ", outside,
			"; other drawn things inside ", labels_in, " outside ", labels_out, "; hidden nodes ", hidden, "; biggest ", biggest, " (", most, ")")
		track.free()
	quit()
