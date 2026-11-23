extends SceneTree
## Build step 6 (applying half): the town's own trees and street furniture where plan_props.py put them
## (build/out/props.json).
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/apply_props.gd
## - world/props/ponyville/town_trees.scn: its trees (trunk, crown, collider) reused as patterns, set at the
##   new spots in turn.
## - world/props/ponyville/outdoor_props.scn: benches, tables, street lamps, flowerbeds and daisies, each an
##   instance of its own scene, as before; the root keeps its script (the lamps' dusk controller). And the
##   bunting (props.json "bunting": pairs of ties), one mesh of cords and pennants.
## Run it on the scenes from git.

const PROPS := "res://tools/town_planner/build/out/props.json"
const TREES := "res://world/props/ponyville/town_trees.scn"
const OUTDOOR := "res://world/props/ponyville/outdoor_props.scn"
const KINDS := {"bench": "res://world/props/ponyville/bench.scn", "table": "res://world/props/ponyville/table.scn",
	"streetlamp": "res://world/props/ponyville/streetlamp.scn", "flowerbed": "res://world/props/ponyville/flowerbed.scn",
	"daisy": "res://world/props/ponyville/daisy.scn"}


func _init() -> void:
	# trees only (build_density.py, 2026-11-21: each lower town density's own trees): -- <props json> <out scene>; the
	# full town's town_trees.scn is the pattern, the json's "trees" the spots, nothing else is touched
	var args := OS.get_cmdline_user_args()
	var only_trees := args.size() >= 2
	var props: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0] if only_trees else PROPS))
	# ---- trees: each is a collider (tree_NNN) and two meshes beside it at its spot (near "_part0", far "_far") ----
	var trees_root: Node3D = (load(TREES) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var colliders: Array[Node3D] = []
	var meshes: Array[Node3D] = []
	for c in trees_root.get_children():
		if c is StaticBody3D: colliders.append(c)
		elif c is MeshInstance3D: meshes.append(c)
	var patterns: Array = []          # [collider, [meshes]]
	for col in colliders:
		var mine: Array[Node3D] = []
		for m in meshes:
			if Vector2(m.position.x - col.position.x, m.position.z - col.position.z).length() < 0.2: mine.append(m)
		patterns.append([col, mine])
	for c in trees_root.get_children(): trees_root.remove_child(c)
	var n := 0
	for t: Dictionary in props.trees:
		var pattern: Array = patterns[n % patterns.size()]
		n += 1
		var col: Node3D = pattern[0]
		var at := Vector3(float(t.x), float(t.y), float(t.z))
		var spin := Basis(Vector3.UP, float(t.yaw))
		var tree := col.duplicate() as Node3D
		tree.name = "tree_%03d" % n
		tree.position = at
		trees_root.add_child(tree); _own(tree, trees_root)
		var k := 0
		for m: Node3D in pattern[1]:
			var mesh := m.duplicate() as Node3D
			mesh.name = "%s_%s" % [tree.name, "far" if str(m.name).ends_with("_far") else "part%d" % k]
			k += 1
			mesh.transform = Transform3D(spin * m.transform.basis, at + spin * (m.position - col.position))
			trees_root.add_child(mesh); _own(mesh, trees_root)
	for pattern in patterns:
		(pattern[0] as Node).free()
		for m: Node in pattern[1]: m.free()
	for m in meshes:
		if is_instance_valid(m) and m.get_parent() == null: m.free()
	var err := _save(trees_root, args[1] if only_trees else TREES)
	print("TREES ", n, " from ", patterns.size(), " patterns, save ", err)
	trees_root.free()
	if only_trees:
		quit(); return
	# ---- street furniture ----
	var outdoor: Node3D = (load(OUTDOOR) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var script: Script = outdoor.get_script()
	for c in outdoor.get_children():
		outdoor.remove_child(c); c.free()
	var counts := {}
	var scenes := {}
	for p: Dictionary in props.outdoor:
		var kind := str(p.kind)
		if not scenes.has(kind): scenes[kind] = load(KINDS[kind])
		var node: Node3D = (scenes[kind] as PackedScene).instantiate()
		counts[kind] = int(counts.get(kind, 0)) + 1
		node.name = "%s_%02d" % [kind, counts[kind]]
		node.position = Vector3(float(p.x), float(p.y), float(p.z))
		node.rotation.y = float(p.yaw)
		outdoor.add_child(node); node.owner = outdoor
	# bunting: one mesh for every string
	var strings: Array = props.get("bunting", [])
	if not strings.is_empty():
		var bunting := MeshInstance3D.new(); bunting.name = "Bunting"
		bunting.mesh = _bunting(strings)
		bunting.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outdoor.add_child(bunting); bunting.owner = outdoor
		counts["bunting strings"] = strings.size()
	err = _save(outdoor, OUTDOOR)
	print("OUTDOOR ", counts, " script kept ", outdoor.get_script() == script and script != null, ", save ", err)
	outdoor.free()
	quit()


## Strings of pennants: each string hangs between its two ties with a sag of a fifteenth of its length; a thin
## cord (a flat ribbon seen from every side: two crossed strips), and a triangular pennant every 0.62 m, hanging
## point down in the string's own upright plane, in six colours in turn. One surface, coloured by vertex, drawn
## from both sides.
const PENNANTS := [Color(0.96, 0.45, 0.62), Color(0.38, 0.72, 0.93), Color(0.99, 0.86, 0.35), Color(0.55, 0.83, 0.52), Color(0.74, 0.56, 0.9), Color(0.98, 0.62, 0.32)]
func _bunting(strings: Array) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cord := Color(0.93, 0.9, 0.82)
	var n := 0
	for s: Array in strings:
		var a := Vector3(float(s[0][0]), float(s[0][1]), float(s[0][2])); var b := Vector3(float(s[1][0]), float(s[1][1]), float(s[1][2]))
		var length := a.distance_to(b)
		var sag := clampf(length / 15.0, 0.25, 1.8)
		var along := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var side := along.cross(Vector3.UP).normalized()
		var steps := maxi(8, int(length / 0.31))
		var at := func(t: float) -> Vector3: return a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		for k in steps:
			var p: Vector3 = at.call(float(k) / steps); var q: Vector3 = at.call(float(k + 1) / steps)
			for across: Vector3 in [Vector3.UP * 0.012, side * 0.012]:
				_quad(st, p - across, p + across, q + across, q - across, cord)
			if k % 2 == 0 and k + 2 <= steps:
				# a pennant under this pair of steps: 0.5 m along the cord, 0.52 m deep
				var r: Vector3 = at.call(float(k + 2) / steps)
				var top_a := p.lerp(q, 0.2); var top_b := q.lerp(r, 0.8)
				var tip := (top_a + top_b) * 0.5 + Vector3.DOWN * 0.52
				var colour: Color = PENNANTS[n % PENNANTS.size()]; n += 1
				var normal := (top_b - top_a).cross(tip - top_a).normalized()
				for v: Vector3 in [top_a, top_b, tip]:
					st.set_color(colour); st.set_normal(normal); st.add_vertex(v)
	var material := StandardMaterial3D.new()
	material.resource_name = "Bunting"
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true        # the colours above are as seen; read as linear they came out pale
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.9
	st.set_material(material)
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(colour); st.set_normal(normal); st.add_vertex(v)


func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	if node.scene_file_path != "": return      # an instance keeps its own children
	for c in node.get_children(): _own(c, owner_node)


func _save(root_node: Node, path: String) -> int:
	var packed := PackedScene.new()
	var err := packed.pack(root_node)
	if err != OK: return err
	var compressed := FileAccess.get_file_as_bytes(path).slice(0, 4).get_string_from_ascii() == "RSCC"
	return ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS if compressed else 0)
