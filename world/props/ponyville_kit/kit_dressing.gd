extends Node3D
## Ponyville kit dressing (2026-10-13): the Golden Oak style props from placements.json
## (tools/ponyville_kit/plan_kit.py + fit_kit.gd). One MultiMesh per kind per 48 m cell keeps
## draw calls low and lets far cells cull; blocking props get one simple static collider each.
const PLACEMENTS := "res://world/props/ponyville_kit/placements.json"
const FOLDER := "res://world/props/ponyville_kit/"
const CELL := 48.0
## Visible distance per kind family (small 45 m, medium 90 m, tall 160 m; perf pass 2026-10-13).
const SMALL := ["grass_tuft_a", "grass_tuft_b", "daisy_clump", "lupin_clump", "stepping_stones_b",
	"shore_grass", "river_pebbles"]   # (the streams' banks, 2026-11-24: tools/town_planner/build/make_river_dressing.gd)
const TALL := ["cypress", "tiered_fir", "broadleaf_tree", "bush_cluster_large", "well", "hay_cart"]
## Solid kinds whose drawn mesh is wider than the planned radius suggests. The cypress column
## measures 1.22 m from its trunk (player bug board #9, 2026-10-26: walking 0.7 m into it).
const MEASURED_RADIUS := {"cypress": 1.0}
const RANGE_SMALL := 45.0
const RANGE_MEDIUM := 90.0
const RANGE_TALL := 160.0
const FIELD_RANGE := 170.0
## The flower meadow's clumps batch per FIELD_CELL square, not per 48 m CELL (2026-11-17 cost pass: at 48 m the
## meadow alone was about 500 draw calls, perf_lab.gd): bigger batches, a few metres more of each clump's range so
## the bigger square does not pull its near edge in.
const FIELD_CELL := 72.0
const FIELD_RANGE_EXTRA := 12.0
## The far look of a flower-meadow clump: [colour, radius, height of its middle].
const FIELD_DOT := {"lupin_clump": [Color(0.63, 0.42, 0.87), 0.3, 0.36], "daisy_clump": [Color(0.98, 0.97, 0.88), 0.22, 0.2],
	"sunflower_clump": [Color(0.98, 0.8, 0.18), 0.34, 1.35], "rose_bed": [Color(0.9, 0.24, 0.36), 0.5, 0.2],
	"flowering_shrub": [Color(0.96, 0.55, 0.76), 0.55, 0.5]}
var _dot_meshes: Dictionary = {}

var _dot_rows: Dictionary = {}

## One eight-triangle dot per clump of the meadow, shown from where the clumps themselves stop being drawn: a
## meadow of nine thousand clumps is millions of triangles if all of it draws in full, and bare beyond 45 m if not.
## One batch per flower for the whole meadow (2026-11-17 cost pass: one per cell was about a hundred draw calls):
## a dot fades in per pixel with distance (the material's distance fade) instead of a per-cell visibility range,
## so it is hidden near the camera where the clump itself is drawn.
func _field_dots(kind: String, rows: Array) -> void:
	if not FIELD_DOT.has(kind) or rows.is_empty(): return
	var look: Array = FIELD_DOT[kind]
	var near: float = (RANGE_SMALL if kind in SMALL else RANGE_MEDIUM) + FIELD_RANGE_EXTRA
	if not _dot_meshes.has(kind):
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var r: float = look[1]
		var tips := [Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0), Vector3(0, 0, -r)]
		var top := Vector3(0, r * 0.7, 0); var bottom := Vector3(0, -r * 0.7, 0)
		for i in 4:
			var a: Vector3 = tips[i]; var b: Vector3 = tips[(i + 1) % 4]
			for tri: Array in [[top, b, a], [bottom, a, b]]:
				var n := (Vector3(tri[1]) - Vector3(tri[0])).cross(Vector3(tri[2]) - Vector3(tri[0])).normalized()
				if n.dot(Vector3(tri[0]) + Vector3(tri[1]) + Vector3(tri[2])) > 0.0: tri.reverse()
				else: n = -n
				for v: Vector3 in tri: st.set_normal(n); st.add_vertex(v)
		var paint := StandardMaterial3D.new()
		paint.albedo_color = look[0]; paint.roughness = 1.0
		paint.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		paint.distance_fade_min_distance = near - 10.0
		paint.distance_fade_max_distance = near - 2.0
		st.set_material(paint)
		_dot_meshes[kind] = st.commit()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _dot_meshes[kind]
	mm.instance_count = rows.size()
	for i in rows.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _placement(rows[i]).origin + Vector3.UP * float(look[2])))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = FIELD_RANGE + 160.0   # measured to the middle of the whole meadow
	mmi.visibility_range_end_margin = 10.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_winter_gone.append(mmi)
	_meadow.append(mmi)
## Low or thin props whose shadow is barely visible but costs a shadow pass per cell; trees,
## well, carts, barrels and benches keep theirs. October 13 also removes bush,
## flowering-shrub, log-pile and crop-row shadows, including bush proxy meshes.
const NO_SHADOW := ["shore_grass", "reed_clump", "river_pebbles", "grass_tuft_a", "grass_tuft_b", "daisy_clump", "lupin_clump", "sunflower_clump",
	"rose_bed", "stepping_stones_a", "stepping_stones_b", "heart_fence", "heart_fence_post",
	"white_picket", "white_picket_post", "rail_fence", "rail_fence_broken", "rail_fence_post",
	"mailbox", "signpost", "tree_stump", "produce_crate",
	"bush_round_small", "bush_round_medium", "bush_cluster_large", "flowering_shrub", "log_pile", "crop_row"]
## Fence sections run along +X from their post; their collider is a thin box over the bay.
const BAYS := {"heart_fence": 1.25, "white_picket": 1.6, "rail_fence": 2.4}
const ACTIVITY_STATE := preload("res://world/props/ponyville_kit/kit_state.gd")
## The player's switches for the flower meadow and Carrot Top's farm (Settings > Graphics; town_extras.gd).
const EXTRAS := preload("res://world/towns/ponyville/town_extras.gd")
const FITS := preload("res://world/props/ponyville_kit/kit_fits.gd")
var _activity_state: Node
var _garden_slots: Dictionary = {}

func _ready() -> void:
	if not FileAccess.file_exists(PLACEMENTS): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLACEMENTS))
	if not (parsed is Dictionary): return
	var groups := {}
	# The gardens of the town at its density (town_density.gd): the town scene says which it was built at.
	var town := get_parent()
	var density := str(town.get_meta("town_density", "high")) if town != null else "high"
	for row: Dictionary in preload("res://world/towns/ponyville/town_density.gd").kit_entries(parsed as Dictionary, density):
		# The flower meadow's rows (group "flower-meadow", Ponyville overhaul) are batched apart from the gardens': they
		# are seen as a field of colour from the road, so past a clump's own range each is drawn as a dot of its
		# flower's colour, out to FIELD_RANGE (_field_dots).
		var field := str(row.get("group", "")) == "flower-meadow"
		var size := FIELD_CELL if field else CELL
		var key := "%s|%d|%d%s" % [row.kind, floori(float(row.x) / size), floori(float(row.z) / size), "|field" if field else ("|farm" if EXTRAS.farm_row(row) else "")]
		if not groups.has(key): groups[key] = []
		(groups[key] as Array).append(row)
	var parts := {}
	var body := StaticBody3D.new()
	body.name = "KitCollision"
	add_child(body)
	for key: String in groups:
		var kind := key.get_slice("|", 0)
		if kind == "broadleaf_tree":
			_grassy_trees(groups[key], body); continue
		if _leaf_bush(kind, groups[key], body): continue
		if not parts.has(kind): parts[kind] = _parts(kind)
		var kind_parts: Array = parts[kind]
		if kind_parts.is_empty(): continue
		var rows: Array = groups[key]
		for part: Array in kind_parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _season_mesh(part[0], kind in GRASS_ONLY) if LOOK_SEASON_PLANTS and kind in SEASON_PLANTS else part[0]
			mm.instance_count = rows.size()
			for i in rows.size():
				mm.set_instance_transform(i, _placement(rows[i]) * (part[1] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = RANGE_SMALL if kind in SMALL else (RANGE_TALL if kind in TALL else RANGE_MEDIUM)
			if key.ends_with("|field"): mmi.visibility_range_end += FIELD_RANGE_EXTRA
			mmi.visibility_range_end_margin = 8.0
			if kind in NO_SHADOW: mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			if key.ends_with("|field") or kind in WINTER_GONE: _winter_gone.append(mmi)
			if key.ends_with("|field"): _meadow.append(mmi)
			if key.ends_with("|farm"): _farm.append(mmi)
			if kind in ACTIVITY_STATE.GARDEN:
				for i: int in rows.size(): _remember_garden(str(rows[i].id), mm, i, _placement(rows[i]).origin)
		if key.ends_with("|field"): (_dot_rows.get_or_add(kind, []) as Array).append_array(rows)
		for row: Dictionary in rows:
			if bool(row.get("blocking", false)): _collider(body, row, kind)
	# The town's own trees answer "where are the trees" (falling leaves, leaf piles, birds).
	var habitat := preload("res://world/foliage/town_tree_habitat.gd").new()
	habitat.name = "TownTreeHabitat"
	add_child(habitat)
	habitat.setup([get_parent().get_node_or_null("TownTrees") if get_parent() != null else null, self])
	for kind: String in _dot_rows: _field_dots(kind, _dot_rows[kind])
	_dot_rows.clear()
	_winter_start()
	add_to_group(EXTRAS.GROUP)
	town_extras_changed()
	_activity_state = ACTIVITY_STATE.for_node(self)
	if _activity_state != null: _activity_state.touched.connect(_touch_garden)
	var activity_visuals := preload("res://world/props/ponyville_kit/kit_state_visuals.gd").new()
	activity_visuals.name = "ActivityStateVisuals"
	add_child(activity_visuals)
	activity_visuals.setup(self, (parsed as Dictionary).get("entries", []))

## Gone for the winter (play test 2026-11-16: "The flowers in the meadow and the crops in the farms should be
## gone in Winter"): the flower meadow's clumps and far dots, and the farms' crop rows. They stood in the snow all
## winter. A check every few seconds (nothing per frame): in winter they fade out over a few seconds and are
## switched off; when winter ends they fade back in. A world that opens in winter opens without them.
const WINTER_GONE := ["crop_row"]
const WINTER_CHECK := 3.0
const WINTER_FADE := 5.0
var _winter_gone: Array[GeometryInstance3D] = []
var _winter_hidden := false
## The flower meadow's batches (clumps and dots): gone at the lowest quality preset too (2026-11-17: "disabled
## completely if the user is on minimum settings"; Quality key flower_meadow), at once when the preset changes.
var _meadow: Array[GeometryInstance3D] = []
## Carrot Top's crop rows (town_extras.gd farm_row), which the player may switch off.
var _farm: Array[GeometryInstance3D] = []

## The meadow: the player's choice, or the graphics preset's (town_extras.gd).
func _meadow_allowed() -> bool:
	return EXTRAS.meadow_on()

func _show(part: GeometryInstance3D, on: bool) -> void:
	part.visible = on and (not _meadow.has(part) or _meadow_allowed()) and (not _farm.has(part) or EXTRAS.carrot_farm_on())

func _quality_changed(_preset: int) -> void:
	for part: GeometryInstance3D in _meadow:
		if is_instance_valid(part): _show(part, not _winter_hidden)

## Settings > Graphics changed the meadow or the farm (town_extras.gd set_choice): shown or hidden at once.
func town_extras_changed() -> void:
	for part: GeometryInstance3D in _meadow + _farm:
		if is_instance_valid(part): _show(part, not (_winter_hidden and _winter_gone.has(part)))

func _winter_start() -> void:
	if _winter_gone.is_empty(): return
	_winter_hidden = _is_winter()
	for part: GeometryInstance3D in _winter_gone: _show(part, not _winter_hidden)
	var quality: Node = get_node_or_null("/root/Quality")
	if quality != null and quality.has_signal("preset_changed"): quality.connect("preset_changed", _quality_changed)
	var timer := Timer.new(); timer.name = "WinterCheck"; timer.wait_time = WINTER_CHECK
	add_child(timer)
	timer.timeout.connect(_winter_check)
	timer.start()

func _is_winter() -> bool:
	var season: Node = get_tree().get_first_node_in_group("season_state") if is_inside_tree() else null
	return is_instance_valid(season) and season.has_method("is_winter") and bool(season.call("is_winter"))

func _winter_check() -> void:
	var winter := _is_winter()
	if winter == _winter_hidden: return
	_winter_hidden = winter
	for part: GeometryInstance3D in _winter_gone:
		if not is_instance_valid(part): continue
		if _meadow.has(part) and not _meadow_allowed(): part.visible = false; continue
		if not winter: part.transparency = 1.0; part.visible = true
		var fade := create_tween()
		fade.tween_property(part, "transparency", 1.0 if winter else 0.0, WINTER_FADE)
		if winter: fade.tween_callback(part.set_visible.bind(false))

## Small plants that follow the seasons (kit_plant.gdshader; dev 2026-11-10: they stood summer
## green on autumn straw and on snow). false brings their plain materials back.
const LOOK_SEASON_PLANTS := true
const SEASON_PLANTS := ["grass_tuft_a", "grass_tuft_b", "daisy_clump", "lupin_clump", "sunflower_clump", "rose_bed"]
## Of those, the ones that are grass and nothing else: all of the plant turns with the ground.
const GRASS_ONLY := ["grass_tuft_a", "grass_tuft_b"]
const PLANT_SHADER := preload("res://world/props/ponyville_kit/kit_plant.gdshader")
var _season_meshes: Dictionary = {}

## A copy of a kit plant's mesh whose plain materials are replaced by the season-aware one,
## keeping each surface's colour, picture and cut-out. One copy per mesh.
func _season_mesh(source: Mesh, grass_only := false) -> Mesh:
	if _season_meshes.has(source): return _season_meshes[source]
	var copy := source.duplicate() as Mesh
	for surface: int in copy.get_surface_count():
		var plain := copy.surface_get_material(surface) as BaseMaterial3D
		if plain == null: continue
		var material := ShaderMaterial.new()
		material.shader = PLANT_SHADER
		material.set_shader_parameter("albedo_tint", plain.albedo_color)
		material.set_shader_parameter("has_texture", plain.albedo_texture != null)
		if plain.albedo_texture != null: material.set_shader_parameter("albedo_texture", plain.albedo_texture)
		material.set_shader_parameter("vertex_tint", plain.vertex_color_use_as_albedo)
		material.set_shader_parameter("all_green", grass_only)
		material.set_shader_parameter("ground_light", 0.65 if grass_only else 0.25)
		var cut := plain.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or plain.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH \
			or plain.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS or plain.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		material.set_shader_parameter("scissor", (plain.alpha_scissor_threshold if plain.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.5) if cut else 0.0)
		copy.surface_set_material(surface, material)
	_season_meshes[source] = copy
	return copy

## The kit's own broadleaf tree (a lumpy painted crown) is replaced by the Grassy trees used
## everywhere else (dev 2026-10-17: "the grassy one is the fancy one", the kit one is not).
## Species from the placement id, about GRASSY_HEIGHT tall, with the Grassy tree's own LODs.
const GRASSY := preload("res://world/foliage/grassy_catalogue.gd")
const GRASSY_HEIGHT := 9.0
func _grassy_trees(rows: Array, body: StaticBody3D) -> void:
	var choices: Array = GRASSY.trees().filter(func(e: Dictionary) -> bool: return not str(e.id).contains("sakura"))
	if choices.is_empty(): return
	for row: Dictionary in rows:
		var entry: Dictionary = choices[absi(hash(str(row.id))) % choices.size()]
		var packed := GRASSY.scene(entry)
		if packed == null: continue
		var tree := packed.instantiate() as Node3D
		var factor := GRASSY_HEIGHT / maxf(float(entry.height), 0.1)
		var basis := Basis(Vector3.UP, float(row.yaw)).scaled(Vector3.ONE * factor)
		tree.transform = Transform3D(basis, _placement(row).origin + basis * GRASSY.contact_offset(entry))
		tree.name = "GrassyTree_" + str(row.id)
		add_child(tree)
		# LOD distances are authored in metres for the pack's own size.
		for mesh: GeometryInstance3D in tree.find_children("*", "GeometryInstance3D", true, false):
			mesh.visibility_range_begin *= factor; mesh.visibility_range_end *= factor
		if bool(row.get("blocking", false)): _collider(body, row, "broadleaf_tree")

func _placement(row: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(row.yaw)), Vector3(float(row.x), KIT_LIFTS.y(row), float(row.z)))
const KIT_LIFTS := preload("res://world/props/ponyville_kit/kit_lifts.gd")

## Every MeshInstance3D of the kit scene with its transform relative to the scene root.
func _parts(kind: String) -> Array:
	# Leaf-card bushes go through _leaf_bush; this is their painted far/shadow mesh.
	var path := FOLDER + kind + ".scn"
	if not ResourceLoader.exists(path): return []
	var scene := (load(path) as PackedScene).instantiate() as Node3D
	var out: Array = []
	var meshes: Array = scene.find_children("*", "MeshInstance3D", true, false)
	if scene is MeshInstance3D: meshes.push_front(scene)
	for mesh: MeshInstance3D in meshes:
		# Include the scene root's own transform: the glTF root carries the import rotation.
		var t := mesh.transform
		var parent := mesh.get_parent() as Node3D if mesh != scene else null
		while parent != null:
			t = parent.transform * t
			parent = parent.get_parent() as Node3D if parent != scene else null
		out.append([mesh.mesh, t])
	scene.free()
	return out

func _collider(body: StaticBody3D, row: Dictionary, kind: String) -> void:
	if kind in ["bench", "tree_stump"] and _measured_seat(row, kind): return
	var shape := CollisionShape3D.new()
	var place := _placement(row)
	if BAYS.has(kind):
		var box := BoxShape3D.new()
		box.size = Vector3(float(BAYS[kind]), 1.0, 0.12)
		shape.shape = box
		shape.transform = place * Transform3D(Basis.IDENTITY, Vector3(float(BAYS[kind]) * 0.5, 0.5, 0))
	else:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = maxf(0.1, float(row.radius) * 0.75 * (0.7 if kind.begins_with("bush_") else 1.0))  # leaf bushes are built at 0.7
		if MEASURED_RADIUS.has(kind): cylinder.radius = float(MEASURED_RADIUS[kind])
		cylinder.height = 1.2 if kind not in TALL else 3.0
		shape.shape = cylinder
		shape.transform = place * Transform3D(Basis.IDENTITY, Vector3(0, cylinder.height * 0.5, 0))
	body.add_child(shape)

## Leaf-card bushes (tools/ponyville_kit/build_leaf_bushes.gd; perf pass 2026-10-13): the
## built leaf LODs per LEAF_CELL square with the ranges stored in the scene, then the painted
## kit bush at the builder's BUSH_SCALE as the far LOD. Leaf cards cast no shadow; the painted
## bush casts it as a shadow-only MultiMesh until it takes over. Ranges are measured from each
## MultiMesh's bounds centre, so the last leaf LOD of a square ends farther by the distance
## from its centre to its 48 m cell's: the painted bush always shows before the leaves go.
const LEAF_CELL := 24.0
const BUSH_SCALE := 0.7
const BUSH_FAR_END := {"bush_cluster_large": 160.0}
const BUSH_FAR_END_DEFAULT := 120.0
var _leaf_lods := {}

func _leaf_bush(kind: String, rows: Array, body: StaticBody3D) -> bool:
	if not _leaf_lods.has(kind):
		var lods: Array = []
		var path := FOLDER + kind + "_leaves.scn"
		if ResourceLoader.exists(path):
			var scene := (load(path) as PackedScene).instantiate()
			for lod: MeshInstance3D in scene.find_children("LeavesLOD*", "MeshInstance3D", false, false):
				lods.append([lod.mesh, lod.visibility_range_begin, lod.visibility_range_end])
			scene.free()
		_leaf_lods[kind] = lods
	var leaf_lods: Array = _leaf_lods[kind]
	if leaf_lods.is_empty(): return false
	# The painted bush takes over at `switch` from the 48 m cell's centre.
	var switch: float = float(leaf_lods[-1][2]) - LEAF_CELL * 0.71
	var far_end: float = BUSH_FAR_END.get(kind, BUSH_FAR_END_DEFAULT)
	var shrink := Transform3D(Basis.from_scale(Vector3.ONE * BUSH_SCALE), Vector3.ZERO)
	for part: Array in _parts(kind):
		var local: Transform3D = shrink * (part[1] as Transform3D)
		# The approved shadow cut also covers leaf-bush proxy/far paths.
		if kind not in NO_SHADOW:
			_bush_multimesh(part[0], rows, local, 0.0, switch, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
		_bush_multimesh(part[0], rows, local, switch, far_end, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind in NO_SHADOW else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	var squares := {}
	for row: Dictionary in rows:
		var square := Vector2i(floori(float(row.x) / LEAF_CELL), floori(float(row.z) / LEAF_CELL))
		if not squares.has(square): squares[square] = []
		(squares[square] as Array).append(row)
	var cell_centre := _rows_centre(rows)
	for square: Vector2i in squares:
		var square_rows: Array = squares[square]
		var reach := switch + _rows_centre(square_rows).distance_to(cell_centre) + 2.0
		for l in leaf_lods.size():
			var end: float = reach if l == leaf_lods.size() - 1 else float(leaf_lods[l][2])
			_bush_multimesh(leaf_lods[l][0], square_rows, Transform3D.IDENTITY, float(leaf_lods[l][1]), end, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	for row: Dictionary in rows:
		if bool(row.get("blocking", false)): _collider(body, row, kind)
	return true

func _bush_multimesh(mesh: Mesh, rows: Array, local: Transform3D, begin: float, end: float, shadow: GeometryInstance3D.ShadowCastingSetting) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = rows.size()
	for i in rows.size():
		mm.set_instance_transform(i, _placement(rows[i]) * local)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_begin = begin
	mmi.visibility_range_end = end
	mmi.cast_shadow = shadow
	add_child(mmi)
	if str(rows[0].kind) in ACTIVITY_STATE.GARDEN:
		for i: int in rows.size(): _remember_garden(str(rows[i].id), mm, i, _placement(rows[i]).origin)

func _remember_garden(id: String, mesh: MultiMesh, index: int, pivot: Vector3) -> void:
	if not _garden_slots.has(id): _garden_slots[id] = []
	(_garden_slots[id] as Array).append({"mesh": mesh, "index": index,
		"original": mesh.get_instance_transform(index), "pivot": pivot})

func _touch_garden(id: String, amount: float) -> void:
	var basis := Basis(Vector3.RIGHT, amount * .025)
	for slot: Dictionary in _garden_slots.get(id, []):
		var pivot: Vector3 = slot.pivot
		(slot.mesh as MultiMesh).set_instance_transform(int(slot.index), Transform3D(basis, pivot - basis * pivot) * slot.original)

func _measured_seat(row: Dictionary, kind: String) -> bool:
	var fit := FITS.get_kind(kind)
	var seat_transform := FITS.transform(fit.get("seat"))
	var slabs: Array = fit.get("slabs", [])
	if not seat_transform.origin.is_finite() or slabs.is_empty() or float(fit.get("depth", 0)) <= 0: return false
	for value: Variant in slabs:
		if not FITS.box(value).has_volume(): return false
	var upper: Array = fit.get("upper", [])
	for value: Variant in upper:
		if not FITS.box(value).has_volume(): return false
	var support := Node3D.new()
	support.name = "KitSeat_" + str(row.id)
	support.transform = _placement(row)
	add_child(support)
	_seat_boxes(support, "SeatSupport", slabs)
	if not upper.is_empty(): _seat_boxes(support, "SeatUpper", upper)
	var seat := preload("res://world/life/seat.gd").new()
	seat.name = "Seat"
	seat.transform = seat_transform
	seat.depth = float(fit.depth)
	seat.set_meta("kit_spot_id", str(row.id))
	var tea := FITS.transform(fit.get("tea_rest"))
	if tea.origin.is_finite():
		var marker := Node3D.new()
		marker.name = "TeaRest"
		marker.transform = seat_transform.affine_inverse() * tea
		seat.add_child(marker)
	support.add_child(seat)
	return true

func _seat_boxes(parent: Node3D, name: String, boxes: Array) -> void:
	var body := StaticBody3D.new()
	body.name = name
	parent.add_child(body)
	for value: Variant in boxes:
		var box := FITS.box(value)
		var shape := CollisionShape3D.new()
		var resource := BoxShape3D.new()
		resource.size = box.size
		shape.shape = resource
		shape.position = box.get_center()
		body.add_child(shape)

func _exit_tree() -> void:
	if is_instance_valid(_activity_state) and _activity_state.touched.is_connected(_touch_garden): _activity_state.touched.disconnect(_touch_garden)
	_garden_slots.clear()

## Centre of the rows' bounding box, about where the renderer measures a MultiMesh's range from.
func _rows_centre(rows: Array) -> Vector3:
	var box := AABB(_placement(rows[0]).origin, Vector3.ZERO)
	for row: Dictionary in rows:
		box = box.expand(_placement(row).origin)
	return box.get_center()
