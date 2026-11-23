extends "res://world/life/day/actions/tend.gd"
## Carrot Top's fields (play test 2026-11-16: "Carrot Top (aka Golden Harvest) should be able to get to
## her carrots and look like she's doing stuff there, when the season is right for it."). A routine
## step (world/life/day/tables/routines.json "carrot_fields_morning" / "_afternoon", spring to autumn
## by the calendar's season; the crop rows are hidden in winter by kit_dressing.gd). The garden "tend"
## step only finds a pony's own house planting (kit_spots.gd), and her crop rows belong to the farm
## (kit group "carrot-farm"), so this walks her row to row through the beds near her farmhouse (the
## step's target, found at run time) and works each one the way tend.gd waters a garden: up to the
## bed, a look down over it, the watering can out and a pour, then on to the next bed with the can
## still in her mouth, until the routine's end hour. The rows are not in kit_state's garden kinds, so
## the visit is not recorded as a watered garden (nothing reads it for crops).

const FIELD_RADIUS := 70.0
## Beds she works per visit (picked near each other, then walked in order), and how far beside a bed
## she stands: half the spacing of the rows, in the furrow between two.
const BEDS := 10
const FURROW := 0.9
const MAX_MISSES := 4
var _beds: Array = []
var _next := 0
var _misses := 0
var _worked := 0
var _at_work := false


## Where her essence works while unloaded (day_runner._essence_run): the crop row nearest her
## farmhouse, not the farmhouse itself.
static func essence_point(tree: SceneTree, step: Dictionary) -> Vector3:
	var farm: Node3D = PLACES.find(tree, str(step.get("target", ""))).get("node") as Node3D
	if farm == null or not farm.is_inside_tree(): return Vector3.INF
	var best := Vector3.INF
	for record: Dictionary in SPOTS.of_kind("crop_row"):
		var at: Vector3 = record.position
		if not best.is_finite() or at.distance_squared_to(farm.global_position) < best.distance_squared_to(farm.global_position): best = at
	return best if best.is_finite() and best.distance_to(farm.global_position) <= FIELD_RADIUS else Vector3.INF


func start(ctx: Dictionary) -> bool:
	if not is_instance_valid(ctx.get("actor")) or not is_instance_valid(ctx.get("nav")): return false
	# the player switched the farm's crops off (Settings > Graphics, town_extras.gd): nothing to tend
	if not preload("res://world/towns/ponyville/town_extras.gd").carrot_farm_on(): return false
	var farm: Node3D = PLACES.find(ctx.tree, str(ctx.step.target)).get("node") as Node3D
	var centre: Vector3 = farm.global_position if farm != null else ctx.actor.global_position
	_beds = _pick_beds(ctx, centre)
	if _beds.is_empty(): return false
	while _next < _beds.size():
		var spot: Dictionary = _beds[_next]
		_next += 1
		if _begin(ctx, spot): return true
	return false


## BEDS crop rows near the farmhouse, a different stretch each day, in walking order.
func _pick_beds(ctx: Dictionary, centre: Vector3) -> Array:
	var near: Array = []
	for record: Dictionary in SPOTS.of_kind("crop_row"):
		var at: Vector3 = record.position
		if Vector2(at.x - centre.x, at.z - centre.z).length() <= FIELD_RADIUS: near.append(record)
	if near.is_empty(): return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("fields:%s:%d:%s" % [str(ctx.id), int(ctx.get("day", 0)), str(ctx.step.get("action", ""))])
	var first: Dictionary = near[rng.randi_range(0, near.size() - 1)]
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.position as Vector3).distance_squared_to(first.position) < (b.position as Vector3).distance_squared_to(first.position))
	var chosen: Array = []
	var here: Vector3 = first.position
	var pool: Array = near.slice(0, mini(near.size(), BEDS * 3))
	while chosen.size() < BEDS and not pool.is_empty():
		# The nearest bed to the last one, skipping a neighbour now and then so she moves along the rows.
		pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a.position as Vector3).distance_squared_to(here) < (b.position as Vector3).distance_squared_to(here))
		var take: int = mini(pool.size() - 1, rng.randi_range(0, 1))
		var bed: Dictionary = (pool[take] as Dictionary).duplicate()
		pool.remove_at(take)
		here = bed.position
		# Stand in the furrow beside the bed (its side towards her farmhouse), facing the bed.
		var transform: Transform3D = bed.transform
		var across: Vector3 = transform.basis.x.normalized()
		if across.dot(centre - here) < 0.0: across = -across
		var stand: Vector3 = here + across * FURROW
		if is_instance_valid(WorldTerrain.instance):
			var height: float = WorldTerrain.instance.height_at(stand)
			if is_finite(height): stand.y = height
		bed.approach = stand
		chosen.append(bed)
	return chosen


func tick(ctx: Dictionary, delta: float) -> String:
	if _over(ctx): return "done" if _worked > 0 else "failed"
	var result := super.tick(ctx, delta)
	# At her first bed (the runner writes "Today's plan: ..." when the step starts, after start()).
	if _phase != "travel" and not _at_work:
		_at_work = true
		ctx.actor.set_meta("life_intent", "Out in her carrot fields, tending the carrot beds")
	if result == "running": return result
	if result == "done":
		_worked += 1
		_misses = 0
	else:
		_misses += 1
		if _misses > MAX_MISSES or not _owns_navigation(ctx): return "done" if _worked > 0 else "failed"
	# On to the next bed (round again when she has done them all).
	if _next >= _beds.size(): _next = 0
	var spot: Dictionary = _beds[_next]
	_next += 1
	_unlock_spot()
	if not _lock_spot(ctx, _snapped(ctx, spot)):
		_misses += 1
		return "running"
	_phase = "travel"
	if is_instance_valid(_prop): _prop.carry_seconds = TRAVEL_LIMIT + 30.0
	_navigate(ctx)
	return "running"


## The furrow point on her walk grid when it is that close (as tend.gd's _begin does for the first bed).
func _snapped(ctx: Dictionary, spot: Dictionary) -> Dictionary:
	var approach: Vector3 = spot.approach
	if not ctx.nav.has_method("command_support"): return spot
	var walkable: Vector3 = ctx.nav.command_support(approach)
	if not walkable.is_finite() or Vector2(walkable.x - approach.x, walkable.z - approach.z).length() > _snap_radius(): return spot
	var copy := spot.duplicate()
	copy.approach = walkable
	return copy


func _over(ctx: Dictionary) -> bool:
	if ctx.step.has("end") and is_instance_valid(ctx.get("runner")) and ctx.runner.has_method("_card_hours"):
		return float(ctx.runner.call("_card_hours")) >= float(ctx.step.end)
	return seconds >= duration(float(ctx.step.get("minutes", 60.0)))


## A crop row is not a garden kind for kit_state: the pour itself is the work.
func _mark_watered(_ctx: Dictionary) -> bool:
	return true


## A furrow is narrow: a grid cell farther off than this would put her up on a bed (lab 2026-11-16).
func _snap_radius() -> float:
	return 0.3
