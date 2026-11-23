extends "res://world/life/day/day_action.gd"
## The Cutie Mark Crusaders' meet-up (play test 2026-11-16: "the CMC clubhouse should be a location
## for the CMC to be able to group up and meet at after school or whenever, before going off and doing
## other stuff together, as if they're running off in a group to go crusading."). A routine step
## (world/life/day/tables/routines.json "crusade_after_school" / "crusade_free_day") that Apple Bloom,
## Sweetie Belle and Scootaloo each have on the same day: each trots to the clubhouse and waits outside
## it for the others (step.members); once all are there, or after WAIT_MINUTES with at least two, they
## run off together to the day's crusading place (step.goal, the same for all: day_planner picks it per
## day), the first of them leading and the others at her flanks, and spend the rest of the routine there
## together until step.end, before going their own ways. One who comes late, after the others left,
## follows them there. Alone at the time-out she gives up (failed: no "finished" memory of a crusade
## that never happened). The meet-up is shared through a static table keyed by the step and day, the
## same way the fountain shares its spots; meeting points come from the buildings' own bounds and her
## walk grid (gather_points.gd), never a map position.
## Play test 2026-11-17: they go anywhere in Ponyville (routines.json lists the town's places; one not
## loaded is passed over for the next), at a full sprint (pony_navigator.gd `sprint`) to the clubhouse
## and on the outing; and one the player stops to talk to is waited for: the others hold where they are
## for up to AWAY_SECONDS of real time (at the clubhouse, on the way or at the place) and she sprints back to them
## after the chat, wherever they are by then. Longer than that, they carry on without her.

const GATHER := preload("res://world/life/day/gather_points.gd")
const WAIT_MINUTES := 40.0
const TRAVEL_LIMIT := 150.0
const ARRIVAL := 0.8
const CIRCLE := 1.3
const FLANK_BACK := 1.4
const FLANK_SIDE := 1.1
## Real seconds, not game minutes: a chat runs at the player's pace (10 game minutes were 14 s of real time).
const AWAY_SECONDS := 180.0
## "<action>:<day>" -> {"centre", "here": {id: true}, "go": bool, "leader", "walking": {id: true},
## "dest": Vector3, "left_at": msec}.
static var _meets: Dictionary = {}
var _meet: Dictionary = {}
var _point := Vector3.INF
var _face := Vector3.INF
var _phase := "travel"
var _phase_seconds := 0.0
var _tries := 0
var _limit := TRAVEL_LIMIT
var _follow_timer := 0.0
var reason := ""   # why it failed, for tests/debug
## The last failure reason by pony (labs and the playtest bridge read it after the step is gone).
static var failures: Dictionary = {}


static func meet_for(action: String, day: int) -> Dictionary:
	var key := "%s:%d" % [action, day]
	if not _meets.has(key): _meets[key] = {"centre": Vector3.INF, "here": {}, "go": false, "leader": "", "walking": {}, "dest": Vector3.INF,
		"away": {}, "label": ""}
	return _meets[key]


## Where an unloaded Crusader's essence waits (day_runner._essence_run): beside the clubhouse, not in it.
static func essence_point(tree: SceneTree, step: Dictionary) -> Vector3:
	var club: Node3D = PLACES.find(tree, str(step.get("target", ""))).get("node") as Node3D
	if club == null or not club.is_inside_tree(): return Vector3.INF
	var ring: Array = GATHER.ring(null, club, 2.0, 16)
	return ring[0] if not ring.is_empty() else Vector3.INF


func _members(ctx: Dictionary) -> Array:
	var members: Array = ctx.step.get("members", []) if ctx.step.get("members") is Array else []
	return members if not members.is_empty() else [str(ctx.id)]


func _others(ctx: Dictionary, among: Array) -> String:
	var names: PackedStringArray = []
	for id: Variant in among:
		if str(id) != str(ctx.id): names.append(str(id).replace("_", " ").capitalize())
	return " and ".join(names) if not names.is_empty() else "her friends"


## What they try for today (2026-11-18 play test: they talked of a corn-eating cutie mark at the market and ran off
## to the windmill): the day's idea for the place (routines.json "ideas", day_planner step.idea), so the talk, the
## plan and the place agree.
func _idea(ctx: Dictionary) -> String:
	if not str(_meet.get("idea", "")).is_empty(): return str(_meet.idea)
	return str(ctx.step.get("idea", ""))


## As they set off from the clubhouse with Anon near enough to hear: a quick talk about today's plan, the place and
## the idea, so what they say is what they then do (director_group.gd request_scene). Once per meet-up.
func _plan_talk(ctx: Dictionary) -> void:
	if bool(_meet.get("planned", false)): return
	_meet.planned = true
	var scene: Node = ctx.tree.current_scene if ctx.get("tree") != null else null
	var director: Variant = scene.get("director") if scene != null and "director" in scene else null
	var turns: Variant = (director as Object).get("_group_turns") if director is Object and is_instance_valid(director) else null
	if not turns is Object or not (turns as Object).has_method("request_scene"): return
	var here: Array = (_meet.here as Dictionary).keys()
	var idea := _idea(ctx)
	var request := ("The Cutie Mark Crusaders (%s) have met at their clubhouse and are about to run off together to %s%s. Write their quick " +
		"plan now, all at once: whose idea it is, why it is sure to get them their cutie marks this time, and who does what, with the " +
		"usual enthusiasm (their cheer, \"Cutie Mark Crusaders ... yay!\", fits here). They are going to %s and nowhere else: do not suggest any other place or " +
		"plan. About 3 to 6 short lines, every one of them speaking, ending as they set off. Mark each line [to: listener_id]. Anon " +
		"being nearby is not a cue to greet or address him.") % [", ".join(PackedStringArray(here)), _place_label(ctx),
		" to try for their cutie marks in " + idea if idea != "" else "", _place_label(ctx)]
	(turns as Object).call("request_scene", here, request)


func _place_label(ctx: Dictionary) -> String:
	if not str(_meet.get("label", "")).is_empty(): return str(_meet.label)
	return str(ctx.step.get("item", "")) if not str(ctx.step.get("item", "")).is_empty() else "the clubhouse"


## Members the player stopped to talk to, not back yet, for under AWAY_SECONDS: the others wait for them.
func _waited_for(ctx: Dictionary) -> Array:
	var out: Array = []
	var away: Dictionary = _meet.get("away", {})
	for id: Variant in away.keys():
		if str(id) == str(ctx.id): continue
		if float(Time.get_ticks_msec() - int(away[id])) / 1000.0 > AWAY_SECONDS: away.erase(id); continue
		out.append(str(id))
	return out


func _sprint(ctx: Dictionary, on: bool) -> void:
	if is_instance_valid(ctx.get("nav")) and ctx.nav.get("sprint") != null: ctx.nav.sprint = on


func start(ctx: Dictionary) -> bool:
	if not is_instance_valid(ctx.get("actor")) or not is_instance_valid(ctx.get("nav")): reason = "No body"; return false
	var club: Node3D = PLACES.find(ctx.tree, str(ctx.step.target)).get("node") as Node3D
	if club == null or not club.is_inside_tree(): reason = "No clubhouse here"; return false
	_meet = meet_for(str(ctx.step.action), int(ctx.get("day", 0)))
	if not (_meet.centre as Vector3).is_finite():
		var ring: Array = GATHER.ring(ctx.nav, club, 2.0, 16, ctx.actor.global_position)
		if ring.is_empty(): reason = "No ground by the clubhouse"; return false
		_meet.centre = ring[0]
	claim(ctx)
	if str(ctx.nav.command_owner) != "day:" + str(ctx.id): reason = "Navigator refused"; return false
	var was_away: bool = (_meet.away as Dictionary).has(str(ctx.id))
	(_meet.away as Dictionary).erase(str(ctx.id))
	if bool(_meet.go) and (_meet.dest as Vector3).is_finite():
		# The others have already run off: she sprints after them, to wherever they are now (back with her
		# friends after a chat with Anon, or late).
		_head_out(ctx, (_meet.here as Dictionary).has(str(ctx.id)))
		if was_away: ctx.actor.set_meta("life_intent", "Running to catch up with %s after talking to Anon" % _others(ctx, _members(ctx)))
		return true
	var members := _members(ctx)
	var index := maxi(0, members.find(str(ctx.id)))
	var angle := TAU * float(index) / float(maxi(3, members.size()))
	var around: Vector3 = (_meet.centre as Vector3) + Vector3(cos(angle), 0.0, sin(angle)) * CIRCLE
	var ground := GATHER.walkable(ctx.nav, around, 0.5)
	_point = ground if ground.is_finite() else GATHER.grounded(around)   # a cell not sampled yet: still her own place
	_face = _meet.centre
	ctx.actor.set_meta("life_intent", "On her way to the clubhouse to meet the other Crusaders")
	_navigate(ctx, _point)
	return true


func _navigate(ctx: Dictionary, to: Vector3) -> void:
	_phase_seconds = 0.0
	_tries = 0
	ctx.nav.face_point = Vector3.INF
	var far := Vector2(ctx.actor.global_position.x - to.x, ctx.actor.global_position.z - to.z).length()
	_limit = maxf(TRAVEL_LIMIT, far / 0.3 + 60.0)
	# Foals on their way to adventure sprint (the walk is for the last few metres).
	_sprint(ctx, far > 8.0)
	ctx.nav.go_to(to, ctx.nav.Gait.TROT if far > 8.0 else ctx.nav.Gait.WALK)


## Where they go crusading, worked out once for the group: a walkable point beside the place, on the
## side facing the clubhouse. No place (not loaded): they stay and crusade by the clubhouse.
func _destination(ctx: Dictionary) -> Vector3:
	if (_meet.dest as Vector3).is_finite(): return _meet.dest
	var goal := str(ctx.step.get("goal", ""))
	var node: Node3D = PLACES.find(ctx.tree, goal).get("node") as Node3D if not goal.is_empty() else null
	if node == null or not node.is_inside_tree():
		# Today's place is not loaded (or not in this town): the next one on the list that is.
		var places: Array = ctx.step.get("places", []) if ctx.step.get("places") is Array else []
		var from := 0
		for i in places.size():
			if places[i] is Dictionary and str(places[i].get("id", "")) == goal: from = i + 1
		for k in places.size():
			var place: Variant = places[(from + k) % places.size()]
			if not place is Dictionary: continue
			var other: Node3D = PLACES.find(ctx.tree, str(place.get("id", ""))).get("node") as Node3D
			if other != null and other.is_inside_tree() and other.global_position.distance_to(_meet.centre) > 25.0:
				node = other; _meet.label = str(place.get("label", ""))
				var ideas: Variant = place.get("ideas")
				if ideas is Array and not (ideas as Array).is_empty(): _meet.idea = str(ideas[0])
				break
	var dest: Vector3 = _meet.centre
	if node != null and node.is_inside_tree():
		var ring: Array = GATHER.ring(ctx.nav, node, 2.5, 16, _meet.centre)
		if not ring.is_empty(): dest = ring[0]
	_meet.dest = dest
	return dest


## Off to the crusading place: the leader straight there, the others at her flanks (_follow).
func _head_out(ctx: Dictionary, together: bool) -> void:
	var dest := _destination(ctx)
	var members := _members(ctx)
	var index := maxi(0, members.find(str(ctx.id)))
	var angle := TAU * float(index) / float(maxi(3, members.size())) + 0.5
	var spot := dest + Vector3(cos(angle), 0.0, sin(angle)) * CIRCLE
	var own := GATHER.walkable(ctx.nav, spot, 0.5)
	_point = own if own.is_finite() else GATHER.grounded(spot)
	_face = dest
	(_meet.walking as Dictionary)[str(ctx.id)] = true
	_phase = "outing"
	var with := _others(ctx, (_meet.here as Dictionary).keys() if together else members)
	var trying := " to try for their cutie marks in " + _idea(ctx) if _idea(ctx) != "" else ""
	ctx.actor.set_meta("life_intent", "Off crusading with %s, galloping over to %s together%s" % [with, _place_label(ctx), trying] if together
		else "Hurrying after %s to %s to go crusading with them%s" % [with, _place_label(ctx), trying])
	if str(_meet.leader) == str(ctx.id) or not together: _navigate(ctx, _point)
	else: _follow(ctx)


## A follower aims a little behind and to one side of the leader while the leader is under way.
func _follow(ctx: Dictionary) -> void:
	_follow_timer = 1.0
	var leader_id := str(_meet.leader)
	var leader: Node3D = ctx.population.live.get(leader_id, {}).get("actor") if ctx.population != null else null
	var leader_away: bool = leader_id in _waited_for(ctx)
	var leading: bool = is_instance_valid(leader) and ((_meet.walking as Dictionary).has(leader_id) or leader_away) and leader.global_position.distance_to(_meet.dest) > 8.0
	if not leading:
		if ctx.nav.get("_has_target") != true or not ctx.nav.target.is_equal_approx(_point): _navigate(ctx, _point)
		return
	var forward: Vector3 = (_meet.dest as Vector3) - leader.global_position
	forward.y = 0.0
	forward = forward.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	var index := maxi(1, _members(ctx).find(str(ctx.id)))
	var sign := 1.0 if index % 2 == 1 else -1.0
	var at: Vector3 = leader.global_position - forward * FLANK_BACK + side * FLANK_SIDE * sign
	var ground: Vector3 = ctx.nav.command_formation_support(at, leader.global_position) if ctx.nav.has_method("command_formation_support") else at
	if not ground.is_finite(): ground = leader.global_position - forward * (FLANK_BACK * 1.6)
	var far: float = ctx.actor.global_position.distance_to(ground)
	_sprint(ctx, far > 2.5 and not leader_away)
	ctx.nav.go_to(ground, ctx.nav.Gait.TROT if far > 2.5 else ctx.nav.Gait.WALK)


func _over(ctx: Dictionary) -> bool:
	if ctx.step.has("end") and is_instance_valid(ctx.get("runner")) and ctx.runner.has_method("_card_hours"):
		return float(ctx.runner.call("_card_hours")) >= float(ctx.step.end)
	return seconds >= duration(float(ctx.step.get("minutes", 60.0)))


func _at(ctx: Dictionary, point: Vector3) -> bool:
	var nav: Node = ctx.nav
	var gap := Vector2(ctx.actor.global_position.x - point.x, ctx.actor.global_position.z - point.z).length()
	return gap <= ARRIVAL and (nav.state == nav.State.ARRIVED or not nav._has_target)


func _retry(ctx: Dictionary) -> bool:
	var nav: Node = ctx.nav
	if nav.state in [nav.State.UNREACHABLE, nav.State.BLOCKED] or (not nav._has_target and _phase_seconds > 1.0):
		_tries += 1
		if _tries > 3: return false
		nav.go_to(_point, nav.Gait.WALK)
	return true


func tick(ctx: Dictionary, delta: float) -> String:
	var result := _tick(ctx, delta)
	if result == "failed": failures[str(ctx.id)] = "%s (%s)" % [reason, _phase]
	return result


func _tick(ctx: Dictionary, delta: float) -> String:
	seconds += delta
	_phase_seconds += delta
	if str(ctx.nav.command_owner) != "day:" + str(ctx.id): reason = "Lost her"; return "failed"
	var nav: Node = ctx.nav
	if _over(ctx):
		reason = "The afternoon ran out"
		return "done" if _phase == "crusading" else "failed"
	match _phase:
		"travel":
			if bool(_meet.go) and not (_meet.here as Dictionary).has(str(ctx.id)):
				_head_out(ctx, false)   # late: they left without her
				return "running"
			if _phase_seconds > _limit: reason = "Could not reach the clubhouse"; return "failed"
			if _at(ctx, _point):
				_sprint(ctx, false)
				nav.stay()
				nav.face_point = _face
				(_meet.here as Dictionary)[str(ctx.id)] = true
				_phase = "wait"; _phase_seconds = 0.0
				ctx.actor.set_meta("life_intent", "Meeting the other Crusaders at the clubhouse, waiting for %s" % _others(ctx, _members(ctx)))
				return "running"
			if not _retry(ctx):
				# Her own place by the clubhouse may be off her grid: try the meeting point itself once.
				if _point.is_equal_approx(_meet.centre): reason = "Could not reach the clubhouse"; return "failed"
				_point = _meet.centre
				_navigate(ctx, _point)
		"wait":
			nav.face_point = _face
			var here: Dictionary = _meet.here
			if not bool(_meet.go):
				if not _waited_for(ctx).is_empty(): _phase_seconds = minf(_phase_seconds, duration(WAIT_MINUTES) * 0.5)   # one of them is talking to Anon: wait up for her
				var all := _members(ctx).all(func(m): return here.has(str(m)))
				if all or (_phase_seconds > duration(WAIT_MINUTES) and here.size() >= 2):
					_meet.go = true
					for m: Variant in _members(ctx):
						if here.has(str(m)): _meet.leader = str(m); break
					_plan_talk(ctx)
				elif _phase_seconds > duration(WAIT_MINUTES) * 1.5:
					reason = "Nopony else came"; return "failed"
			if bool(_meet.go): _head_out(ctx, true)
		"outing":
			var waiting := _waited_for(ctx)
			if str(_meet.leader) == str(ctx.id) and not waiting.is_empty() and ctx.actor.global_position.distance_to(_point) > 8.0:
				# One of them stopped to talk to Anon: the leader holds where she is till she catches up.
				if nav.get("_has_target") == true: _sprint(ctx, false); nav.stay()
				ctx.actor.set_meta("life_intent", "Waiting for %s, who stopped to talk to Anon, before running on to %s" % [
					" and ".join(waiting.map(func(w): return str(w).replace("_", " ").capitalize())), _place_label(ctx)])
				_phase_seconds = 0.0
				return "running"
			if str(_meet.leader) == str(ctx.id) and nav.get("_has_target") != true and ctx.actor.global_position.distance_to(_point) > ARRIVAL * 2.0:
				_head_out(ctx, true)   # she is back: on again together
			if _phase_seconds > _limit: reason = "Could not reach the crusading place"; return "failed"
			if str(_meet.leader) != str(ctx.id) and (_meet.here as Dictionary).has(str(ctx.id)):
				_follow_timer -= delta
				if _follow_timer <= 0.0: _follow(ctx)
			if _at(ctx, _point):
				_sprint(ctx, false)
				nav.stay()
				nav.face_point = _face
				(_meet.walking as Dictionary).erase(str(ctx.id))
				_phase = "crusading"; _phase_seconds = 0.0
				ctx.actor.set_meta("life_intent", "Off crusading with %s at %s, trying for their cutie marks%s" % [_others(ctx, _members(ctx)), _place_label(ctx),
					" in " + _idea(ctx) if _idea(ctx) != "" else ""])
				return "running"
			# A follower's flank point moves with the leader and may be briefly off her grid: only the
			# leader, or a pony making her own way, counts failed tries (all have the time limit).
			var following: bool = str(_meet.leader) != str(ctx.id) and (_meet.here as Dictionary).has(str(ctx.id)) and not ctx.nav.target.is_equal_approx(_point)
			if not following and not _retry(ctx):
				reason = "Could not reach the crusading place"; return "failed"
		"crusading":
			nav.face_point = _face
	return "running"


## Stopped part-way (the player spoke to her, or something else took her): the others wait for her a while
## (away), and the runner starts her step again after the chat while its hour lasts.
func stop(ctx: Dictionary) -> void:
	_sprint(ctx, false)
	if not _meet.is_empty():
		(_meet.walking as Dictionary).erase(str(ctx.id))
		if not bool(_meet.go): (_meet.here as Dictionary).erase(str(ctx.id))
		if _phase != "crusading": (_meet.away as Dictionary)[str(ctx.id)] = Time.get_ticks_msec()
	super.stop(ctx)


func release(ctx: Dictionary) -> void:
	_sprint(ctx, false)
	if not _meet.is_empty(): (_meet.walking as Dictionary).erase(str(ctx.id)); (_meet.away as Dictionary).erase(str(ctx.id))
	super.release(ctx)
