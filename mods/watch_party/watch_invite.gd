extends RefCounted
## [watch_tv] (part 2): "do you want to watch a movie with me?" The mod's script extensions in ext/
## add the tag (ext/pony_action_schema.gd), offer it while a television is set up and hand its
## movement to step() here each tick (ext/pony_action_executor.gd). Her own model decides whether
## she comes: accepting puts the tag in her reply, declining is just words.
## Phases (movement "watch_phase"):
## - "find": a set near her (TV_NEAR metres, same house)? She goes to sit by it. Otherwise the
##   movement becomes an ordinary follow of Anon (the executor walks it) until one is near.
## - "seat": a free seat facing the set (couch, bench), else a spot on the floor in front of it
##   (an invisible floor seat, world/life/seat.gd), where she lies down; world/life/seating.gd
##   walks her there. A seat or spot she cannot reach is skipped for the next.
## - "watching": settled. watch_company.gd counts her as watching and she looks at the screen.
## It ends when Anon is away from the set (another house, or far) for AWAY_SECONDS; when the set
## stays off (she says something first, then gets up); when following never reaches a set within
## FOLLOW_GIVE_UP (she says so); or on any new movement or [cancel]. ended() tidies up.
## note() is what a watching pony is told about what is on (ext/conversation_director.gd).

const HOUSE := preload("res://world/buildings/house_interior.gd")
const SEAT := preload("res://world/life/seat.gd")
const FINDS := preload("res://mods/watch_party/finds.gd")
const HUB := "/root/Mods/watch_party"
## A set this close (flat metres, same house) is "nearby": she goes to it instead of following.
const TV_NEAR := 10.0
## Farther than TV_NEAR but within this (same house, or both outdoors): a pony knows the set is
## there, but not what is on (watch_company.gd prompt_note; playtest 2026-11-06, the party).
const TV_SEEN := 25.0
## A set that does not work yet this close (flat metres, same house) is in front of her to see.
const DORMANT_NEAR := 8.0
## Seats this far from the screen at most, and the least they must face it.
const SEAT_RANGE := 5.0
const SEAT_FACING := 0.55
## Floor spots in front of the set: metres out, then metres to either side.
const FLOOR_OUT := [2.2, 2.7, 1.8, 3.2]
const FLOOR_SIDE := [0.0, 0.75, -0.75, 1.4, -1.4]
const SPOT_GAP := 0.9
const SEAT_TRIES := 5
const AWAY_SECONDS := 120.0
const AWAY_METRES := 15.0
const OFF_PROMPT_SECONDS := 90.0
const OFF_LEAVE_SECONDS := 180.0
const FOLLOW_GIVE_UP := 600.0
## Television item ids (catalog.gd), and how often owned_homes() reads the briefcase again.
const TV_PREFIX := "goods:watch-tv-"
const REMOTE_ID := "goods:watch-tv-remote"
const OWNED_EVERY := 5.0
static var _owned: Array = []
static var _owned_at := -INF
static var _briefcase: WeakRef
const NO_PLACE := "You meant to settle in and watch Anon's television with him, but you could not find a free place in front of it that you could get to. Tell him so in a few words, in your own way."

## [watch_tv] is offered while Anon has a television set up in a house, loaded or not (she walks
## along with him until one is near).
static func offered(actor: Node) -> bool:
	if not actor.is_inside_tree(): return false
	return not actor.get_tree().get_nodes_in_group("watch_tvs").is_empty() or not owned_homes(actor.get_tree()).is_empty()

## The houses (place ids) where Anon has a television set up, from the briefcase's saved loans
## (world/inventory/inventory_store.gd: furnishing_home), so it is known while that house is
## not loaded. Read again at most every OWNED_EVERY seconds.
static func owned_homes(tree: SceneTree) -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _owned_at < OWNED_EVERY: return _owned
	_owned_at = now
	_owned = []
	var briefcase: Node = _briefcase.get_ref() as Node if _briefcase != null else null
	if not is_instance_valid(briefcase) and tree != null:
		briefcase = tree.root.find_child("BriefcaseInventory", true, false)
		_briefcase = weakref(briefcase) if briefcase != null else null
	var store: Variant = briefcase.get("inventory") if is_instance_valid(briefcase) else null
	var loans: Variant = (store as Object).get("loans") if store is Object else null
	if not loans is Dictionary: return _owned
	for loan: Variant in (loans as Dictionary).values():
		if not loan is Dictionary: continue
		var id := str((loan as Dictionary).get("id", ""))
		var home := str((loan as Dictionary).get("furnishing_home", ""))
		# Only a set that works (Twilight has woken its kind: finds.gd).
		if id.begins_with(TV_PREFIX) and id != REMOTE_ID and FINDS.powered(id) and not home.is_empty() and not home in _owned: _owned.append(home)
	return _owned

static func hub(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null(HUB) if tree != null else null

static func company(tree: SceneTree) -> Node:
	var node := hub(tree)
	var found: Variant = node.get("company") if node != null else null
	return found as Node if is_instance_valid(found) else null

## She is settled in front of a set (ext/conversation_director.gd skips her lulls).
static func watching(node: Node, id: String) -> bool:
	var watchers: Node = company(node.get_tree()) if node != null and node.is_inside_tree() else null
	return watchers != null and bool(watchers.call("is_watching", id))

static func _director(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group("conversation_director")

static func _player(ex: Node) -> Node3D:
	var director := _director(ex.get_tree())
	if director == null or not director.has_method("_action_targets"): return null
	var targets: Variant = director.call("_action_targets", str(ex.character_id))
	var player: Variant = (targets as Dictionary).get("player") if targets is Dictionary else null
	return player as Node3D if is_instance_valid(player) else null

## The nearest working set to `at` in the same house (or, out of doors, one also out of doors: a
## woken set works anywhere it is set down), within TV_NEAR; null when none.
static func near_tv(tree: SceneTree, at: Vector3, reach := TV_NEAR) -> Node3D:
	var house := HOUSE.at(tree, at)
	var best: Node3D = null
	var best_distance := reach
	for node: Node in tree.get_nodes_in_group("watch_tvs"):
		var tv := node as Node3D
		if tv == null or not bool(tv.get("active")): continue
		var distance := _flat(tv.global_position, at)
		if distance <= best_distance and HOUSE.at(tree, tv.global_position) == house:
			best = tv
			best_distance = distance
	return best

## A set Twilight has not woken yet standing near `at` (within DORMANT_NEAR, same house or both
## outdoors), put down by Anon: not one for sale or lying in the forest, not one in his hands.
## Null if none.
static func dormant_near(tree: SceneTree, at: Vector3) -> Node3D:
	var house := HOUSE.at(tree, at)
	var best: Node3D = null
	var best_distance := DORMANT_NEAR
	for node: Node in tree.get_nodes_in_group("watch_tvs_dormant"):
		var tv := node as Node3D
		if tv == null or not tv.is_inside_tree() or not tv.has_method("_standing") or not bool(tv.call("_standing", false)): continue
		var distance := _flat(tv.global_position, at)
		if distance <= best_distance and HOUSE.at(tree, tv.global_position) == house:
			best = tv
			best_distance = distance
	return best

static func _tv(m: Dictionary) -> Node3D:
	var ref: Variant = m.get("watch_tv_ref")
	var tv: Variant = (ref as WeakRef).get_ref() if ref is WeakRef else null
	return tv as Node3D if is_instance_valid(tv) and bool((tv as Node3D).get("active")) else null

## One executor tick of a [watch_tv] movement. False hands the tick back to the executor (she is
## following Anon, an ordinary follow).
static func step(ex: Node, m: Dictionary, dt: float) -> bool:
	if not m.has("watch"):
		m.watch = true
		m.watch_phase = "find"
		m.watch_elapsed = 0.0
		print("[watch_party] %s accepted: coming to watch" % ex.character_id)
	m.watch_elapsed = float(m.watch_elapsed) + dt
	match str(m.watch_phase):
		"follow": return _following(ex, m)
		"seat": _seat(ex, m)
		"watching": _watching(ex, m, dt)
		_: _find(ex, m)
	return true

static func _find(ex: Node, m: Dictionary) -> void:
	var actor: Node3D = ex.actor
	var tv := near_tv(ex.get_tree(), actor.global_position)
	if tv != null:
		m.watch_tv_ref = weakref(tv)
		m.watch_phase = "seat"
		return
	var player := _player(ex)
	if player == null:
		ex._end_move("failed", "Anon is not around to watch with")
		return
	# No set nearby: go along with him; the executor walks it as a follow of the player.
	m.type = "follow"; m.target_id = "player"; m.target = weakref(player)
	m.formation = "right"; m.distance_m = 1.5
	m.watch_phase = "follow"
	m.follow_since = float(m.watch_elapsed)
	actor.set_meta("active_follow", true)
	ex._report(m, "running", "Going along with Anon to watch something on his television")

## Following Anon: once a set is near she stops following and goes to it; after FOLLOW_GIVE_UP she
## gives up politely.
static func _following(ex: Node, m: Dictionary) -> bool:
	var actor: Node3D = ex.actor
	var tv := near_tv(ex.get_tree(), actor.global_position)
	if tv != null:
		m.type = "watch_tv"
		m.erase("target"); m.erase("target_id"); m.erase("formation"); m.erase("distance_m")
		m.watch_tv_ref = weakref(tv)
		m.watch_phase = "seat"
		actor.set_meta("active_follow", false)
		if is_instance_valid(ex.navigator): ex.navigator.stay()
		ex._last_goal = Vector3.INF
		return true
	if float(m.watch_elapsed) - float(m.get("follow_since", 0.0)) > FOLLOW_GIVE_UP:
		_say(ex, "watch-gave-up", "You agreed to watch something on Anon's television with him and have gone along with him a good while, but there is still no television in sight. Tell him kindly, in a few words and in your own way, that you will watch with him another time.")
		ex._end_move("cancelled", "Gave up going along to watch television", true)
		return true
	return false

## Finding a place and walking there (world/life/seating.gd does the walk, the hop and the sit).
static func _seat(ex: Node, m: Dictionary) -> void:
	var actor: Node3D = ex.actor
	var tv := _tv(m)
	if tv == null:
		_free_spot(m)
		m.watch_phase = "find"
		m.seat_asked = false
		return
	var seating: Node = ex.get_tree().get_first_node_in_group("pony_seating")
	if seating == null:
		ex._end_move("failed", "Nowhere to sit")
		return
	if not bool(m.get("seat_asked", false)):
		var status: Dictionary = actor.posture_status()
		if status.kind != "stand" or not status.settled:
			actor.request_posture("stand")
			return
		# Still getting off another seat: seating.gd takes one seat per pony at a time.
		if not str(seating.phase(actor)).is_empty(): return
		var spot := _pick_spot(ex, m, tv, seating)
		if spot.is_empty():
			_say(ex, "watch-no-seat", NO_PLACE)
			ex._end_move("failed", "No free seat or spot in front of the television")
			return
		if not seating.sit(actor, 30.0, spot.seat, spot.rest):
			_blocked(m, spot)
			return
		m.seat_ref = weakref(spot.seat)
		m.seat_key = str(spot.key)
		m.seat_asked = true
		ex._report(m, "running", "Going to settle in front of the television")
		return
	var phase := str(seating.phase(actor))
	if phase == "seated" and bool(actor.posture_status().settled):
		m.watch_phase = "watching"
		print("[watch_party] %s is settled in to watch" % ex.character_id)
		ex._report(m, "running", "Watching the television with Anon")
	elif phase == "":
		# Could not get there: the next best seat or spot.
		_blocked(m, {"key": m.get("seat_key", "")})
		_free_spot(m)
		m.seat_asked = false
		if int(m.get("seat_tries", 0)) >= SEAT_TRIES:
			_say(ex, "watch-no-seat", NO_PLACE)
			ex._end_move("failed", "Could not reach a seat or a spot in front of the television")

static func _blocked(m: Dictionary, spot: Dictionary) -> void:
	var blocked: Array = m.get("watch_blocked", [])
	blocked.append(str(spot.get("key", "")))
	m.watch_blocked = blocked
	m.seat_tries = int(m.get("seat_tries", 0)) + 1
	if spot.get("seat") is Node and (spot.seat as Node).has_meta("watch_spot"): (spot.seat as Node).queue_free()

## A free seat in front of the set, facing it; else a floor spot there. {seat, rest, key} or {}.
static func _pick_spot(ex: Node, m: Dictionary, tv: Node3D, seating: Node) -> Dictionary:
	var actor: Node3D = ex.actor
	var tree := ex.get_tree()
	var blocked: Array = m.get("watch_blocked", [])
	var screen := _screen(tv)
	var out := Vector3(tv.global_basis.z.x, 0.0, tv.global_basis.z.z).normalized()
	var house := HOUSE.at(tree, tv.global_position)
	var best: Node3D = null
	var best_score := INF
	# Untyped: a freed seat must be checked before it is assigned to a Node3D variable.
	for entry: Variant in seating.get("seats"):
		if not is_instance_valid(entry): continue
		var seat := entry as Node3D
		if seat == null or seat.has_meta("watch_spot") or seat.get_meta("floor_sit", false): continue
		if str(seat.get_instance_id()) in blocked or not seating.call("_free", seat, actor): continue
		var couch: Variant = seat.get_meta("couch") if seat.has_meta("couch") else null
		if is_instance_valid(couch) and bool((couch as Object).get("opened")): continue
		var to_screen := screen - seat.global_position
		to_screen.y = 0.0
		var distance := to_screen.length()
		if distance < 1.2 or distance > SEAT_RANGE: continue
		if HOUSE.at(tree, seat.global_position) != house: continue
		var facing := Vector3(-seat.global_basis.z.x, 0.0, -seat.global_basis.z.z).normalized()
		var looks := facing.dot(to_screen.normalized())
		# Facing the screen, and in front of it rather than behind or beside the set.
		if looks < SEAT_FACING or out.dot(-to_screen.normalized()) < 0.3: continue
		var score := absf(distance - 2.6) + (1.0 - looks) * 2.0
		if score < best_score:
			best = seat
			best_score = score
	if best != null: return {"seat": best, "rest": {}, "key": str(best.get_instance_id())}
	var navigator: Node = ex.navigator
	var right := out.cross(Vector3.UP)
	var space := tv.get_world_3d().direct_space_state
	var skip: Array[RID] = [actor.get_rid()]
	var body: Variant = tv.get("body")
	if body is CollisionObject3D: skip.append((body as CollisionObject3D).get_rid())
	# The floor the set stands on; a wall-mounted one hangs above it, so take the floor in front.
	var floor_y := tv.global_position.y
	if str(tv.get("variant")) == "wall" and is_instance_valid(navigator) and navigator.has_method("command_support"):
		var below: Vector3 = navigator.command_support(tv.global_position + out * 0.6)
		if below.is_finite(): floor_y = below.y
	for distance: float in FLOOR_OUT:
		for side: float in FLOOR_SIDE:
			var key := "floor:%.2f:%.2f" % [distance, side]
			if key in blocked: continue
			var at := tv.global_position + out * distance + right * side
			var ground: Vector3 = navigator.command_support(at) if is_instance_valid(navigator) and navigator.has_method("command_support") else at
			if not ground.is_finite() or absf(ground.y - floor_y) > 0.4: continue
			if HOUSE.at(tree, ground) != house or _spot_taken(tree, ground): continue
			# Nothing between her and the screen (a wall, a table, a pillar).
			var ray := PhysicsRayQueryParameters3D.create(ground + Vector3.UP * 0.6, screen, 1, skip)
			if not space.intersect_ray(ray).is_empty(): continue
			var spot: Node3D = SEAT.new()
			spot.name = "WatchSpot"
			spot.set("floor_sit", true)
			spot.set("for_player", false)
			spot.set_meta("watch_spot", key)
			tv.add_child(spot)
			var look := screen - ground
			look.y = 0.0
			spot.global_transform = Transform3D(Basis.looking_at(look.normalized(), Vector3.UP), ground)
			m.spot_ref = weakref(spot)
			# On the floor she always lies down (dev 2026-11-01: the lying pose is the one).
			return {"seat": spot, "rest": {"posture": "lie_down"}, "key": key}
	return {}

static func _spot_taken(tree: SceneTree, at: Vector3) -> bool:
	for node: Node in tree.get_nodes_in_group("watch_tvs"):
		for child: Node in node.get_children():
			if child is Node3D and child.has_meta("watch_spot") and _flat((child as Node3D).global_position, at) < SPOT_GAP: return true
	return false

static func _free_spot(m: Dictionary) -> void:
	var ref: Variant = m.get("spot_ref")
	var spot: Variant = (ref as WeakRef).get_ref() if ref is WeakRef else null
	if is_instance_valid(spot): (spot as Node).queue_free()
	m.erase("spot_ref")

static func _screen(tv: Node3D) -> Vector3:
	var point: Variant = tv.get("gaze_point")
	return (point as Node3D).global_position if is_instance_valid(point) else tv.global_position + Vector3.UP * 0.7

## Settled in front of the set.
static func _watching(ex: Node, m: Dictionary, dt: float) -> void:
	var actor: Node3D = ex.actor
	var id := str(ex.character_id)
	var tree := ex.get_tree()
	var watchers := company(tree)
	var tv := _tv(m)
	if tv == null:
		# The set was picked up or put away.
		ex._end_move("cancelled", "The television is gone", true)
		return
	var seating: Node = tree.get_first_node_in_group("pony_seating")
	if seating == null or str(seating.phase(actor)) != "seated":
		# Up again (picked up and put down, or nudged off): find a place again.
		if watchers != null: watchers.stop_watching(id)
		_free_spot(m)
		m.watch_phase = "seat"
		m.seat_asked = false
		return
	if watchers != null: watchers.watching(id, actor, tv)
	var point: Variant = tv.get("gaze_point")
	if (ex.gaze as Dictionary).is_empty() and actor.has_method("set_action_gaze") and is_instance_valid(point): actor.set_action_gaze(point)
	# Anon gone: another house, or far from the set.
	var player := _player(ex)
	var away: bool = player == null or HOUSE.at(tree, player.global_position) != HOUSE.at(tree, tv.global_position) or _flat(player.global_position, tv.global_position) > AWAY_METRES
	m.away_for = float(m.get("away_for", 0.0)) + dt if away else 0.0
	if float(m.away_for) > AWAY_SECONDS:
		ex._end_move("cancelled", "Anon left, so she stopped watching", true)
		return
	# The set off: after a while she says something, later she gets up.
	var state := str((tv.call("status") as Dictionary).get("state", "idle"))
	if state in ["playing", "paused", "tuning", "slides"]:
		m.off_for = 0.0
		m.off_told = false
		# A slideshow is on too (playtest 2026-11-07: Fluttershy, told it was off, said the box was black).
		ex._report(m, "running", "Watching a slideshow of Anon's pictures on the television" if state == "slides" else "Watching the television with Anon")
		return
	m.off_for = float(m.get("off_for", 0.0)) + dt
	ex._report(m, "running", "Sitting in front of the television; it is off")
	if not bool(m.get("off_told", false)) and float(m.off_for) > OFF_PROMPT_SECONDS:
		m.off_told = true
		_say(ex, "watch-off", "You are settled in front of Anon's television to watch something with him, but it has been off for a while now. Say something about it in a few words, in your own way: ask whether he still wants to put something on, or tease him a little. If you would rather stop waiting, say so and use [resume_routine].")
	elif bool(m.get("off_told", false)) and float(m.off_for) > OFF_PROMPT_SECONDS + OFF_LEAVE_SECONDS:
		ex._end_move("cancelled", "Stopped waiting for the television", true)

## A generated line in her own words (the director's intent queue), once per watch.
static func _say(ex: Node, kind: String, purpose: String) -> void:
	var director := _director(ex.get_tree())
	if director == null or not director.has_method("queue_generated_intent"): return
	var actor: Node3D = ex.actor
	var started := Time.get_ticks_msec()
	director.queue_generated_intent(str(ex.character_id), purpose, "%s:%s:%d" % [kind, ex.character_id, started],
		func() -> bool: return is_instance_valid(actor) and actor.is_inside_tree() and Time.get_ticks_msec() - started < 60000, Callable(), true)

## Movement tags that [watch_tv] already covers: while she is on her way to watch (or watching),
## these from the same or a later reply leave the watch be instead of replacing it.
const KEPT := ["sit", "lie_down", "stay", "stand", "sit_on_seat", "approach", "follow"]

static func keeps(m: Dictionary, action: Dictionary) -> bool:
	if not (m.get("type") == "watch_tv" or m.has("watch")): return false
	var kind := str(action.get("type", ""))
	if kind not in KEPT: return false
	# A follow or approach is only "come to Anon", which the watch does anyway.
	if kind in ["follow", "approach"] and str(action.get("target_id", "")) != "player": return false
	return true

## The watch is over (any reason): no longer a watcher, eyes free, up off the seat, spot removed.
static func ended(ex: Node, m: Dictionary, why := "") -> void:
	var actor: Node3D = ex.actor
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return
	var watchers := company(actor.get_tree())
	if watchers != null: watchers.stop_watching(str(ex.character_id))
	if (ex.gaze as Dictionary).is_empty() and actor.has_method("set_action_gaze"): actor.set_action_gaze(null)
	if str(m.get("watch_phase", "")) in ["seat", "watching"] and actor.has_method("request_posture"): actor.request_posture("stand")
	_free_spot(m)
	print("[watch_party] %s stopped watching (%s, phase %s)" % [ex.character_id, why, str(m.get("watch_phase", "not started"))])

## What a pony watching with Anon is told about what is on, in her prompt ("" when she is not
## watching anything that is on; ext/conversation_director.gd system_prompt).
static func note(id: String) -> String:
	var watchers := company(Engine.get_main_loop() as SceneTree)
	return str(watchers.call("note_for", id)) if watchers != null else ""

## The note on a group exchange among ponies near a set (ext/conversation_director.gd _group_prompt).
static func group_note(members: Array) -> String:
	var watchers := company(Engine.get_main_loop() as SceneTree)
	return str(watchers.call("group_note", members)) if watchers != null else ""

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
