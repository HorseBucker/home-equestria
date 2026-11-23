extends "res://world/life/day/day_action.gd"
## Drink at the Town Square fountain (play test 2026-11-16: "Give ponies the ability to walk over to
## the fountain and dip their heads down to drink from it. Make this something the ponies can just go
## do like they can with fishing."). A day-card step like fishing (day_tables.json "drink_fountain"):
## she walks to a free spot at the basin (world/water/fountain_water.gd drink_spots, one pony a spot),
## turns to the water, and fountain_drinker.gd does the drink itself (play test 2026-11-16: "work with
## ponies of all sizes"): fitted to her measured size against the basin, a tall pony steps closer and
## leans down over the rim, a smaller one rears and puts her forehooves up on the rim top and lowers
## her head to the water (fountain_drink_pose.gd); eyes shut while she sips; then she backs onto the
## spot she walked to and goes on with her day. A rig without that skeleton looks down with its
## secondary motion instead.
## Refused (the runner drops the step) with no fountain loaded, an iced-over basin, no free spot she
## can stand on, or a pony too small for even the forehooves-up drink (a foal at the smaller size
## settings); given up when she cannot get there. Any other owner of her navigator (the player, a
## command, bedtime) ends it at once; a chat holds it in place (day_runner.gd), and the drinker
## stands her down meanwhile.

const FOUNTAIN := preload("res://world/water/fountain_water.gd")
const DRINKER := preload("res://world/life/day/actions/fountain_drinker.gd")
const DRINK_POSE := preload("res://world/life/day/actions/fountain_drink_pose.gd")
## The whole drink (turn, step closer, rear, sips, step down, back): longer is a stuck drinker.
const DRINK_LIMIT := 60.0
const TRAVEL_LIMIT := 120.0
const ALIGN_LIMIT := 10.0
## A walk-grid cell this close to the measured standing point still reaches the water.
const SNAP := 0.35
const ARRIVAL := 0.6
## A rig without the drinking pose: SIPS looks down of SIP_SECONDS each, SETTLE_SECONDS either side.
const SIPS := 3
const SIP_SECONDS := 2.2
const SETTLE_SECONDS := 1.0
var _counted := false
var _fountain: Node3D
var _index := -1
var _spot: Dictionary = {}
var _point := Vector3.INF
var _phase := "travel"
var _phase_seconds := 0.0
var _tries := 0
var _gait := 0
var _limit := TRAVEL_LIMIT
var _drinker: Node
var reason := ""   # why it failed, for tests/debug


## The fountain nearest `at` with water in it, or null.
static func fountain_near(tree: SceneTree, at: Vector3) -> Node3D:
	var best: Node3D = null
	for node: Node in tree.get_nodes_in_group(FOUNTAIN.GROUP) if tree != null else []:
		var water := node as Node3D
		if water == null or not water.is_inside_tree(): continue
		if best == null or water.global_position.distance_squared_to(at) < best.global_position.distance_squared_to(at): best = water
	return best


func start(ctx: Dictionary) -> bool:
	if not is_instance_valid(ctx.get("actor")) or not is_instance_valid(ctx.get("nav")): reason = "No body"; return false
	if _interrupted(ctx): reason = "Busy"; return false
	_fountain = fountain_near(ctx.tree, ctx.actor.global_position)
	if _fountain == null: reason = "No fountain here"; return false
	if bool(_fountain.call("iced")): reason = "The fountain is iced over"; return false
	if not _take_spot(ctx): reason = "No free spot at the fountain"; return false
	# Her own size against the rim's height over the ground she will stand on (the fountain node's
	# height over the terrain can change with a town rebuild).
	var rim_height: float = _fountain.to_global(Vector3(0.0, DRINK_POSE.RIM_TOP_Y, 0.0)).y - float(_spot.approach.y)
	if ctx.actor.get("skeleton") != null and not DRINK_POSE.fits(ctx.actor, rim_height):
		_let_go(ctx); reason = "Too small to reach the water"; return false
	claim(ctx)
	if str(ctx.nav.command_owner) != "day:" + str(ctx.id):
		_let_go(ctx); reason = "Navigator refused"; return false
	ctx.actor.set_meta("life_intent", "Going for a drink at the fountain")
	_navigate(ctx)
	return true


## The free spot nearest her whose standing point is on the walk grid.
func _take_spot(ctx: Dictionary) -> bool:
	var spots: Array = _fountain.call("drink_spots")
	var here: Vector3 = ctx.actor.global_position
	var order: Array = range(spots.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return here.distance_squared_to(spots[a].approach) < here.distance_squared_to(spots[b].approach))
	for index: int in order:
		if not bool(_fountain.call("spot_free", index)): continue
		var spot: Dictionary = (spots[index] as Dictionary).duplicate()
		var stand: Vector3 = spot.approach
		# A bigger pony's walk grid keeps a wider margin (her radius grows with her size, play test
		# 2026-11-16): her spot lies that much further out; the drinker steps her in.
		var centre: Vector3 = spot.centre
		var radius := float(ctx.actor.profile.radius) if ctx.actor.get("profile") != null else 0.45
		var out := Vector3(stand.x - centre.x, 0.0, stand.z - centre.z).normalized()
		stand += out * maxf(0.0, radius - 0.45)
		var walkable: Vector3 = ctx.nav.command_support(stand) if ctx.nav.has_method("command_support") else stand
		if not walkable.is_finite() or Vector2(walkable.x - stand.x, walkable.z - stand.z).length() > SNAP or absf(walkable.y - stand.y) > 0.6: continue
		# Never nearer the basin than measured: the grid cell may lie inside the wall's margin.
		if Vector2(walkable.x - centre.x, walkable.z - centre.z).length() < FOUNTAIN.STAND_R + maxf(0.0, radius - 0.45) - 0.15: continue
		if not bool(_fountain.call("take_spot", index, str(ctx.id), self)): continue
		spot.approach = walkable
		_spot = spot
		_index = index
		return true
	return false


func _navigate(ctx: Dictionary) -> void:
	_point = _spot.approach
	_phase = "travel"
	_phase_seconds = 0.0
	ctx.nav.face_point = Vector3.INF
	var far := Vector2(ctx.actor.global_position.x - _point.x, ctx.actor.global_position.z - _point.z).length()
	_gait = ctx.nav.Gait.TROT if far > 40.0 else ctx.nav.Gait.WALK
	_limit = maxf(TRAVEL_LIMIT, far / 0.3 + 60.0)
	ctx.nav.go_to(_point, _gait)


func tick(ctx: Dictionary, delta: float) -> String:
	seconds += delta
	_phase_seconds += delta
	if not is_instance_valid(_fountain) or not _owns(ctx): reason = "Lost her"; return "failed"
	if _interrupted(ctx): reason = "Interrupted"; return "failed"
	var nav: Node = ctx.nav
	match _phase:
		"travel":
			if _phase_seconds > _limit: reason = "Could not reach the fountain"; return "failed"
			var gap := Vector2(ctx.actor.global_position.x - _point.x, ctx.actor.global_position.z - _point.z).length()
			if gap <= ARRIVAL and (nav.state == nav.State.ARRIVED or not nav._has_target):
				# The walk grid keeps her 0.45 m off the wall; the drinker takes the last step closer.
				nav.stay()
				nav.face_point = _spot.centre
				_phase = "align"; _phase_seconds = 0.0
				return "running"
			if nav.state in [nav.State.UNREACHABLE, nav.State.BLOCKED] or (not nav._has_target and _phase_seconds > 1.0):
				_tries += 1
				if _tries > 2: reason = "Could not reach the fountain"; return "failed"
				nav.go_to(_point, _gait)
		"align":
			if _phase_seconds > ALIGN_LIMIT: reason = "Could not turn to the water"; return "failed"
			if not _aligned(ctx): return "running"
			# From here the drinker turns and steps her itself (the navigator would keep turning her).
			nav.face_point = Vector3.INF
			if ctx.actor.has_method("face_direction"): ctx.actor.face_direction(Vector3.ZERO)
			_begin_drink(ctx)
			_phase = "drink"; _phase_seconds = 0.0
			ctx.actor.set_meta("life_intent", "Having a drink at the fountain")
		"drink":
			if is_instance_valid(_drinker) and not _counted and str(_drinker.get("stage")) in ["raise", "down", "away", "off"]:
				_counted = true
				(load("res://world/life/day/actions/fountain_visit.gd") as GDScript).call("mark_drank", ctx.tree, ctx.actor, str(ctx.id))
			if is_instance_valid(_drinker):
				if not str(_drinker.outcome).is_empty():
					reason = str(_drinker.reason)
					if str(_drinker.outcome) == "done" and not _counted: (load("res://world/life/day/actions/fountain_visit.gd") as GDScript).call("mark_drank", ctx.tree, ctx.actor, str(ctx.id))
					return "done" if str(_drinker.outcome) == "done" else "failed"
				if _phase_seconds > DRINK_LIMIT: reason = "The drink took too long"; return "failed"
				return "running"
			if _drinker != null:
				# Freed without telling (cleanup on exit): over.
				reason = "Drink ended"; return "failed"
			_look_down(ctx)
			if _phase_seconds < SETTLE_SECONDS * 2.0 + SIPS * SIP_SECONDS: return "running"
			(load("res://world/life/day/actions/fountain_visit.gd") as GDScript).call("mark_drank", ctx.tree, ctx.actor, str(ctx.id))
			return "done"
	return "running"


func _aligned(ctx: Dictionary) -> bool:
	if float(ctx.actor.get("actual_speed")) > 0.08: return false
	var toward: Vector3 = _spot.centre - ctx.actor.global_position
	toward.y = 0.0
	if toward.length_squared() < 0.01: return true
	var forward: Vector3 = -ctx.actor.global_basis.z
	forward.y = 0.0
	return forward.normalized().dot(toward.normalized()) >= 0.9


## The drink itself, frame by frame (fountain_drinker.gd); a rig it cannot pose looks down instead.
func _begin_drink(ctx: Dictionary) -> void:
	var drinker: Node = DRINKER.new()
	drinker.name = "FountainDrink"
	if not bool(drinker.call("begin", ctx.actor, _fountain, "day:" + str(ctx.id))):
		drinker.free()
		return
	ctx.actor.add_child(drinker)
	_drinker = drinker


## A rig without the drinking pose: a look down toward the water (as tend.gd looks at a garden).
func _look_down(ctx: Dictionary) -> void:
	var secondary: RefCounted = ctx.actor.get("secondary")
	if secondary != null: secondary.look_toward(Vector3(-0.5, 0.0, 0.0), 0.6)


func _owns(ctx: Dictionary) -> bool:
	return is_instance_valid(ctx.get("nav")) and str(ctx.nav.command_owner) == "day:" + str(ctx.id)


func _interrupted(ctx: Dictionary) -> bool:
	var actor: Node3D = ctx.actor
	if actor.get("sleeping") == true: return true
	if actor.get("_held") == true: return true
	var flight: RefCounted = actor.get("flight")
	if flight != null and flight.active() and _phase != "travel": return true
	if actor.get_meta("active_follow", false) or actor.get_meta("seating", false): return true
	return actor.has_method("action_interruption_reason") and not str(actor.action_interruption_reason()).is_empty()


func _let_go(_ctx: Dictionary) -> void:
	# Cut short at any phase: the drinker eases her pose and eyes back and frees itself; finished, it
	# has let go of everything already.
	if is_instance_valid(_drinker):
		if str(_drinker.outcome).is_empty(): _drinker.call("abort")
		else: _drinker.queue_free()
	_drinker = null
	if is_instance_valid(_fountain) and _index >= 0: _fountain.call("release_spot", _index, self)
	_index = -1


func stop(ctx: Dictionary) -> void:
	_let_go(ctx)
	super.stop(ctx)


func release(ctx: Dictionary) -> void:
	_let_go(ctx)
	super.release(ctx)
