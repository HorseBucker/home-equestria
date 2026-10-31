extends RefCounted
## Perf 0.1.0 (geometry): a built room's still decoration drawn as one mesh per look.
## Authored rooms build every tube, disc, box and lathe as its own MeshInstance3D with its own
## (often identical) material: the Golden Oak library drew ~350 separate surfaces per pass for
## its stairs, rails, lanterns, carved bays and table roots. merge() gathers the qualifying meshes
## under `root`, groups their surfaces by an equal material (every stored property compared, so two
## separately made but identical materials share one draw) and by the instance settings that
## affect drawing, and adds one MeshInstance3D per group in `root` space with the same vertices.
## The sources are hidden, not freed: their collision bodies, names, meshes and materials stay for
## every other reader. Build time only; no frame callback.
##
## Never merged: meshes carrying metadata, anything under a script, a physics body, an instanced scene or a group not in
## `open_groups` (books, furniture props, beds, candles, open books, doors, lamps), skinned or
## blend-shape meshes, transparent, billboard, next-pass or local-triplanar materials, shader
## materials whose shader is not in `shaders` (those must read the world position, not the local
## one), mirrored transforms, and meshes with visual children.
const META := &"merged_static"

## Rollback: false keeps the template's own range (pieces far from the root could stop a few
## metres sooner than they did on their own).
const RANGE_REACH := true
const REACH := &"range_reach"

## Returns [sources hidden, merged meshes added].
## `shadow_floor` > 0 (rooms inside the town): a piece that town_render_budget.gd would stop
## casting on its own (world size under the floor, or under FLAT_CASTER tall) merges as a
## non-caster, since the merged mesh is too big for that rule to find it afterwards.
const FLAT_CASTER := 0.4   # town_render_budget.gd FLAT_CASTER
static func merge(root: Node3D, open_groups: Array = [], shaders: Array = [], label := "MergedStatic", shadow_floor := 0.0) -> Vector2i:
	var groups: Dictionary = {}   # key -> {"material", "template", "parts": [[arrays, xform]]}
	var signatures: Dictionary = {}  # material -> signature (each material read once)
	var sources: Array[MeshInstance3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not _mergeable(mi, root, open_groups, shaders): continue
		var xform := _relative(mi, root)
		if xform.basis.determinant() <= 0.0: continue
		var cast := mi.cast_shadow
		if shadow_floor > 0.0 and cast != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and mi.is_inside_tree():
			var box: AABB = mi.mesh.get_aabb()
			var size: Vector3 = box.size * mi.global_basis.get_scale()
			if maxf(size.x, maxf(size.y, size.z)) < shadow_floor or (mi.global_transform * box).size.y < FLAT_CASTER:
				cast = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var keys: Array = []
		var ok := true
		for s: int in mi.mesh.get_surface_count():
			var material: Material = mi.get_active_material(s)
			if not _material_ok(material, shaders):
				ok = false; break
			var signature := "default"
			if material != null:
				if not signatures.has(material): signatures[material] = _signature(material)
				signature = signatures[material]
			keys.append("%s|%d|%d|%.3f|%.3f|%d|%d" % [signature, cast, mi.layers,
				mi.visibility_range_end, mi.visibility_range_end_margin, mi.visibility_range_fade_mode, mi.gi_mode])
		if not ok: continue
		for s: int in mi.mesh.get_surface_count():
			var key: String = keys[s]
			if not groups.has(key):
				groups[key] = {"material": mi.get_active_material(s), "template": mi, "cast": cast, "parts": [], "points": []}
			(groups[key].parts as Array).append([mi.mesh.surface_get_arrays(s), xform])
			# Visibility ranges are measured per instance: remember where each piece measured from.
			(groups[key].points as Array).append_array([xform.origin, xform * mi.get_aabb().get_center()])
		sources.append(mi)
	var added := 0
	for key: String in groups:
		var group: Dictionary = groups[key]
		var surface: Array = _build(group.parts)
		if (surface[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty(): continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
		mesh.surface_set_material(0, group.material)
		var template: MeshInstance3D = group.template
		var view := MeshInstance3D.new()
		view.name = "%s%02d" % [label, added]
		view.mesh = mesh
		view.cast_shadow = group.cast
		view.layers = template.layers
		view.gi_mode = template.gi_mode
		view.visibility_range_end = template.visibility_range_end
		if RANGE_REACH:
			# Never stop drawing sooner than any piece did: the merged mesh measures from the root
			# (or its own centre), so its range grows by the farthest piece's offset from either.
			# Range caps applied later (interior_range.gd) read the same allowance from REACH.
			var reach := _reach(group.points, mesh.get_aabb().get_center()) * _scale(root)
			view.set_meta(REACH, reach)
			if template.visibility_range_end > 0.0: view.visibility_range_end += reach
		view.visibility_range_end_margin = template.visibility_range_end_margin
		view.visibility_range_fade_mode = template.visibility_range_fade_mode
		view.set_meta(META, true)
		root.add_child(view)
		added += 1
	for mi: MeshInstance3D in sources:
		mi.visible = false
		mi.set_meta(META, true)
	return Vector2i(sources.size(), added)

static func _mergeable(mi: MeshInstance3D, root: Node, open_groups: Array, shaders: Array) -> bool:
	# Any metadata marks a piece some system reads or tends (lighting shell, food, glass boxes).
	if mi.mesh == null or not mi.get_meta_list().is_empty(): return false
	if mi.skin != null or mi.material_overlay != null or mi.transparency > 0.0 or mi.visibility_range_begin > 0.0: return false
	# Primitive meshes are always triangles; array meshes are checked surface by surface.
	if not (mi.mesh is PrimitiveMesh or mi.mesh is ArrayMesh): return false
	if mi.mesh is ArrayMesh:
		var array_mesh := mi.mesh as ArrayMesh
		if array_mesh.get_blend_shape_count() > 0: return false
		for s: int in array_mesh.get_surface_count():
			if array_mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES: return false
	if not mi.find_children("*", "VisualInstance3D", true, false).is_empty(): return false
	var material_override := mi.material_override
	if material_override != null and not _material_ok(material_override, shaders): return false
	var at: Node = mi
	while at != null and at != root:
		if not at is Node3D or not (at as Node3D).visible or (at as Node3D).top_level or at.get_script() != null or at is CollisionObject3D or not at.scene_file_path.is_empty(): return false
		for group: StringName in at.get_groups():
			if not String(group).begins_with("_") and not open_groups.has(String(group)): return false
		at = at.get_parent()
	return at == root

static func _reach(points: Array, centre: Vector3) -> float:
	var reach := 0.0
	for point: Vector3 in points:
		reach = maxf(reach, maxf(point.length(), point.distance_to(centre)))
	return reach

static func _scale(root: Node3D) -> float:
	var scale: Vector3 = root.global_basis.get_scale() if root.is_inside_tree() else root.basis.get_scale()
	return maxf(absf(scale.x), maxf(absf(scale.y), absf(scale.z)))

## The quality tier's town shadow-size floor (town_render_budget.gd small_caster), for `shadow_floor`.
static func town_shadow_floor(context: Node) -> float:
	var quality: Node = context.get_node_or_null("/root/Quality") if context.is_inside_tree() else null
	return float(quality.get_value("small_caster", 1.6)) if quality != null else 1.6

## Local transforms up to `root`: works before the room is in the tree.
static func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var xform := node.transform
	var at := node.get_parent() as Node3D
	while at != null and at != root:
		xform = at.transform * xform
		at = at.get_parent() as Node3D
	return xform

static func _material_ok(material: Material, shaders: Array) -> bool:
	if material == null: return true
	if material.next_pass != null: return false
	if material is ShaderMaterial:
		return shaders.has((material as ShaderMaterial).shader)
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or base.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED: return false
		if (base.uv1_triplanar and not base.uv1_world_triplanar) or (base.uv2_triplanar and not base.uv2_world_triplanar): return false
		if base.proximity_fade_enabled or base.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED: return false
		return true
	return false

## Every stored property, resources by identity: equal strings draw identically.
static func _signature(material: Material) -> String:
	if material == null: return "default"
	var parts := PackedStringArray([material.get_class(), str(material.render_priority)])
	if material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		parts.append(str(shader_material.shader.get_instance_id()))
		for uniform: Dictionary in shader_material.shader.get_shader_uniform_list():
			var value: Variant = shader_material.get_shader_parameter(uniform.name)
			parts.append("%s=%s" % [uniform.name, str(value.get_instance_id()) if value is Object else var_to_str(value)])
		return "|".join(parts)
	for property: Dictionary in material.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE): continue
		var name: String = property.name
		if name.begins_with("resource_") or name == "script": continue
		var value: Variant = material.get(name)
		parts.append("%s=%s" % [name, str(value.get_instance_id()) if value is Object else var_to_str(value)])
	return "|".join(parts)

## One surface from every part, in root space. Arrays only some parts have are filled with the
## values Godot assumes when they are absent (UV 0, tangent +X, colour white), so nothing changes look.
static func _build(parts: Array) -> Array:
	var has_uv := false
	var has_tangent := false
	var has_color := false
	for part: Array in parts:
		var arrays: Array = part[0]
		has_uv = has_uv or arrays[Mesh.ARRAY_TEX_UV] != null
		has_tangent = has_tangent or arrays[Mesh.ARRAY_TANGENT] != null
		has_color = has_color or arrays[Mesh.ARRAY_COLOR] != null
	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uv := PackedVector2Array()
	var out_tangent := PackedFloat32Array()
	var out_color := PackedColorArray()
	var out_index := PackedInt32Array()
	for part: Array in parts:
		var arrays: Array = part[0]
		var xform: Transform3D = part[1]
		var base := out_vertices.size()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var count := vertices.size()
		var normal_basis := xform.basis.inverse().transposed()
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		for i: int in count:
			out_vertices.append(xform * vertices[i])
			out_normals.append((normal_basis * normals[i]).normalized() if i < normals.size() else Vector3.UP)
		if has_uv:
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			if uvs.size() != count: uvs.resize(count)
			out_uv.append_array(uvs)
		if has_tangent:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			for i: int in count:
				if tangents.size() == count * 4:
					var t := (xform.basis * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])).normalized()
					out_tangent.append_array([t.x, t.y, t.z, tangents[i * 4 + 3]])
				else: out_tangent.append_array([1.0, 0.0, 0.0, 1.0])
		if has_color:
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			if colors.size() != count:
				colors = PackedColorArray(); colors.resize(count); colors.fill(Color.WHITE)
			out_color.append_array(colors)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i: int in count: out_index.append(base + i)
		else:
			for i: int in indices: out_index.append(base + i)
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = out_vertices
	surface[Mesh.ARRAY_NORMAL] = out_normals
	if has_uv: surface[Mesh.ARRAY_TEX_UV] = out_uv
	if has_tangent: surface[Mesh.ARRAY_TANGENT] = out_tangent
	if has_color: surface[Mesh.ARRAY_COLOR] = out_color
	surface[Mesh.ARRAY_INDEX] = out_index
	return surface
