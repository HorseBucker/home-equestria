extends RefCounted
## Ponies spread out at a landmark instead of all standing on its one anchor point (2026-11-22 play test: "a few
## other ponies came to the market ... they all kind of gathered right here in a single area. I'd like it if when
## ponies go to these types of locations, like the market, or town hall, or any other place that has some room ...
## they were more spread out"; and Scootaloo stood on top of a market stall: the market's anchor is under one, and an
## unloaded pony there was set down on its awning when she streamed in).
##
## point() gives each pony her own open spot round the anchor: on the ground (nothing built over it or within a pony's
## width of it: stalls, carts, lamps, the fountain's basin), on the anchor's level (not down in a stream), and at least
## APART from every other pony's spot there. Seeded by her id and the place, so her body and her unloaded essence go to
## the same spot. Places inside a building (house_interior.gd visit_point) and non-landmark targets are left alone.

const HOME := preload("res://world/buildings/house_interior.gd")
## How far round the anchor ponies spread (metres); the rest DEFAULT_RADIUS. Roomy squares spread wider; bridges and
## the dock keep close to their bank point.
const RADIUS := {"landmark:ponyville_market": 12.0, "landmark:town_hall": 11.0, "landmark:fountain_01": 9.0,
	"landmark:bridge_01": 3.5, "landmark:bridge_02": 3.5, "landmark:bridge_03": 3.5, "landmark:bridge_04": 3.5}
const DEFAULT_RADIUS := 7.0
const MIN_RADIUS := 2.0
const APART := 1.8
const TRIES := 28

static var _spots: Dictionary = {}     # pony id -> [target, Vector3]
static var last_misses: Dictionary = {}   # why the last pony left on the anchor found no spot (labs)


static func point(tree: SceneTree, id: String, target: String, anchor: Vector3) -> Vector3:
	if tree == null or id.is_empty() or not target.begins_with("landmark:") or not anchor.is_finite(): return anchor
	if not is_instance_valid(WorldTerrain.instance) or tree.root.get_world_3d() == null: return anchor
	var kept: Variant = _spots.get(id)
	var hall: Node3D = HOME.at(tree, anchor)
	if hall != null:
		# a building with its own visiting places (Sugarcube Corner's slots) chooses them; one without (Town Hall) is
		# spread over its floor (2026-11-22 play test: 11 ponies stood in the middle of Town Hall)
		if hall.has_method("request_visit") or not ("floors" in hall) or not ("floor_y" in hall): return anchor
		if kept is Array and str(kept[0]) == target and hall.call("contains", kept[1]):
			# picked while the room was not loaded: kept while it still is not, or while it proves clear
			var state := _floor_clear(tree.root.get_world_3d().direct_space_state, kept[1])
			if state != "blocked": return kept[1]
		return _inside(tree, id, target, hall, anchor)
	if kept is Array and str(kept[0]) == target and (kept[1] as Vector3).distance_to(anchor) < float(RADIUS.get(target, DEFAULT_RADIUS)) + 3.0:
		return kept[1]
	var ground: float = WorldTerrain.instance.height_at(anchor)
	if not is_finite(ground): ground = anchor.y
	var space := tree.root.get_world_3d().direct_space_state
	var misses := {}
	var best := Vector3.INF
	var best_gap := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id + "@" + target)
	var reach: float = RADIUS.get(target, DEFAULT_RADIUS)
	# a building's anchor is inside it: start beyond its walls, and look wider when the near ring is full or built up
	var inner := MIN_RADIUS
	for i in TRIES * 2:
		if i == TRIES: inner = reach * 0.6; reach *= 1.8
		var angle := rng.randf() * TAU
		var r := lerpf(inner, reach, sqrt(rng.randf()))
		var at := anchor + Vector3(cos(angle), 0.0, sin(angle)) * r
		var h: float = WorldTerrain.instance.height_at(at)
		if not is_finite(h) or absf(h - ground) > 1.2: misses["level"] = int(misses.get("level", 0)) + 1; continue   # a stream, a bank
		at.y = h
		if covered(space, at): misses["built"] = int(misses.get("built", 0)) + 1; continue
		if _crowded(id, target, at):
			misses["crowded"] = int(misses.get("crowded", 0)) + 1
			var gap := _gap(id, target, at)
			if gap > best_gap: best_gap = gap; best = at
			continue
		_spots[id] = [target, at]
		return at
	last_misses = misses
	# every open spot near another pony's: the roomiest of them, never the anchor (on the stall, in the basin)
	var chosen := best if best.is_finite() else anchor
	_spots[id] = [target, chosen]
	return chosen


## A spot on a building's floor (its floors rects, local), clear of its walls and furniture, apart from the others.
static func _inside(tree: SceneTree, id: String, target: String, hall: Node3D, anchor: Vector3) -> Vector3:
	var rects: Array = hall.get("floors")
	if rects.is_empty(): return anchor
	var floor_y := float(hall.get("floor_y"))
	var space := tree.root.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id + "@" + target)
	var misses := {}
	var best := Vector3.INF
	var best_gap := 0.0
	for i in TRIES * 2:
		var rect: Rect2 = rects[rng.randi_range(0, rects.size() - 1)]
		if not rect.has_area(): continue
		var local := Vector3(rng.randf_range(rect.position.x, rect.end.x), floor_y, rng.randf_range(rect.position.y, rect.end.y))
		var at := hall.to_global(local)
		if not hall.call("contains", at): misses["outside"] = int(misses.get("outside", 0)) + 1; continue
		var state := _floor_clear(space, at)
		if state == "blocked": misses["built"] = int(misses.get("built", 0)) + 1; continue
		if _crowded(id, target, at):
			misses["crowded"] = int(misses.get("crowded", 0)) + 1
			var gap := _gap(id, target, at)
			if gap > best_gap: best_gap = gap; best = at
			continue
		_spots[id] = [target, at]
		return at
	last_misses = misses
	if best.is_finite(): _spots[id] = [target, best]; return best
	return anchor


## A floor point indoors: "clear" (its floor, nothing standing within a pony's width), "blocked" (furniture, a wall,
## not floor), or "unloaded" (no collision there yet: far from Anon, the room is not built; kept, checked again later).
static func _floor_clear(space: PhysicsDirectSpaceState3D, at: Vector3) -> String:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.8, at + Vector3.DOWN * 0.5, 1))
	if hit.is_empty(): return "unloaded"
	if absf((hit.position as Vector3).y - at.y) > 0.2: return "blocked"
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new(); shape.radius = 0.6
	query.shape = shape; query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.85)
	return "blocked" if not space.intersect_shape(query, 1).is_empty() else "clear"


## Something built over the point, or standing within a pony's width of it (terrain aside).
static func covered(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 14.0, at + Vector3.DOWN * 0.5, 1)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and not (hit.collider as Object).is_class("Terrain3D") and (hit.position as Vector3).y > at.y + 0.25: return true
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new(); shape.radius = 0.65
	query.shape = shape; query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.9)
	for found: Dictionary in space.intersect_shape(query, 4):
		if not (found.collider as Object).is_class("Terrain3D"): return true
	return false


static func _crowded(id: String, target: String, at: Vector3) -> bool:
	for other: String in _spots:
		if other == id: continue
		var spot: Array = _spots[other]
		if str(spot[0]) == target and Vector2((spot[1] as Vector3).x - at.x, (spot[1] as Vector3).z - at.z).length() < APART: return true
	return false


## How far the nearest other pony's spot at the place is.
static func _gap(id: String, target: String, at: Vector3) -> float:
	var nearest := INF
	for other: String in _spots:
		var spot: Array = _spots[other]
		if other != id and str(spot[0]) == target:
			nearest = minf(nearest, Vector2((spot[1] as Vector3).x - at.x, (spot[1] as Vector3).z - at.z).length())
	return nearest


## She left the place: her spot is free for another.
static func release(id: String) -> void:
	_spots.erase(id)
