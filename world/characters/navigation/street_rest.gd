extends RefCounted
## Free time is spent on the grass, not in the street (2026-11-22 play test: "When ponies are just standing around in
## the road throughout town ... I do kind of wish they'd move on to the grass, rather than sitting in the middle of the
## street, since it messes with ponies pathfinding. I also think it's cuter and more realistic that they'd rather lay
## in the grass ... The exception to this should obviously be the market and town hall").
##
## A wander that ends on a street or dirt path is moved onto the nearest grass beside it (navigator_wander.gd), and a
## pony about to rest on one walks the few steps off it first. Streets are told by the ground's paint (the overhaul's
## apply_paint.py: town street sage, dirt trail, town dirt, rail gravel), so they need no layer of their own. The
## market and Town Hall squares (PLAZAS) are left as they are.

const STREET_TEXTURES := [22, 1, 4, 5]      # sage street, dirt trail, town dirt, rail gravel (apply_paint.py ids)
const PLAZAS := {"landmark:ponyville_market": 26.0, "landmark:town_hall": 30.0}
const SEARCH := [2.0, 3.5, 5.0, 7.0, 9.5]
const ANGLES := 10
const PLACES := preload("res://world/navigation/place_directory.gd")
static var _plaza_points: Dictionary = {}


static func texture_at(at: Vector3) -> int:
	var terrain := WorldTerrain.instance
	if not is_instance_valid(terrain) or not is_instance_valid(terrain.terrain): return -1
	var data: Object = terrain.terrain.data
	if data == null or not data.has_method("get_texture_id"): return -1
	var info: Vector3 = data.call("get_texture_id", at)
	if not info.is_finite(): return -1
	return int(info.y if info.z >= .5 else info.x)


static func on_street(tree: SceneTree, at: Vector3) -> bool:
	if not texture_at(at) in STREET_TEXTURES: return false
	return not in_plaza(tree, at)


static func in_plaza(tree: SceneTree, at: Vector3) -> bool:
	for id: String in PLAZAS:
		if not _plaza_points.has(id):
			var p := PLACES.resolve(tree, id)
			if not p.is_finite(): continue
			_plaza_points[id] = p
		var c: Vector3 = _plaza_points[id]
		if Vector2(at.x - c.x, at.z - c.z).length() < float(PLAZAS[id]): return true
	return false


## The nearest walkable grass beside `at` (not street, not a doorway), or INF.
static func grass_near(nav: Node, at: Vector3) -> Vector3:
	var service: Variant = nav.get("_service")
	var pony: Node3D = nav.get("pony")
	if service == null or pony == null: return Vector3.INF
	var tree := nav.get_tree()
	var start := randf() * TAU
	for r: float in SEARCH:
		for k in ANGLES:
			var a := start + TAU * float(k) / ANGLES
			var p := at + Vector3(cos(a), 0.0, sin(a)) * r
			if texture_at(p) in STREET_TEXTURES or texture_at(p) < 0: continue
			var snapped: Vector3 = service.closest(p, pony.get("profile"), 1.0)
			if not snapped.is_finite() or absf(snapped.y - at.y) > 1.0: continue
			if texture_at(snapped) in STREET_TEXTURES: continue
			if preload("res://world/navigation/rest_placement.gd").passage(tree, snapped, float(pony.get("profile").radius)): continue
			return snapped
	return Vector3.INF


## Free time only: her own wandering or life's, not a day step, a command or a conversation.
static func free_time(nav: Node) -> bool:
	var owner := str(nav.get("command_owner"))
	return owner.is_empty() or owner.begins_with("life:")
