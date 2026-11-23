extends RefCounted
## Ponyville's town river and the bridges over it, for pony trips (world/characters/navigation/
## pony_navigator.gd). A long pony lead picks straight legs; one that meets the river stops on
## the bank (the arrival escort stalled at X 103, Z -47 on 2026-09-30). When the straight way
## from a pony to her goal crosses water, route() gives the approach points of the cheapest
## bridge, 5 m off each end on dry bank, in walking order.
##
## Bridges since the Ponyville overhaul (tools/town_planner/build/plan_scenery.py): the plan's bridges.
## Water: the town canal grid (world/water/ponyville_canals.json, 1 m cells, NaN = dry), the
## same data the water surface is built from. Bridges: the fitted deck ends of the four placed
## bridges in world/props/ponyville/rnl_scenery.json (tools/rnl_scenery/plan.py; the two stone
## footbridges were rejected by the layout and do not exist). Verified by
## tools/navigation/probe_river_paths.gd, which walk-grid-routes every approach pair.
## Re-fitted square to the water with dry ends on 2026-10-22 (tools/rnl_scenery/fit_bridges.py;
## tools/rnl_scenery/probe_bridges.gd checks these against the placed nodes). The Cottage bridge
## (bridge_04, 2026-10-25, player board #2) joins Fluttershy's bank to the island between the
## south and north channels, which the Market road and East bridges reach from the other sides.
const CANALS := "res://world/water/ponyville_canals.json"
const BRIDGE_ENDS := {
	"bridge_01": [Vector2(250.48, -309.90), Vector2(241.04, -311.00)],
	"bridge_02": [Vector2(250.92, -291.08), Vector2(241.36, -292.19)],
	"bridge_03": [Vector2(191.10, -224.34), Vector2(198.58, -212.08)],
	"bridge_04": [Vector2(161.48, -177.97), Vector2(177.23, -175.13)],
	"bridge_05": [Vector2(-50.62, -175.14), Vector2(-60.07, -172.55)],
	"bridge_06": [Vector2(-50.09, -142.05), Vector2(-59.94, -140.89)],
	"bridge_07": [Vector2(134.98, -141.18), Vector2(141.80, -128.39)],
	"bridge_08": [Vector2(-4.30, -102.12), Vector2(-9.82, -94.02)],
	"bridge_09": [Vector2(51.01, -91.14), Vector2(50.36, -81.77)],
	"bridge_10": [Vector2(402.10, -27.57), Vector2(405.37, -19.39)],
	"bridge_11": [Vector2(95.84, -14.39), Vector2(86.99, -14.34)],
	"bridge_12": [Vector2(180.07, -52.56), Vector2(172.18, -47.80)],
	"bridge_13": [Vector2(260.32, -37.29), Vector2(263.56, -45.68)],
}
## Approach pairs walked end to end by a pony, used instead of the computed ones. The South
## bridge's old skewed placement put its computed south point beside the ramp rail
## (tools/navigation/river_trips.gd, 2026-09-30); since the 2026-10-22 re-fit every bridge
## runs straight across with dry ends, so the computed points (5 m off each end) are used.
const WALKED := {}
const APPROACH := 5.0
const STEP := 1.5

static var _loaded := false
static var _heights := PackedFloat32Array()
static var _width := 0
static var _depth := 0
static var _origin := Vector2.ZERO
static var _cell := 1.0
static var _approaches: Dictionary = {}   # bridge id -> [Vector2, Vector2], dry ends

static func _load() -> void:
	if _loaded: return
	_loaded = true
	if not FileAccess.file_exists(CANALS): return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(CANALS))
	if not doc is Dictionary: return
	_width = int(doc.width); _depth = int(doc.depth); _cell = float(doc.cell)
	_origin = Vector2(float(doc.origin[0]), float(doc.origin[1]))
	_heights = Marshalls.base64_to_raw(String(doc.heights)).to_float32_array()
	if _heights.size() != _width * _depth: _heights = PackedFloat32Array()
	for id: String in BRIDGE_ENDS:
		var a: Vector2 = BRIDGE_ENDS[id][0]
		var b: Vector2 = BRIDGE_ENDS[id][1]
		var along := (b - a).normalized()
		_approaches[id] = WALKED[id] if WALKED.has(id) else [_dry_beyond(a, -along), _dry_beyond(b, along)]

## Out from a deck end along the span until the bank is dry, then APPROACH metres more.
static func _dry_beyond(end: Vector2, outward: Vector2) -> Vector2:
	var at := end
	for i in 20:
		if not wet(at): break
		at += outward
	return at + outward * APPROACH

## Water under this ground point (outside the town grid counts as dry).
static func wet(at: Vector2) -> bool:
	_load()
	if _heights.is_empty(): return false
	var i := int(round((at.x - _origin.x) / _cell))
	var j := int(round((at.y - _origin.y) / _cell))
	if i < 0 or j < 0 or i >= _width or j >= _depth: return false
	return not is_nan(_heights[j * _width + i])

## The straight ground line between two points passes over water.
static func crosses(from: Vector2, to: Vector2) -> bool:
	var length := from.distance_to(to)
	var count := maxi(1, ceili(length / STEP))
	for k in range(1, count):
		if wet(from.lerp(to, float(k) / count)): return true
	return false

## Bridge approach points to walk through, in order, from `from` to `to` (world positions); [] when the straight
## way stays dry or no chain of bridges joins the two banks.
## Since the Ponyville overhaul the town has thirteen bridges over a web of streams, and many trips need two of
## them (from the southern meadows into town: a footbridge, then a town bridge). The old choice took one bridge
## only, and only when both of its legs were dry; a trip that needed two got no points at all, and the pony was
## left to a search that ran out of budget (Pinkie stood stranded at X 134, Z -55, play test 2026-11-15). Now: the
## shortest chain over the bridges' approach points, each leg of it a straight dry line or a bridge's own deck.
static func route(from: Vector3, to: Vector3) -> Array:
	_load()
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	if _heights.is_empty() or not crosses(a, b): return []
	_link()
	var count := _nodes.size()
	# Dijkstra over the approach points; -1 is the start, `count` the goal
	var cost: Array[float] = []; var parent: Array[int] = []; var done: Array[bool] = []
	cost.resize(count); parent.resize(count); done.resize(count)
	for i in count:
		done[i] = false; parent[i] = -1
		cost[i] = INF if crosses(a, _nodes[i]) else a.distance_to(_nodes[i])
	var best_end := -1
	var best_cost := INF
	for step in count:
		var at := -1
		for i in count:
			if not done[i] and (at < 0 or cost[i] < cost[at]): at = i
		if at < 0 or not is_finite(cost[at]) or cost[at] >= best_cost: break
		done[at] = true
		if not crosses(_nodes[at], b):
			var total := cost[at] + _nodes[at].distance_to(b)
			if total < best_cost: best_cost = total; best_end = at
		for link: Array in _links[at]:
			var other: int = link[0]
			var through: float = cost[at] + float(link[1])
			if through < cost[other]: cost[other] = through; parent[other] = at
	if best_end < 0: return []
	var chain: Array[Vector2] = []
	var walk := best_end
	while walk >= 0:
		chain.push_front(_nodes[walk]); walk = parent[walk]
	var points: Array = []
	for p: Vector2 in chain:
		var y: float = WorldTerrain.instance.height_at(Vector3(p.x, 0, p.y)) if is_instance_valid(WorldTerrain.instance) else NAN
		points.append(Vector3(p.x, y if is_finite(y) else from.y, p.y))
	return points

## The approach points as a graph, made once: each bridge's two points joined by its deck, and any two points of
## different bridges joined when the straight line between them stays dry.
static var _nodes: Array[Vector2] = []
static var _links: Array = []      # per node: [[other node, metres], ...]
static func _link() -> void:
	if not _nodes.is_empty(): return
	for id: String in _approaches:
		_nodes.append(_approaches[id][0]); _nodes.append(_approaches[id][1])
	for i in _nodes.size(): _links.append([])
	for i in _nodes.size():
		for j in range(i + 1, _nodes.size()):
			var same_bridge := i / 2 == j / 2
			if not same_bridge and crosses(_nodes[i], _nodes[j]): continue
			var metres := _nodes[i].distance_to(_nodes[j])
			(_links[i] as Array).append([j, metres]); (_links[j] as Array).append([i, metres])

## Every bridge's approach pair, for labs and the probe.
static func approaches() -> Dictionary:
	_load()
	return _approaches.duplicate(true)
