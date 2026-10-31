extends Node3D
## One, three or four candles of different heights on a table top (dev 2026-09-28: "four and
## three and one and various heights and sizes, like Minecraft, randomly placed on tables").
## A trigger press on any wick lights or snuffs the whole cluster (candle_lighter.gd). One warm
## shadowless light per lit cluster; the flames flicker only while lit. Lit state is per session.
const WAX := [Color("f4ead2"), Color("efe2c4"), Color("f7efe0"), Color("e9dcc0")]
var lit := false
var wicks: Array[Vector3] = [] # local wick tips
var _flames: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _time := 0.0
var _seed := 0.0
static var _wax_materials: Array[StandardMaterial3D] = []
static var _wick_material: StandardMaterial3D
static var _flame_material: StandardMaterial3D
## Perf 0.1.0 (geometry): a cluster's wax bodies draw as one surface (their four wax colours
## become vertex colours on one otherwise identical material) and its wicks as a second surface:
## 2 draws per cluster per pass instead of 2 per candle. Same cylinders, sizes and seeded layout.
## false = one wax and one wick mesh per candle again (rollback / A-B).
const MERGE_CANDLES := true
static var _wax_vertex_material: StandardMaterial3D

## `count` candles within a small circle, seeded by `rng` (heights 5-16 cm, radii 1.2-2.2 cm).
func build(count: int, rng: RandomNumberGenerator) -> void:
	add_to_group("candle_clusters")
	_materials()
	_seed = rng.randf() * 100.0
	var spots: Array[Vector2] = [Vector2.ZERO]
	if count == 3: spots = [Vector2(-0.028, 0.012), Vector2(0.026, 0.018), Vector2(0.0, -0.03)]
	elif count >= 4: spots = [Vector2(-0.03, -0.028), Vector2(0.032, -0.024), Vector2(-0.026, 0.03), Vector2(0.03, 0.032)]
	var turn := rng.randf() * TAU
	var wax_parts: Array = []   # [mesh, offset, colour]
	var wick_parts: Array = []  # [mesh, offset]
	for i in spots.size():
		var radius := rng.randf_range(0.012, 0.022)
		var height := rng.randf_range(0.05, 0.16)
		var at := spots[i].rotated(turn) * rng.randf_range(0.85, 1.15)
		var wax := MeshInstance3D.new()
		var body := CylinderMesh.new(); body.top_radius = radius; body.bottom_radius = radius * 1.04; body.height = height; body.radial_segments = 14
		wax.mesh = body
		var wax_index := rng.randi() % _wax_materials.size()
		wax.material_override = _wax_materials[wax_index]
		wax.position = Vector3(at.x, height * 0.5, at.y)
		var wick := MeshInstance3D.new()
		var thread := CylinderMesh.new(); thread.top_radius = 0.0012; thread.bottom_radius = 0.0015; thread.height = 0.012; thread.radial_segments = 5
		wick.mesh = thread; wick.material_override = _wick_material
		wick.position = Vector3(at.x, height + 0.005, at.y)
		if MERGE_CANDLES:
			wax_parts.append([body, wax.position, WAX[wax_index]])
			wick_parts.append([thread, wick.position, Color.WHITE])
			wax.free(); wick.free()
		else:
			_finish(wax)
			_finish(wick)
		wicks.append(Vector3(at.x, height + 0.011, at.y))
		var flame := MeshInstance3D.new()
		var drop := SphereMesh.new(); drop.radius = 0.0065; drop.height = 0.024; drop.radial_segments = 8; drop.rings = 5
		flame.mesh = drop; flame.material_override = _flame_material
		flame.position = Vector3(at.x, height + 0.022, at.y)
		flame.visible = false
		_finish(flame)
		_flames.append(flame)
	if MERGE_CANDLES:
		var merged := ArrayMesh.new()
		_add_parts(merged, wax_parts, true, _wax_vertex_material)
		_add_parts(merged, wick_parts, false, _wick_material)
		var view := MeshInstance3D.new()
		view.name = "CandleBodies"
		view.mesh = merged
		_finish(view)
		# Ranges measure from the instance: the cluster's farthest candle keeps its own 40 m.
		var reach := 0.0
		for part: Array in wax_parts: reach = maxf(reach, (part[1] as Vector3).length())
		view.visibility_range_end += reach * global_basis.get_scale().x if is_inside_tree() else reach
	set_process(false)

## One surface from cylinders offset in the cluster frame; `coloured` writes each part's wax colour.
static func _add_parts(mesh: ArrayMesh, parts: Array, coloured: bool, material: Material) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part: Array in parts:
		var arrays: Array = (part[0] as PrimitiveMesh).get_mesh_arrays()
		var offset: Vector3 = part[1]
		var base := vertices.size()
		var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for point: Vector3 in source: vertices.append(point + offset)
		normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		tangents.append_array(arrays[Mesh.ARRAY_TANGENT])
		uvs.append_array(arrays[Mesh.ARRAY_TEX_UV])
		if coloured:
			var fill := PackedColorArray(); fill.resize(source.size()); fill.fill(part[2]); colors.append_array(fill)
		for index: int in arrays[Mesh.ARRAY_INDEX]: indices.append(base + index)
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_TANGENT] = tangents
	surface[Mesh.ARRAY_TEX_UV] = uvs
	if coloured: surface[Mesh.ARRAY_COLOR] = colors
	surface[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)

func _finish(piece: MeshInstance3D) -> void:
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.visibility_range_end = 40.0
	add_child(piece)

## The wick tip nearest `point` (world), for the lighter's touch test.
func nearest_wick(point: Vector3) -> Vector3:
	var best := Vector3.INF
	for wick in wicks:
		var at := to_global(wick)
		if at.distance_to(point) < best.distance_to(point): best = at
	return best

func toggle() -> void:
	set_lit(not lit)

func set_lit(value: bool) -> void:
	lit = value
	for flame in _flames: flame.visible = lit
	if lit and _light == null:
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.72, 0.42)
		_light.shadow_enabled = false
		_light.omni_range = 2.6 + 0.35 * wicks.size()
		_light.omni_attenuation = 1.6
		_light.distance_fade_enabled = true
		_light.distance_fade_begin = 25.0
		_light.distance_fade_length = 8.0
		var centre := Vector3.ZERO
		for wick in wicks: centre += wick
		_light.position = centre / maxf(1, wicks.size()) + Vector3.UP * 0.05
		add_child(_light)
	if _light != null: _light.visible = lit
	set_process(lit)

func _process(delta: float) -> void:
	_time += delta
	var base := 0.32 * pow(float(wicks.size()), 0.7)
	_light.light_energy = base * (0.88 + 0.08 * sin(_time * 9.1 + _seed) + 0.05 * sin(_time * 23.7 + _seed * 2.0))
	for i in _flames.size():
		var sway := sin(_time * (11.0 + i) + _seed + i * 1.7)
		_flames[i].scale = Vector3(1.0 + 0.06 * sway, 1.0 + 0.14 * sin(_time * (15.0 + i) + i), 1.0 + 0.06 * sway)

static func _materials() -> void:
	if not _wax_materials.is_empty(): return
	for colour: Color in WAX:
		var wax := StandardMaterial3D.new()
		wax.albedo_color = colour
		wax.roughness = 0.55
		# A little light through the wax, like the real thing.
		wax.subsurf_scatter_enabled = false
		wax.rim_enabled = true; wax.rim = 0.2; wax.rim_tint = 0.4
		_wax_materials.append(wax)
	# The wax material once more, white, taking each candle's wax colour from its vertices.
	_wax_vertex_material = _wax_materials[0].duplicate() as StandardMaterial3D
	_wax_vertex_material.albedo_color = Color.WHITE
	_wax_vertex_material.vertex_color_use_as_albedo = true
	_wax_vertex_material.vertex_color_is_srgb = true
	_wick_material = StandardMaterial3D.new()
	_wick_material.albedo_color = Color("2a211b")
	_flame_material = StandardMaterial3D.new()
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.albedo_color = Color(1.0, 0.78, 0.35)
	_flame_material.emission_enabled = true
	_flame_material.emission = Color(1.0, 0.62, 0.22)
	_flame_material.emission_energy_multiplier = 3.0
