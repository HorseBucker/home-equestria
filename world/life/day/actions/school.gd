extends "res://world/life/day/day_action.gd"
## School (play test 2026-11-16: "Add the ponyville schoolhouse as a place for foals and Cheerilee to
## need to go to in the morning. Around 8am ... The school isn't enterable, but they can hang around
## outside, in the fenced area around the playground or the benches, so they aren't blocking the
## street."). A routine step (world/life/day/tables/routines.json "school_pupil" / "school_teach",
## school days only: day_planner.school_day). Cheerilee stands in the schoolyard beside the building,
## facing her class; the foals sit in loose rows in front of her, facing her, until school lets out
## (step.end). Nothing here knows a map position: the yard is laid out at run time from the
## schoolhouse's own mesh bounds, on the side of the building with the tetherball and away from its
## door (the road), each point checked against her walk grid and kept clear of the yard's props.
## Refused (the runner drops the step) with no schoolhouse loaded or no free place in the yard.

const GATHER := preload("res://world/life/day/gather_points.gd")
## The yard's furniture, kept clear of (scenery node names; the first one found picks the yard side).
const YARD_PROPS := ["teatherpoll_01", "teatherball_01", "picnictable_01", "picnictable_02"]
const PROP_CLEAR := 2.4
## Cheerilee stands this far out from the wall; the first row sits FIRST_ROW in front of her, the
## next ones ROW_STEP behind, SEAT_GAP apart, each row offset half a gap from the one before.
const WALL_CLEAR := 2.2
const FIRST_ROW := 3.0
const ROW_STEP := 1.5
const SEAT_GAP := 1.5
const ROWS := [5, 4, 5, 4]
## She paces a step to one side and back while she teaches, every so often (real seconds).
const PACE_SECONDS := 35.0
const PACE_STEP := 1.0
const TRAVEL_LIMIT := 150.0
const ARRIVAL := 0.6
## Yard layouts by schoolhouse node: {"teacher", "pupils": [Vector3], "class": Vector3}; places taken
## by handler: "<node id>:<slot>" -> weakref(handler) (slot -1 is the teacher's).
static var _layouts: Dictionary = {}
static var _taken: Dictionary = {}
var _school: Node3D
var _slot := -2
var _point := Vector3.INF
var _face := Vector3.INF
var _phase := "travel"
var _phase_seconds := 0.0
var _tries := 0
var _gait := 0
var _limit := TRAVEL_LIMIT
var _pace := 0
var reason := ""   # why it failed, for tests/debug
var nav_for_snap: Node


func _teacher(ctx: Dictionary) -> bool:
	return str(ctx.step.get("role", "")) == "teacher"


func start(ctx: Dictionary) -> bool:
	if not is_instance_valid(ctx.get("actor")) or not is_instance_valid(ctx.get("nav")): reason = "No body"; return false
	var entry: Dictionary = PLACES.find(ctx.tree, str(ctx.step.target))
	_school = entry.get("node") as Node3D
	if _school == null or not _school.is_inside_tree(): reason = "No schoolhouse here"; return false
	var layout := layout_for(_school, ctx.nav)
	if layout.is_empty(): reason = "No room in the schoolyard"; return false
	nav_for_snap = ctx.nav
	if not _take_place(layout, _teacher(ctx)): reason = "No free place in the schoolyard"; return false
	claim(ctx)
	if str(ctx.nav.command_owner) != "day:" + str(ctx.id): _free_place(); reason = "Navigator refused"; return false
	ctx.actor.set_meta("life_intent", "On her way to the schoolhouse to teach her class" if _teacher(ctx) else "On her way to school at the schoolhouse")
	_navigate(ctx, _point)
	return true


## The schoolyard for this schoolhouse, laid out once per node (and again when its room ran out).
static func layout_for(school: Node3D, nav: Node) -> Dictionary:
	var key := school.get_instance_id()
	var cached: Dictionary = _layouts.get(key, {})
	if not cached.is_empty() and (cached.pupils as Array).size() >= 6: return cached
	var made := _lay_out(school, nav)
	if not made.is_empty(): _layouts[key] = made
	return made


static func _lay_out(school: Node3D, nav: Node) -> Dictionary:
	var frame := school.global_transform.orthonormalized()
	var inverse := frame.affine_inverse()
	var box := GATHER.local_bounds(school)
	if box.size == Vector3.ZERO: return {}
	var props: Array = []
	for name: String in YARD_PROPS:
		var prop := GATHER.scenery_node(school, name)
		if prop != null: props.append(prop.global_position)
	# Sides of the building in its own frame: left, right and back. The front (+Z) is where the
	# model's door is, on the road (the schoolhouse door opens onto the street).
	var sides := [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD]   # -Z: the back wall
	var best: Dictionary = {}
	var best_score := -INF
	for out: Vector3 in sides:
		var plan := _side(frame, box, out, props, nav)
		var score := float((plan.pupils as Array).size())
		# The playground side (the tetherball, the first yard prop) wins a tie and a near tie.
		if not props.is_empty():
			var local: Vector3 = inverse * (props[0] as Vector3)
			if Vector3(local.x, 0.0, local.z).normalized().dot(out) > 0.6: score += 2.5
		if plan.teacher.is_finite() and score > best_score:
			best_score = score
			best = plan
	if best.is_empty() or (best.pupils as Array).is_empty(): return {}
	return best


## Cheerilee's place and the pupils' rows on one side (`out`, a unit axis of the building's frame).
static func _side(frame: Transform3D, box: AABB, out: Vector3, props: Array, nav: Node) -> Dictionary:
	var lateral := Vector3(-out.z, 0.0, out.x)
	var centre := box.get_center()
	var reach: float = absf(out.x) * box.size.x * 0.5 + absf(out.z) * box.size.z * 0.5
	# Along a side wall, a step towards the back: further from the road at the front.
	var back := -1.0 if absf(out.x) > 0.5 else 0.0
	var teacher_local := Vector3(centre.x, box.position.y, centre.z + back) + out * (reach + WALL_CLEAR)
	var teacher := _stand(nav, frame * teacher_local)
	var pupils: Array = []
	var row_index := 0
	for count: int in ROWS:
		var depth := FIRST_ROW + ROW_STEP * row_index
		for i in count:
			var across := (float(i) - float(count - 1) * 0.5) * SEAT_GAP
			# A gentle arc: the ends of a row turn in towards her.
			var bow := 0.08 * across * across
			var local := teacher_local + out * (depth - bow) + lateral * across
			var at := _stand(nav, frame * local)
			if not at.is_finite() or _near_any(at, props, PROP_CLEAR) or _near_any(at, pupils, 1.1): continue
			pupils.append(at)
		row_index += 1
	var middle := Vector3.ZERO
	for p: Vector3 in pupils: middle += p
	middle = middle / maxf(1.0, float(pupils.size())) if not pupils.is_empty() else frame * (teacher_local + out * FIRST_ROW)
	return {"teacher": teacher, "pupils": pupils, "class": middle, "lateral": frame.basis * lateral}


## On her walk grid when it knows the point already, else on the terrain: the grid samples new cells a
## while after it is first asked (and an unloaded pony has none), so the yard is laid out from the
## building's geometry and each pony snaps her own place when she sets off (_take_place).
static func _stand(nav: Node, at: Vector3) -> Vector3:
	var ground := GATHER.walkable(nav, at, 0.45)
	return ground if ground.is_finite() else GATHER.grounded(at)


## Where an unloaded pony's essence spends the routine (day_runner._essence_run): the middle of the
## class, laid out from the geometry alone, or INF with no schoolhouse loaded.
static func essence_point(tree: SceneTree, step: Dictionary) -> Vector3:
	var school: Node3D = PLACES.find(tree, str(step.get("target", ""))).get("node") as Node3D
	if school == null or not school.is_inside_tree(): return Vector3.INF
	var layout := layout_for(school, null)
	if layout.is_empty(): return Vector3.INF
	return layout.teacher if str(step.get("role", "")) == "teacher" else layout["class"]


static func _near_any(at: Vector3, points: Array, radius: float) -> bool:
	for p: Vector3 in points:
		if Vector2(p.x - at.x, p.z - at.z).length() < radius: return true
	return false


## The teacher's place, or the free pupil's place nearest the front (rows fill from the front).
func _take_place(layout: Dictionary, teacher: bool) -> bool:
	var key := str(_school.get_instance_id())
	if teacher:
		if not _free(key + ":-1"): return false
		_slot = -1
		_point = layout.teacher
		var snapped := GATHER.walkable(nav_for_snap, _point, 0.6)
		if snapped.is_finite(): _point = snapped
		_face = layout["class"]
	else:
		var pupils: Array = layout.pupils
		for i in pupils.size():
			if not _free(key + ":" + str(i)): continue
			_slot = i
			_point = pupils[i]
			var snapped := GATHER.walkable(nav_for_snap, _point, 0.6)
			if snapped.is_finite(): _point = snapped
			_face = layout.teacher
			break
		if _slot < -1: return false
	_taken[key + ":" + str(_slot)] = weakref(self)
	return true


static func _free(place: String) -> bool:
	var holder: Variant = _taken.get(place)
	return holder == null or not is_instance_valid((holder as WeakRef).get_ref())


func _free_place() -> void:
	if _slot < -1 or not is_instance_valid(_school): _slot = -2; return
	var place := str(_school.get_instance_id()) + ":" + str(_slot)
	var holder: Variant = _taken.get(place)
	if holder != null and (holder as WeakRef).get_ref() == self: _taken.erase(place)
	_slot = -2


func _navigate(ctx: Dictionary, to: Vector3) -> void:
	_phase = "travel"
	_phase_seconds = 0.0
	ctx.nav.face_point = Vector3.INF
	var far := Vector2(ctx.actor.global_position.x - to.x, ctx.actor.global_position.z - to.z).length()
	_gait = ctx.nav.Gait.TROT if far > 40.0 else ctx.nav.Gait.WALK
	_limit = maxf(TRAVEL_LIMIT, far / 0.3 + 60.0)
	ctx.nav.go_to(to, _gait)


## School is out at the routine's end hour (or after its minutes, for a step without one).
func _over(ctx: Dictionary) -> bool:
	if ctx.step.has("end") and is_instance_valid(ctx.get("runner")) and ctx.runner.has_method("_card_hours"):
		return float(ctx.runner.call("_card_hours")) >= float(ctx.step.end)
	return seconds >= duration(float(ctx.step.get("minutes", 60.0)))


func tick(ctx: Dictionary, delta: float) -> String:
	seconds += delta
	_phase_seconds += delta
	if not is_instance_valid(_school) or str(ctx.nav.command_owner) != "day:" + str(ctx.id): reason = "Lost her"; return "failed"
	var nav: Node = ctx.nav
	if _over(ctx):
		ctx.actor.request_posture("stand")
		return "done"
	match _phase:
		"travel", "pace":
			if _phase == "travel" and _phase_seconds > _limit: reason = "Could not reach the schoolyard"; return "failed"
			var gap := Vector2(ctx.actor.global_position.x - _point.x, ctx.actor.global_position.z - _point.z).length()
			if gap <= ARRIVAL and (nav.state == nav.State.ARRIVED or not nav._has_target):
				nav.stay()
				nav.face_point = _face
				if _phase == "travel":
					_phase_seconds = 0.0
					ctx.actor.set_meta("life_intent", "Teaching her class at the schoolhouse" if _teacher(ctx) else "At school at the schoolhouse, being taught by Cheerilee")
					# In class: the director's lessons find the teacher and her seated pupils by this (director_group.gd _lesson).
					ctx.actor.set_meta("school_class", {"role": "teacher" if _teacher(ctx) else "pupil", "school": _school.get_instance_id()})
				_phase = "class"
				return "running"
			if nav.state in [nav.State.UNREACHABLE, nav.State.BLOCKED] or (not nav._has_target and _phase_seconds > 1.0):
				_tries += 1
				if _tries > 3:
					if _phase == "travel": reason = "Could not reach the schoolyard"; return "failed"
					_phase = "class"; _phase_seconds = 0.0   # a pacing step she cannot make: stay put
					return "running"
				nav.go_to(_point, _gait)
		"class":
			nav.face_point = _face
			if not _teacher(ctx):
				if _phase_seconds > 1.5 and ctx.actor.has_method("posture_status") and str(ctx.actor.posture_status().get("kind", "stand")) == "stand":
					ctx.actor.request_posture("sit")
			elif _phase_seconds > PACE_SECONDS:
				# A step to one side of her place and back again, as a teacher does at the board.
				var layout: Dictionary = _layouts.get(_school.get_instance_id(), {})
				var lateral: Vector3 = layout.get("lateral", Vector3.ZERO)
				_pace = (_pace + 1) % 4
				var offsets: Array[float] = [0.0, PACE_STEP, 0.0, -PACE_STEP]
				var offset: float = offsets[_pace]
				var to := GATHER.walkable(nav, (layout.get("teacher", _point) as Vector3) + lateral * offset, 0.45)
				if to.is_finite():
					_point = to
					_phase = "pace"
					_phase_seconds = 0.0
					_tries = 0
					nav.face_point = Vector3.INF
					_gait = nav.Gait.WALK
					nav.go_to(_point, _gait)
				else:
					_phase_seconds = 0.0
	return "running"


func stop(ctx: Dictionary) -> void:
	_free_place()
	if is_instance_valid(ctx.get("actor")) and ctx.actor.has_meta("school_class"): ctx.actor.remove_meta("school_class")
	if is_instance_valid(ctx.get("actor")) and ctx.actor.has_method("request_posture"): ctx.actor.request_posture("stand")
	super.stop(ctx)


func release(ctx: Dictionary) -> void:
	_free_place()
	if is_instance_valid(ctx.get("actor")) and ctx.actor.has_meta("school_class"): ctx.actor.remove_meta("school_class")
	super.release(ctx)
