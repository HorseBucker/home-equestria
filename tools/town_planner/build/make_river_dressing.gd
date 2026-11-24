extends SceneTree
## The streams' bank dressing as kit kinds (2026-11-24 play test: "more natural clusters of rocks, reeds/cattails,
## and shoreline grass tufts ... using instancing/batching so it barely impacts our triangle/draw-call budget").
##   godot --headless --xr-mode off --path . --script res://tools/town_planner/build/make_river_dressing.gd
## Writes world/props/ponyville_kit/<kind>.scn, each one MeshInstance3D of one small mesh, flat painted colours
## in its vertices (one material per kind, so the kit draws each kind as one MultiMesh per 48 m square,
## kit_dressing.gd), the same every run (seeded):
## - reed_clump: a dozen tall blades leaning out and three cattails, about 110 triangles;
## - shore_grass: a low tuft of long blades, about 60 triangles;
## - river_rocks: three to five rounded stones of different sizes half sunk together, about 120 triangles;
## - river_pebbles: two or three small ones, about 50 triangles.
## tools/town_planner/build/place_river_dressing.py sets them along the banks.
const FOLDER := "res://world/props/ponyville_kit/"

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 24112026
	_save("reed_clump", _reeds(), true)
	_save("shore_grass", _grass(), true)
	_save("river_rocks", _rocks(randi_range_n(3, 5), 0.16, 0.42, 0.9), false)
	_save("river_pebbles", _rocks(randi_range_n(2, 3), 0.07, 0.16, 0.45), false)
	quit()


func randi_range_n(a: int, b: int) -> int:
	return rng.randi_range(a, b)


func _save(kind: String, st: SurfaceTool, two_sided: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	if two_sided: mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = kind
	mi.mesh = mesh
	var scene := PackedScene.new()
	scene.pack(mi)
	ResourceSaver.save(scene, FOLDER + kind + ".scn")
	var tris := 0
	for s in mesh.get_surface_count(): tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("RIVER_DRESSING %s: %d triangles, %s" % [kind, tris, mesh.get_aabb().size])
	mi.free()


## A blade: a strip from `base` up `height`, `width` wide at the foot to a point, bending out along `lean`.
func _blade(st: SurfaceTool, base: Vector3, height: float, width: float, lean: Vector3, foot: Color, tip: Color) -> void:
	var side := Vector3.UP.cross(lean).normalized() if lean.length() > 0.01 else Vector3.RIGHT
	var face := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	side = side.lerp(face, 0.5).normalized()
	var segs := 2
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / segs
		pts.append(base + Vector3.UP * height * t + lean * height * t * t)
	var up := Vector3.UP
	for i in segs:
		var t0 := float(i) / segs; var t1 := float(i + 1) / segs
		var w0 := width * (1.0 - t0); var w1 := width * (1.0 - t1) * (1.0 if i + 1 < segs else 0.15)
		var a := pts[i] - side * w0 * 0.5; var b := pts[i] + side * w0 * 0.5
		var c := pts[i + 1] + side * w1 * 0.5; var d := pts[i + 1] - side * w1 * 0.5
		var c0 := foot.lerp(tip, t0); var c1 := foot.lerp(tip, t1)
		for v: Array in [[a, c0], [b, c0], [c, c1], [a, c0], [c, c1], [d, c1]]:
			st.set_color(v[1]); st.set_normal(up); st.add_vertex(v[0])


func _reeds() -> SurfaceTool:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 12:
		var a := rng.randf() * TAU; var r := rng.randf_range(0.0, 0.22)
		var base := Vector3(cos(a) * r, -0.05, sin(a) * r)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.08, 0.3)
		var green := Color(0.36, 0.55, 0.22).lerp(Color(0.5, 0.62, 0.26), rng.randf())
		_blade(st, base, rng.randf_range(0.8, 1.35), rng.randf_range(0.05, 0.08), lean, green.darkened(0.35), green.lightened(0.12))
	for i in 3:
		var a := rng.randf() * TAU; var r := rng.randf_range(0.03, 0.15)
		var base := Vector3(cos(a) * r, -0.05, sin(a) * r)
		var h := rng.randf_range(1.05, 1.45)
		var top := base + Vector3(cos(a) * 0.06, h, sin(a) * 0.06)
		# the stem: two crossed thin strips
		for side: Vector3 in [Vector3(0.012, 0, 0), Vector3(0, 0, 0.012)]:
			var stem := Color(0.42, 0.52, 0.24)
			for v: Vector3 in [base - side, base + side, top + side, base - side, top + side, top - side]:
				st.set_color(stem.darkened(0.3) if v.y < 0.5 else stem); st.set_normal(Vector3.UP); st.add_vertex(v)
		# the head: a brown six-sided spindle a little below the top
		var lo := top - Vector3(0, 0.26, 0); var hi := top - Vector3(0, 0.04, 0)
		var brown := Color(0.42, 0.26, 0.14).lerp(Color(0.5, 0.31, 0.16), rng.randf())
		for k in 6:
			var a0 := TAU * k / 6.0; var a1 := TAU * (k + 1) / 6.0
			var o0 := Vector3(cos(a0), 0, sin(a0)) * 0.032; var o1 := Vector3(cos(a1), 0, sin(a1)) * 0.032
			var n := Vector3(cos((a0 + a1) * 0.5), 0.2, sin((a0 + a1) * 0.5)).normalized()
			for v: Vector3 in [lo + o0, lo + o1, hi + o1, lo + o0, hi + o1, hi + o0]:
				st.set_color(brown); st.set_normal(n); st.add_vertex(v)
			for v: Vector3 in [hi + o0, hi + o1, hi + Vector3(0, 0.03, 0)]:
				st.set_color(brown.lightened(0.1)); st.set_normal(Vector3.UP); st.add_vertex(v)
			for v: Vector3 in [lo + o1, lo + o0, lo - Vector3(0, 0.03, 0)]:
				st.set_color(brown.darkened(0.2)); st.set_normal(Vector3.DOWN); st.add_vertex(v)
	st.index()
	return st


func _grass() -> SurfaceTool:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 15:
		var a := rng.randf() * TAU; var r := rng.randf_range(0.0, 0.16)
		var base := Vector3(cos(a) * r, -0.03, sin(a) * r)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.25, 0.6)
		var green := Color(0.42, 0.66, 0.24).lerp(Color(0.56, 0.74, 0.3), rng.randf())
		_blade(st, base, rng.randf_range(0.3, 0.58), rng.randf_range(0.04, 0.065), lean, green.darkened(0.3), green.lightened(0.1))
	st.index()
	return st


## `count` rounded stones from `small` to `big` m across, within `spread` m, half sunk, each a squashed, jittered
## icosahedron with flat faces (toon shading picks them out).
func _rocks(count: int, small: float, big: float, spread: float) -> SurfaceTool:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := (1.0 + sqrt(5.0)) / 2.0
	var ico: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var tones := [Color(0.62, 0.6, 0.56), Color(0.7, 0.66, 0.58), Color(0.52, 0.5, 0.48), Color(0.6, 0.54, 0.46)]
	for n in count:
		var size := lerpf(big, small, float(n) / maxf(1.0, count - 1.0)) * rng.randf_range(0.85, 1.1)
		var a := rng.randf() * TAU; var r := 0.0 if n == 0 else rng.randf_range(0.35, 1.0) * spread * 0.5
		# rounded, not flat (2026-11-24: squashed to under 0.7 they read as flat discs on the banks), a third sunk
		var centre := Vector3(cos(a) * r, size * 0.16, sin(a) * r)
		var squash := Vector3(rng.randf_range(0.9, 1.2), rng.randf_range(0.68, 0.9), rng.randf_range(0.85, 1.1)) * size * 0.5
		var spin := Basis(Vector3.UP, rng.randf() * TAU)
		var pts: Array[Vector3] = []
		for p: Vector3 in ico:
			var q := p.normalized() * rng.randf_range(0.85, 1.1)
			pts.append(centre + spin * Vector3(q.x * squash.x, q.y * squash.y, q.z * squash.z))
		var tone: Color = tones[rng.randi() % tones.size()]
		for f: Array in faces:
			var a_ := pts[f[0]]; var b_ := pts[f[1]]; var c_ := pts[f[2]]
			var nrm := (c_ - a_).cross(b_ - a_).normalized()
			if nrm.dot(a_ - centre) < 0: nrm = -nrm; var swap := b_; b_ = c_; c_ = swap
			var lit := tone.lightened(0.12 * clampf(nrm.y, 0, 1)).darkened(0.25 * clampf(-nrm.y, 0, 1))
			for v: Vector3 in [a_, c_, b_]:
				st.set_color(lit); st.set_normal(nrm); st.add_vertex(v)
	st.index()
	return st
