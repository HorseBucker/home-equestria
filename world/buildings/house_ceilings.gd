extends RefCounted
## House ceilings: from modChad's Pathfinding Fix 1.1.0 (github.com/modChad/home-equestria-mods, pathfinding_fix/
## house_ceilings.gd), taken into the game itself for the Ponyville overhaul (2026-11-15) so no separate pack is
## needed; called at the end of HouseInterior._ready. The ceiling body keeps the mod's node name, so the mod, if
## it is installed as well, finds the work done and leaves the house alone.
##
## Pathfinding Fix (modChad): house ceilings.
## The walk grid keeps only two floor spans per 25 cm column (WalkGrid.SPANS), and gives up after
## six downward hits. Over a town house the roof, attic floor, porch and balcony roofs (the outer
## shell, Exterior_col) and the door and window reveal frames above the threshold fill both spans,
## so the ground floor inside, the doorway and the stoop under a porch roof are never seen: ponies
## cannot route in and out of the door or settle in the room (House H, found 2026-11-15 with
## tools/_house_lab/probe3.gd). The game only marks Hayburger, Spa and lamp roofs `navigation_ceiling`.
## Fix: after the house's own collision edits (HouseInterior._ready: shell repairs, wing cut, ramp
## clearing), everything lying wholly more than ABOVE_FLOOR above the room floor moves into ONE
## body per house tagged `navigation_ceiling`: high triangles of each static trimesh (the rest stay
## where they were) and whole small shapes (boxes, convex pieces) that sit up there (their own
## holder is disabled). Collision is unchanged (the same triangles and shapes, one layer). The walk
## grid (GDScript and the native column sampler alike) excludes the tagged body from its floor rays
## after the first hit, so it costs one of the six hits, and still measures headroom against it.
## Door leaves (AnimatableBody3D), furniture (added later) and bodies on other layers are untouched.
## Only plain town houses (house_interior.gd itself, designs A to H): authored homes with real
## upper floors (Golden Oak, Sugarcube, ...) are left alone.

const HOUSE := "res://world/buildings/house_interior.gd"
const CEILING_NAME := "PathfindingFixCeiling"
const GROUP := "pathfinding_fix_ceilings"
## Walkable layer: only bodies on exactly this layer are moved, and the ceiling body uses it.
const LAYER := 1
## House units above the room floor (town houses are scaled about 10 to 12, so 1.4 to 1.7 m):
## the stoop, sills and floor fills sit within 0.21, the lowest porch roof about 0.28 up.
const ABOVE_FLOOR := 0.14
## Houses placed at another scale (labs) use metres instead.
const ABOVE_FLOOR_M := 1.6
## [faces hash, house-relative transform, limit, two-sided] -> [low shape or null, high shape or
## null, high bounds]: shared by every house of a design (read-only shapes, as the game's own
## scene shapes are), so later houses skip the split and the shapes' build.
static var _splits := {}


static func is_town_house(interior: Node) -> bool:
	var script := interior.get_script() as Script
	return script != null and script.resource_path == HOUSE and interior.get_parent() is Node3D


## Move this house's high collision into its ceiling body. Returns the world AABB it changed
## (size zero when nothing moved).
static func apply(interior: Node3D) -> AABB:
	var house := interior.get_parent() as Node3D
	var changed := AABB()
	if house == null or not interior.is_inside_tree() or house.has_node(CEILING_NAME): return changed
	var to_house := house.global_transform.affine_inverse()
	var scale_y := house.global_basis.y.length()
	var floor_local: float = (to_house * interior.global_transform * Vector3(0, float(interior.floor_y), 0)).y
	var limit: float = floor_local + (ABOVE_FLOOR if scale_y >= 6.0 and scale_y <= 20.0 else ABOVE_FLOOR_M / maxf(scale_y, .001))
	var ceiling := StaticBody3D.new()
	ceiling.name = CEILING_NAME
	ceiling.collision_layer = LAYER
	ceiling.collision_mask = 0
	ceiling.set_meta("navigation_ceiling", true)
	ceiling.add_to_group(GROUP)
	var undo: Array = []   # [holder, original shape, was disabled]
	var bounds := AABB()
	var moved := 0
	for body: StaticBody3D in house.find_children("*", "StaticBody3D", true, false):
		if body.collision_layer != LAYER or body.physics_material_override != null: continue
		for child: Node in body.get_children():
			var holder := child as CollisionShape3D
			if holder == null or holder.disabled or holder.shape == null: continue
			var rel: Transform3D = to_house * holder.global_transform
			var high_box := AABB()
			if holder.shape is ConcavePolygonShape3D:
				var shape := holder.shape as ConcavePolygonShape3D
				var faces := shape.get_faces()
				var key := [hash(faces), _snapped(rel), snappedf(limit, .0001), shape.backface_collision]
				if not _splits.has(key): _splits[key] = _split(faces, rel, limit, shape.backface_collision)
				var parts: Array = _splits[key]
				if parts[1] == null: continue
				_add(ceiling, parts[1], rel)
				undo.append([holder, shape, false])
				if parts[0] == null: holder.disabled = true
				else: holder.shape = parts[0]
				high_box = rel * (parts[2] as AABB)
			else:
				var box := rel * _local_bounds(holder.shape)
				if box.position.y <= limit: continue
				_add(ceiling, holder.shape, rel)
				undo.append([holder, holder.shape, false])
				holder.disabled = true
				high_box = box
			bounds = high_box if moved == 0 else bounds.merge(high_box)
			moved += 1
	if moved == 0:
		ceiling.free()
		return changed
	ceiling.set_meta("pathfinding_fix_undo", undo)
	ceiling.set_meta("pathfinding_fix_box", house.global_transform * bounds)
	# Deferred: this runs at the end of HouseInterior._ready, while the house is still setting up its children.
	house.add_child.call_deferred(ceiling)
	return house.global_transform * bounds


static func _add(ceiling: StaticBody3D, shape: Shape3D, rel: Transform3D) -> void:
	var node := CollisionShape3D.new()
	node.shape = shape
	node.transform = rel
	ceiling.add_child(node)


## A non-trimesh shape's bounds in its own frame.
static func _local_bounds(shape: Shape3D) -> AABB:
	if shape is BoxShape3D: return AABB(-(shape as BoxShape3D).size * .5, (shape as BoxShape3D).size)
	if shape is ConvexPolygonShape3D:
		var points := (shape as ConvexPolygonShape3D).points
		if points.is_empty(): return AABB()
		var box := AABB(points[0], Vector3.ZERO)
		for p in points: box = box.expand(p)
		return box
	return shape.get_debug_mesh().get_aabb()


## A transform rounded to 0.1 mm, so houses of one design at different scales share a key.
static func _snapped(t: Transform3D) -> Array:
	var step := Vector3.ONE * .0001
	return [t.basis.x.snapped(step), t.basis.y.snapped(step), t.basis.z.snapped(step), t.origin.snapped(step)]


## Faces (shape frame) split by whether their lowest corner, in the house frame, is above `limit`:
## [low shape or null, high shape or null, high bounds (shape frame)].
static func _split(faces: PackedVector3Array, rel: Transform3D, limit: float, two_sided: bool) -> Array:
	var low := PackedVector3Array()
	var high := PackedVector3Array()
	var box := AABB()
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]; var b := faces[i + 1]; var c := faces[i + 2]
		if minf((rel * a).y, minf((rel * b).y, (rel * c).y)) > limit:
			if high.is_empty(): box = AABB(a, Vector3.ZERO)
			high.append(a); high.append(b); high.append(c)
			box = box.expand(a).expand(b).expand(c)
		else:
			low.append(a); low.append(b); low.append(c)
	return [_shape(low, two_sided), _shape(high, two_sided), box]


static func _shape(faces: PackedVector3Array, two_sided: bool) -> ConcavePolygonShape3D:
	# Triangles with no area are left out (Ponyville overhaul): a house shell carries a few, and a part made of
	# nothing else is refused by the physics engine ("Need triangles to create a mesh shape").
	var solid := PackedVector3Array()
	for i in range(0, faces.size() - 2, 3):
		if (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).length_squared() > 1e-10:      # (the engine's own test is 1e-12 on this cross product)
			solid.append(faces[i]); solid.append(faces[i + 1]); solid.append(faces[i + 2])
	if solid.is_empty(): return null
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = two_sided
	shape.set_faces(solid)
	return shape


## Put every house back (mod switched off). Returns the world AABBs touched.
static func undo_all(tree: SceneTree) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for ceiling: Node in tree.get_nodes_in_group(GROUP):
		for entry: Array in ceiling.get_meta("pathfinding_fix_undo", []):
			var holder := entry[0] as CollisionShape3D
			if not is_instance_valid(holder): continue
			holder.shape = entry[1]
			holder.disabled = bool(entry[2])
		if ceiling.has_meta("pathfinding_fix_box"): boxes.append(ceiling.get_meta("pathfinding_fix_box"))
		ceiling.queue_free()
	return boxes
