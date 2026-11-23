extends RefCounted
## Standing points around a scenery building or prop, found at run time (play test 2026-11-16: the
## schoolyard class, the Crusaders' clubhouse meet-up and where they go crusading). The town is rebuilt
## by tools/town_planner, so nothing here knows a map position: a node's own mesh bounds give its
## footprint, and a pony's navigator says which points are walkable ground.

## The node's mesh bounds in its own frame (scale kept out of the basis), or an empty AABB.
static func local_bounds(node: Node3D) -> AABB:
	var frame := node.global_transform.orthonormalized()
	var inverse := frame.affine_inverse()
	var box := AABB()
	var first := true
	for mesh: Node in node.find_children("*", "VisualInstance3D", true, false):
		var visual := mesh as VisualInstance3D
		if visual == null or not visual.is_visible_in_tree(): continue
		var local := inverse * visual.global_transform
		var aabb := visual.get_aabb()
		for i in 8:
			var corner: Vector3 = local * aabb.get_endpoint(i)
			if first: box = AABB(corner, Vector3.ZERO); first = false
			else: box = box.expand(corner)
	return box

## `at` on the terrain (an unloaded pony's essence has no walk grid), or `at` itself off the terrain.
static func grounded(at: Vector3) -> Vector3:
	if not is_instance_valid(WorldTerrain.instance): return at
	var height: float = WorldTerrain.instance.height_at(at)
	return Vector3(at.x, height, at.z) if is_finite(height) else at

## `at` on walkable ground as `nav` sees it (within `snap` m), or INF. No navigator: on the terrain.
static func walkable(nav: Node, at: Vector3, snap := 0.6) -> Vector3:
	if nav == null or not nav.has_method("command_support"): return grounded(at)
	var ground: Vector3 = nav.command_support(at)
	if not ground.is_finite() or Vector2(ground.x - at.x, ground.z - at.z).length() > snap: return Vector3.INF
	return ground

## A ring of `count` walkable points `clearance` m outside the node's footprint (in its own frame),
## nearest `toward` first. `lenient`: a point her walk grid does not know yet (its cells are sampled
## a while after first asked for) is kept on the terrain; her navigator finds the way there.
static func ring(nav: Node, node: Node3D, clearance: float, count := 16, toward := Vector3.INF, lenient := true) -> Array:
	var frame := node.global_transform.orthonormalized()
	var box := local_bounds(node)
	if box.size == Vector3.ZERO: box = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 1.0, 2.0))
	var centre := box.get_center()
	var half := Vector2(box.size.x * 0.5 + clearance, box.size.z * 0.5 + clearance)
	var out: Array = []
	for i in count:
		var angle := TAU * float(i) / float(count)
		var dir := Vector2(cos(angle), sin(angle))
		# Onto the rectangle's edge, not a circle: a long building keeps the same clearance all round.
		var scale := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var local := Vector3(centre.x + dir.x * scale, box.position.y, centre.z + dir.y * scale)
		var world := frame * local
		var ground := walkable(nav, world)
		if not ground.is_finite() and lenient: ground = grounded(world)
		if ground.is_finite(): out.append(ground)
	if toward.is_finite():
		out.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(toward) < b.distance_squared_to(toward))
	return out

## A scenery node by name under the town's RNLScenery that holds `near` (or anywhere in the tree).
static func scenery_node(near: Node, name: String) -> Node3D:
	var root: Node = near
	while root != null and str(root.name) != "RNLScenery": root = root.get_parent()
	if root == null and near != null: root = near.get_tree().root
	return root.find_child(name, true, false) as Node3D if root != null else null
