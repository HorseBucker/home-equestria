extends RefCounted
## Ponyville overhaul: houses cast their sun shadow from a simplified hull (2026-11-22 optimisation pass,
## recommendation 1; measured with tools/town_planner/build/qc/lab_render_attrib.gd). Used by the base game's
## world/performance/town_render_budget.gd through four marked hooks (search "HULLS"); everything else is here.
##
## Why: town_render_budget.gd merges every still, opaque caster into shadow-only meshes per 64 m cell and starts them
## at a coarse LOD, but a cell whose LODs never get that low keeps its full mesh, and thatched roofs never do: the
## merged shadows held 5.1M triangles, mostly whole houses (each drawn again per shadow cascade): 3.5M of the 6.3M
## triangles a street view drew at high density.
##
## What: a house's exterior (a real house's "Exterior" under its plot, or a background house's) casts no longer from
## its own opaque surfaces but from a hull of them made the way town_render_budget.gd makes its house occluders
## (_occluder_for: each surface's coarsest generated LOD that still has its share of HULL_TRIANGLES), one per design,
## merged per cell like the rest. A background house's inward lining (the shell again, only seen past a window pane) is
## left out. Alpha-cut and glass surfaces keep casting as before.
## Near the camera a house casts its own full shadow again (NEAR_FULL): a hull is simplified, so up close it shaded the
## house's own walls a little wrongly (diagonal streaks across a background house's front door at 7 m); further off
## that is a pixel or two, and that is where nearly all the saving is. So does the house the camera is inside, at any
## distance (the hull closes the window openings, which would take the sunlight patches off its floors), as
## town_render_budget.gd already does for that house's occluder and doors.

const HULL_TRIANGLES := 1500          # (town_render_budget.gd OCCLUDER_TRIANGLES)
const LINING := "Background house lining"
const NEAR_FULL := 30.0               # metres from the camera to a house's middle

static var _hulls := {}                # mesh instance id -> [vertices, indices] in the mesh's space, or [] (no hull)

var _cells := {}                       # [cell x, cell z, double] -> {"entries": [...], "node": MeshInstance3D}
var _entry_of := {}                    # real house interior -> its entry
var _full := {}                        # entry id -> the entry, casting its own full shadow now
var _next_id := 0
var _dirty := {}                       # cells waiting for a rebuild (update: one at a time)
var _one_sided: StandardMaterial3D
var _two_sided: StandardMaterial3D
var statistics := {"real": 0, "background": 0, "hull_triangles": 0, "replaced_triangles": 0, "cells": 0}


## town_render_budget.gd _merge_shadows, per mesh it merges: true when mi is a house exterior whose plain opaque
## surfaces (kinds[s] == null) this hull now casts for; the caller then skips those surfaces.
## occluder: the base game's hull of this mesh (town_render_budget.gd _occluders), used as it is for a real house.
func take(mi: MeshInstance3D, kinds: Array, town: Node, double: bool, cell_size: float, occluder: Variant) -> bool:
	if str(mi.name) != "Exterior" or OS.get_cmdline_user_args().has("--no-hulls"): return false   # (--no-hulls: before/after tests)
	var home: Node = null
	var background := false
	var up: Node = mi.get_parent()
	while up != null and up != town:
		if up.has_meta("background_house"): background = true; break
		if up.get_parent() == town and str(up.name).begins_with("plot_"):
			for node: Node in up.find_children("*", "", true, false):
				if node.is_in_group("house_interiors"): home = node; break
			break
		up = up.get_parent()
	if not background and home == null: return false
	var hull: Array = _hull(mi, kinds) if background or not occluder is ArrayOccluder3D else [(occluder as ArrayOccluder3D).vertices, (occluder as ArrayOccluder3D).indices]
	if hull.is_empty(): return false
	var xf := mi.global_transform
	var vertices := PackedVector3Array()
	for v: Vector3 in hull[0]: vertices.append(xf * v)
	var centre := (xf * mi.get_aabb()).get_center()
	var key := [floori(centre.x / cell_size), floori(centre.z / cell_size), double]
	if not _cells.has(key): _cells[key] = {"entries": [], "node": null}
	_next_id += 1
	var entry := {"id": _next_id, "home": home, "exterior": mi, "cast": mi.cast_shadow,
		"vertices": vertices, "indices": hull[1], "key": key, "middle": centre}
	_cells[key].entries.append(entry)
	if home != null: _entry_of[home] = entry
	statistics["background" if background else "real"] += 1
	statistics.hull_triangles += (hull[1] as PackedInt32Array).size() / 3
	for s in kinds.size():
		if kinds[s] == null: statistics.replaced_triangles += maxi(mi.mesh.surface_get_array_index_len(s), mi.mesh.surface_get_array_len(s)) / 3
	return true


## After the merge: one shadow-only mesh per cell of hulls, under the merged shadows' holder.
func build(holder: Node) -> void:
	_one_sided = StandardMaterial3D.new()
	_two_sided = StandardMaterial3D.new(); _two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	for key: Array in _cells:
		# once: the cell's vertices, and each house's triangles already pointing into them, so a rebuild when a house
		# comes near or goes (update) only joins index lists (natively: 10.9 ms per rebuild in GDScript loops before)
		var vertices := PackedVector3Array()
		for entry: Dictionary in _cells[key].entries:
			var base := vertices.size()
			vertices.append_array(entry.vertices)
			var offset := PackedInt32Array()
			offset.resize((entry.indices as PackedInt32Array).size())
			var i := 0
			for index: int in entry.indices: offset[i] = index + base; i += 1
			entry.offset_indices = offset
			entry.erase("vertices"); entry.erase("indices")
		_cells[key].vertices = vertices
		var node := MeshInstance3D.new()
		node.name = "Hulls_%d_%d%s" % [key[0], key[1], "_double" if key[2] else ""]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		holder.add_child(node)
		_cells[key].node = node
		_fill(key)
	statistics.cells = _cells.size()


## town_render_budget.gd _process (every quarter second), with the camera's position and the house it is in (null
## outdoors): the houses near it, and that one, cast their own full shadow; the rest through their hulls.
func update(camera_at: Vector3, home: Node) -> void:
	for key: Array in _cells:
		for entry: Dictionary in _cells[key].entries:
			var full: bool = (entry.home != null and entry.home == home) or Vector2((entry.middle as Vector3).x - camera_at.x, (entry.middle as Vector3).z - camera_at.z).length() < NEAR_FULL
			if full == _full.has(entry.id): continue
			if full:
				_full[entry.id] = entry
				# its own full shadow at once (until its cell is rebuilt it casts twice, in the same shape)
				var exterior: MeshInstance3D = entry.exterior
				if is_instance_valid(exterior): exterior.cast_shadow = entry.cast
			else: _full.erase(entry.id)      # (its own shadow goes off when its cell has its hull again: _fill)
			_dirty[key] = true
	# one cell per quarter second at most (about 2 ms each): crossing several cells at once took up to 10 ms
	if not _dirty.is_empty():
		var key: Array = _dirty.keys()[0]
		_dirty.erase(key)
		_fill(key)


func _fill(key: Array) -> void:
	var cell: Dictionary = _cells[key]
	var node: MeshInstance3D = cell.node
	if not is_instance_valid(node): return
	var indices := PackedInt32Array()
	for entry: Dictionary in cell.entries:
		if _full.has(entry.id): continue
		indices.append_array(entry.offset_indices)
		var exterior: MeshInstance3D = entry.exterior
		if is_instance_valid(exterior) and exterior.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			exterior.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if indices.is_empty():
		node.mesh = null; return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = cell.vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _two_sided if key[2] else _one_sided)
	node.mesh = mesh


## The hull of a mesh's plain opaque surfaces (kinds[s] == null, not a background house's lining): each reduced to its
## coarsest generated LOD that still has its share of HULL_TRIANGLES, as town_render_budget.gd _occluder_for does.
## One per mesh (the houses of a design share theirs).
static func _hull(mi: MeshInstance3D, kinds: Array) -> Array:
	var mesh := mi.mesh
	var id := mesh.get_instance_id()
	if _hulls.has(id): return _hulls[id]
	var picked: Array[int] = []
	var total := 0
	for s in mesh.get_surface_count():
		if s >= kinds.size() or kinds[s] != null: continue
		var material := mi.get_active_material(s)
		if material != null and material.resource_name.begins_with(LINING): continue
		picked.append(s)
		total += maxi(mesh.surface_get_array_index_len(s), mesh.surface_get_array_len(s)) / 3
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for s: int in picked:
		var arrays := mesh.surface_get_arrays(s)
		var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(source.size()))
		var target := maxi(HULL_TRIANGLES * source_indices.size() / 3 / maxi(total, 1), 12)
		var chosen := source_indices
		var slim := []
		slim.resize(Mesh.ARRAY_MAX)
		slim[Mesh.ARRAY_VERTEX] = source
		if arrays[Mesh.ARRAY_NORMAL] != null: slim[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		slim[Mesh.ARRAY_INDEX] = source_indices
		var importer := ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, slim)
		importer.generate_lods(60.0, 25.0, [])
		for lod in importer.get_surface_lod_count(0):
			var candidate := importer.get_surface_lod_indices(0, lod)
			chosen = candidate
			if candidate.size() / 3 <= target: break
		var base := vertices.size()
		vertices.append_array(source)
		for i in chosen: indices.append(i + base)
	_hulls[id] = [] if indices.is_empty() else [vertices, indices]
	return _hulls[id]
