extends "res://world/life/day/day_action.gd"
## Cherry Berry takes Ponyville's hot-air balloon up (play test 2026-11-16: "Cherry Berry should be
## able to get in the hot air balloon and go flying around town on her own. (She's known for being
## the balloon's care taker, and despite being an earth pony, she loves to fly ...)"). A day-card
## step only she gets (day_tables.json "balloon_flight", fair afternoons): she walks to the balloon,
## looks it over at its side, walks round to the ramp and climbs in; from there the balloon's own
## pilot (world/vehicles/balloon/pony_pilot.gd) flies a slow loop over Ponyville and its outskirts,
## brings it home and lands it on its pad, and she climbs out and goes on with her day.
## Refused (the runner drops the step) without the balloon on its pad, while Anon is flying it, in
## foul weather, or too near her bedtime for a whole flight. Her current activity line follows each
## stage, so the dialogue AI knows she is about to fly, is flying (and over what) or has just landed;
## the finished flight goes into the story journal with the places she flew over.
## Any other owner of her navigator ends the step: on the ground at once; from the basket she still
## brings the balloon home and lands first (pony_pilot.gd keeps her aboard until then).

const PILOT := preload("res://world/vehicles/balloon/pony_pilot.gd")
const NIGHT_REST := preload("res://world/life/night_rest.gd")
## Real seconds of cruising: the step's minutes as day time, within these bounds.
const CRUISE_MIN := 150.0
const CRUISE_MAX := 600.0
## Take-off, climb, descent and climbing out, in real seconds (for the bedtime margin).
const OVERHEAD := 120.0
## She is home this many game hours before her bedtime.
const BED_MARGIN := 1.0
const CHECK_SECONDS := 5.0
const TRAVEL_LIMIT := 120.0
var _ship: CharacterBody3D
var _pilot: Node
var _phase := "travel"
var _phase_seconds := 0.0
var _point := Vector3.INF
var _tries := 0
var _limit := TRAVEL_LIMIT
var _cruise := CRUISE_MIN
var _home_by := 99.0
var reason := ""   # why it failed, for tests/debug
## A ride Anon asked for ([use: balloon_ride], play test 2026-11-17: "give Cherry the ability to
## give rides when asked"): injected by request_ride at any daylight hour in fair weather; she waits
## at the helm for him (pony_pilot.gd ride) and the flight is his.
var _ride := false
## Fetching the balloon home from where Anon left it (step "fetch", balloon_fetch.gd): she walks to it, climbs in
## and flies it straight back to its pad.
var _fetch := false
## Ponies who fly the balloon and give rides.
const RIDE_PILOTS := ["cherry_berry"]


## The balloon (game.balloon), or null.
static func balloon(tree: SceneTree) -> CharacterBody3D:
	if tree == null: return null
	for node: Node in tree.get_nodes_in_group("hot_air_balloons"):
		if node is CharacterBody3D and node.is_inside_tree() and "autopilot" in node: return node as CharacterBody3D
	return null


func start(ctx: Dictionary) -> bool:
	if not is_instance_valid(ctx.get("actor")) or not is_instance_valid(ctx.get("nav")): reason = "No body"; return false
	_ship = balloon(ctx.tree)
	if _ship == null: reason = "No balloon"; return false
	_ride = bool(ctx.step.get("ride", false))
	_fetch = bool(ctx.step.get("fetch", false))
	_pilot = PILOT.of(_ship)
	_pilot.set("fetching", _fetch)
	reason = _pilot.refusal()
	if not reason.is_empty(): _pilot.set("fetching", false)
	if not reason.is_empty(): return false
	if not PILOT.fair_weather(ctx.tree): reason = "Not flying weather"; return false
	# Home well before bed: the whole flight must fit before BED_MARGIN hours ahead of bedtime.
	var hours := _card_hours()
	var times: Vector2 = NIGHT_REST.bedtime(str(ctx.id), int(ctx.get("day", 0)))
	var bed := times.x + (24.0 if times.x < 12.0 else 0.0)
	_home_by = bed - BED_MARGIN
	var per_hour := duration(60.0)
	_cruise = clampf(duration(float(ctx.step.get("minutes", 60.0))), CRUISE_MIN, CRUISE_MAX)
	var spare := (_home_by - hours) * per_hour - OVERHEAD - 60.0
	if spare < CRUISE_MIN: reason = "Too near bedtime for a flight"; return false
	_cruise = minf(_cruise, spare)
	claim(ctx)
	if str(ctx.nav.command_owner) != "day:" + str(ctx.id): reason = "Navigator refused"; return false
	ctx.actor.set_meta("life_intent", "Going to fetch Ponyville's hot-air balloon from where Anon left it and fly it back to its pad (you look after the balloon)" if _fetch
		else "Heading to Ponyville's hot-air balloon to give Anon the ride he asked for: he climbs into the basket after you, and you fly him over Ponyville" if _ride
		else "Heading to Ponyville's hot-air balloon to take it up for a flight over the town (you look after the balloon)")
	# First a look over it from its side, then round to the ramp.
	_go(ctx, _walkable(ctx, _ship.to_global(Vector3(2.9, 0.0, 0.3))), "travel")
	return true


func _card_hours() -> float:
	var clock: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("TimeOfDay")
	if clock == null: return 12.0
	var h := float(clock.hours)
	return h + 24.0 if h < 5.0 else h


## A point on her walk grid near `at`, or the ramp foot when there is none.
func _walkable(ctx: Dictionary, at: Vector3) -> Vector3:
	var found: Vector3 = ctx.nav.command_support(at) if ctx.nav.has_method("command_support") else at
	if found.is_finite() and Vector2(found.x - at.x, found.z - at.z).length() < 2.0: return found
	return _ship._ramp_foot()


func _go(ctx: Dictionary, point: Vector3, phase: String) -> void:
	_point = point
	_phase = phase
	_phase_seconds = 0.0
	_tries = 0
	ctx.nav.face_point = Vector3.INF
	var far := Vector2(ctx.actor.global_position.x - point.x, ctx.actor.global_position.z - point.z).length()
	_limit = maxf(TRAVEL_LIMIT, far / 0.3 + 60.0)
	ctx.nav.go_to(point, ctx.nav.Gait.TROT if far > 40.0 else ctx.nav.Gait.WALK)


func tick(ctx: Dictionary, delta: float) -> String:
	seconds += delta
	_phase_seconds += delta
	if not is_instance_valid(_ship) or _pilot == null: reason = "Lost the balloon"; return "failed"
	if _phase == "aboard": return _aboard(ctx)
	if not _owns(ctx): reason = "Lost her"; return "failed"
	if ctx.actor.get("_held") == true or ctx.actor.get("sleeping") == true: reason = "Interrupted"; return "failed"
	var nav: Node = ctx.nav
	match _phase:
		"travel", "ramp":
			if _phase_seconds > _limit: reason = "Could not reach the balloon"; return "failed"
			var gap := Vector2(ctx.actor.global_position.x - _point.x, ctx.actor.global_position.z - _point.z).length()
			var close := gap < (1.2 if _phase == "travel" else 0.8)
			# The walk grid may not reach the very ramp foot: near enough and stuck, she hops the rest.
			if close and (nav.state == nav.State.ARRIVED or not nav._has_target) or (_phase == "ramp" and gap < 3.0 and _phase_seconds > 8.0 and not nav._has_target):
				nav.stay()
				if _phase == "travel":
					nav.face_point = _ship.to_global(Vector3(0.0, 1.0, 0.0))
					_phase = "check"; _phase_seconds = 0.0
					ctx.actor.set_meta("life_intent", "Checking over Ponyville's hot-air balloon (basket, ropes and burner) before taking it up for a flight")
				else:
					return _board(ctx)
				return "running"
			if nav.state in [nav.State.UNREACHABLE, nav.State.BLOCKED] or (not nav._has_target and _phase_seconds > 1.0):
				_tries += 1
				if _tries > 2:
					if _phase == "travel": _go(ctx, _walkable(ctx, _ship._ramp_foot()), "ramp"); return "running"
					reason = "Could not reach the balloon"; return "failed"
				nav.go_to(_point, nav.Gait.WALK)
		"check":
			if _phase_seconds < CHECK_SECONDS: return "running"
			nav.face_point = Vector3.INF
			_go(ctx, _walkable(ctx, _ship._ramp_foot()), "ramp")
	return "running"


func _board(ctx: Dictionary) -> String:
	reason = _pilot.refusal()
	if not reason.is_empty(): return "failed"
	if not PILOT.fair_weather(ctx.tree): reason = "Not flying weather"; return "failed"
	var seed_value := hash("balloon:%s:%d" % [str(ctx.id), int(ctx.get("day", 0))])
	if not _pilot.begin(ctx.actor, str(ctx.id), _cruise, _home_by, seed_value): reason = "Could not board"; return "failed"
	_pilot.set("ride", _ride)
	_phase = "aboard"; _phase_seconds = 0.0
	ctx.actor.set_meta("life_intent", _pilot.status_text())
	return "running"


func _aboard(ctx: Dictionary) -> String:
	if _pilot.get("actor") != ctx.actor: reason = "Lost the balloon"; return "failed"
	if bool(_pilot.get("lost")):
		reason = "Taken out of the basket"
		return "failed"
	var text: String = _pilot.status_text()
	if not text.is_empty() and is_instance_valid(ctx.actor): ctx.actor.set_meta("life_intent", text)
	# The cruise is over (its time used up, with margin for turns): home. A fetch goes home at once.
	if _pilot.call("away") and (_fetch or _phase_seconds > _cruise + 240.0): _pilot.cut_short("bringing it back to its pad" if _fetch else "the flight has run long")
	if _pilot.call("active"): return "running"
	_pilot.set("fetching", false)
	_remember(ctx)
	return "made"


## The flight for the story journal: where she flew, whether Anon rode along, why it ended early.
func _remember(ctx: Dictionary) -> void:
	var places: String = _pilot.call("_places_text")
	var who := str(ctx.id).replace("_", " ").capitalize()
	var text := "%s took Ponyville's hot-air balloon up for a flight over %s and landed it back on its pad" % [who, places]
	if _ride and not bool(_pilot.get("player_rode")):
		text = "%s waited at Ponyville's hot-air balloon to give Anon the ride he asked for, but he never climbed aboard" % who
	if bool(_pilot.get("player_rode")): text += ", with Anon riding along in the basket"
	var cut := str(_pilot.get("cut_reason"))
	if not cut.is_empty(): text += " (she came down early: %s)" % cut
	text += "."
	if is_instance_valid(ctx.actor): ctx.actor.set_meta("life_intent", "Just landed the hot-air balloon on its pad after %s over %s" % ["giving Anon a ride" if bool(_pilot.get("player_rode")) else "a flight", places])
	var runner: Node = ctx.get("runner")
	var context: Node = runner.get_parent().get("world_context") if is_instance_valid(runner) and runner.get_parent() != null else null
	if context == null: return
	var witnesses: Array = [str(ctx.id)]
	for other: String in ctx.population.live:
		var body: Node3D = ctx.population.live[other].get("actor")
		if other != str(ctx.id) and is_instance_valid(body) and body.is_inside_tree() and body.global_position.distance_squared_to(ctx.actor.global_position) < 225.0:
			witnesses.append(other)
	context.record("day", text, witnesses, [str(ctx.id)])


func _owns(ctx: Dictionary) -> bool:
	return is_instance_valid(ctx.get("nav")) and str(ctx.nav.command_owner) == "day:" + str(ctx.id)


## Cut short (bedtime, a command, Anon picking her up): on the ground she just stops; in the basket
## the balloon still brings her home and lands first.
func stop(ctx: Dictionary) -> void:
	if _phase == "aboard" and _pilot != null and _pilot.get("actor") == ctx.get("actor"):
		_pilot.cut_short("something else came up")
	super.stop(ctx)


## Why she cannot give Anon a balloon ride now, or "" (mechanics.gd offers [use: balloon_ride] only
## when ""; otherwise she is told why, to say no kindly): the balloon resting on its pad and free,
## fair weather, daylight, a whole flight before her bedtime, and her free to head off.
static func ride_refusal(tree: SceneTree, id: String) -> String:
	if id not in RIDE_PILOTS: return "you do not fly the balloon"
	var ship := balloon(tree)
	if ship == null: return "the balloon is not here"
	var why: String = PILOT.of(ship).refusal()
	if not why.is_empty(): return why.to_lower()
	if not PILOT.fair_weather(tree): return "it is not balloon weather"
	var clock: Node = tree.root.get_node_or_null("TimeOfDay")
	var runner: Node = tree.get_first_node_in_group("day_runner")
	if clock == null or runner == null: return "you cannot head off right now"
	var hours := float(clock.hours)
	if hours < 5.0: hours += 24.0
	if (clock.has_method("daylight") and float(clock.daylight()) < 0.35) or hours < 7.0: return "it is too dark to fly"
	var times: Vector2 = NIGHT_REST.bedtime(id, int(runner.call("_day_key")))
	var bed := times.x + (24.0 if times.x < 12.0 else 0.0)
	var per_hour := maxf(60.0, float(clock.get("day_length_minutes")) * 60.0 / 24.0) if clock.get("day_length_minutes") != null else 150.0
	if hours + (CRUISE_MIN + OVERHEAD + 60.0) / per_hour > bed - BED_MARGIN: return "it is too close to your bedtime for a flight"
	if not bool(runner.call("can_inject", id)): return "you cannot head off right now"
	return ""


## [use: balloon_ride]: the ride as a fixed step now (day_runner.inject_now). {"status", "reason"}.
static func request_ride(tree: SceneTree, id: String) -> Dictionary:
	var why := ride_refusal(tree, id)
	if not why.is_empty(): return {"status": "failed", "reason": "No balloon ride now: " + why}
	var runner: Node = tree.get_first_node_in_group("day_runner")
	var step := {"action": "balloon_ride", "handler": "fly_balloon", "target": "landmark:airballoon_01", "phrase": "give Anon a ride in Ponyville's hot-air balloon",
		"reason": "because he asked", "item": "", "posture": "stand", "minutes": 60.0, "hours": 2.0, "ride": true, "ai": true}
	if not bool(runner.call("inject_now", id, step)): return {"status": "failed", "reason": "No balloon ride now: you cannot head off right now"}
	return {"status": "accepted", "reason": "Walking to the hot-air balloon; Anon climbs into the basket after you and you fly him over Ponyville"}
