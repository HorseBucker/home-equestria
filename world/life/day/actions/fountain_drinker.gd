extends Node
## One drink at the fountain, frame by frame (drink_at_fountain.gd makes it once she stands at her
## spot facing the water; the day runner's half-second beat is too coarse for a body pose). Play test
## 2026-11-16: "At the canon and JTRHNBR heights, they need to put their forelegs up on the rim of the
## fountain and lean their heads down to the water. At the taller height settings for the ponies,
## they just need to walk closer and lean down to drink. They should close their eyes as they drink."
##
## turn (square up to the basin) -> measure (fountain_drink_pose.gd probes both plans on her rig)
## -> approach (real steps closer: the walk grid keeps her 0.45 m off the wall, so this last bit is
## the drink's own) -> settle -> up (rear: a hop, body up and both forehooves onto the rim together)
## -> lower (a little lean down, eyes shut; leaning: her front dips on buckled forelegs) -> sip (SIPS
## small lifts, a quiet sip each) -> raise (eyes open, she leans back a little) -> down (rear: hops
## off, hooves straight down with her body) -> away (turns side-on to the fountain) -> off (walks on
## out to the spot she walked to) -> done. (2026-11-18 play test: "she goes up to it, hops up with her
## forelegs, a little lean down without stretching her neck, some quiet drinking sounds, then she leans
## back slightly and turns and hops off so she's got her side to the fountain once she's done, rather
## than the odd little back walk she does now".)
## A chat, being picked up or asleep: "hold" eases everything back to standing with her eyes open
## and picks up again from "up" once it is over. abort() (the step was cut short): eases out fast and
## frees everything; she is left standing where she is (she walks off under her new owner).
## Process priority -5: after the navigator's halt (-10), before her locomotion reads the request (0),
## as pony_affection.gd steers a kiss.

const POSE := preload("res://world/life/day/actions/fountain_drink_pose.gd")
const SFX := preload("res://world/audio/interaction_sounds.gd")
## The hop up onto the rim and off it again (both forehooves together), and the turn away after.
const HOP_UP_SECONDS := 0.55
const HOP_DOWN_SECONDS := 0.45
const DIP_SECONDS := 0.9
const TURN_LIMIT := 3.0
const SIPS := 3
const SIP_SECONDS := 2.2
## The muzzle lifts this far (x body scale) off the water between sips.
const SIP_LIFT := 0.05
## Seconds each control takes 0 -> 1.
const REAR_SECONDS := 1.5
const HOOF_SECONDS := 1.0
const HEAD_SECONDS := 1.1
## Faster when a chat or a command takes her.
const HOLD_RATE := 1.8
const ABORT_RATE := 3.0
const WALK_SPEED := 0.22
const STEP_LIMIT := 8.0
## The last step to the rim and the turn away after, at most (2026-11-21: trimmed, the pauses showed).
const APPROACH_LIMIT := 2.5
const AWAY_LIMIT := 1.2
var _stalled := 0.0
var _sliding := false
const EYES := "fountain_drink"

## Her body (pony_locomotion.gd; untyped: its motion commands are script methods).
var actor
var water: Node3D
var owner_tag := ""
var stage := "turn"
var stage_seconds := 0.0
## "" while drinking, then "done" or "failed" (reason says why).
var outcome := ""
var reason := ""
var kind := ""
var pose: SkeletonModifier3D
var lease: RefCounted
var _rear := 0.0
var _hooves: Array[float] = [0.0, 0.0]
var _head := 0.0
var _bob := 0.0
var _sip_clock := 0.0
var _home_r := INF
var _eyes_shut := false
var _aborting := false
var _steered := false
var _aligned_seconds := 0.0
var _done := false
var _dip := 0.0
var _away := Vector3.ZERO
var _sipped := 0


func _ready() -> void:
	process_physics_priority = -5


## Set up on her: the pose modifier on her body skeleton and the lease that keeps her at full detail.
func begin(body: Node3D, fountain_water: Node3D, tag: String) -> bool:
	actor = body
	water = fountain_water
	owner_tag = tag
	var sk: Skeleton3D = actor.get("skeleton") as Skeleton3D
	if sk == null or sk.find_bone("pony_head") < 0 or actor.get_node_or_null("Affection") == null: return false
	pose = POSE.new()
	pose.name = "FountainDrinkPose"
	pose.pony = actor
	pose.water = water
	sk.add_child(pose)
	# The mouth-pose slot pins her at full simulation (pony_locomotion.gd body_pinned) and keeps the
	# expression stance and Pinkie's bounce off her body; taken only when nopony else holds it.
	if "activity_mouth_pose" in actor and actor.get("activity_mouth_pose") == null:
		lease = Lease.new()
		lease.drinker = weakref(self)
		actor.set("activity_mouth_pose", lease)
	return true


## The step was cut short: ease out fast, free everything, leave her be.
func abort() -> void:
	_aborting = true
	if _steered and is_instance_valid(actor): actor.stop()
	_steered = false


func engaged() -> bool:
	return outcome.is_empty() or _rear > 0.0 or _head > 0.0 or _dip > 0.0 or _hooves[0] > 0.0 or _hooves[1] > 0.0


func _hold_reason() -> String:
	if actor.get("sleeping") == true: return "asleep"
	if actor.has_method("is_held") and actor.is_held(): return "held"
	if is_instance_valid(actor.get("conversation_target")): return "chat"
	if not actor.has_method("grounded") or not actor.grounded(): return "off the ground"
	var flight: RefCounted = actor.get("flight")
	if flight != null and flight.active(): return "flying"
	return ""


func _physics_process(delta: float) -> void:
	if _done: return
	if not is_instance_valid(actor) or not is_instance_valid(water) or not is_instance_valid(pose):
		_finish("failed", "Lost her"); return
	stage_seconds += delta
	var s := float(actor.get("body_scale"))
	if _aborting:
		_ease_all(delta * ABORT_RATE)
		if _all_down(): _finish("failed", "Stopped"); return
		_drive()
		return
	var held := _hold_reason()
	if not held.is_empty() and stage in ["approach", "settle", "up", "lower", "sip", "raise", "down", "away", "off"]:
		if _steered: actor.stop(); _steered = false
		if stage != "hold": _go("hold")
	match stage:
		"turn":
			# Square up to the basin's axis (the step's align stops within 25 degrees).
			var b: Dictionary = pose.basin()
			var toward: Vector3 = -b.out
			actor.face_direction(toward)
			var forward: Vector3 = -actor.global_basis.z
			forward.y = 0.0
			_aligned_seconds = _aligned_seconds + delta if forward.normalized().dot(toward) > 0.996 and float(actor.get("actual_speed")) < 0.04 else 0.0
			if _aligned_seconds > 0.15 or stage_seconds > 3.0:
				actor.stop()
				var affection: Node = actor.get_node_or_null("Affection")
				pose.bind_mouth = affection.mouth_point() if affection != null and affection.has_method("mouth_point") else Vector3.INF
				if not pose.bind_mouth.is_finite(): _finish("failed", "No mouth point"); return
				pose.probe_wanted = true
				_home_r = POSE._r(actor.global_position, b.centre)
				_go("measure")
		"measure":
			if pose.probe.is_empty():
				if stage_seconds > 3.0: _finish("failed", "Could not measure her reach")
				return
			# Kept for tests (lab_agent_f.gd prints why a pony drank which way, or could not).
			set_meta("probe", pose.probe)
			kind = choose(pose.probe, s)
			if kind.is_empty(): _finish("failed", "Too small to reach the water"); return
			pose.choose(kind)
			_go("approach")
		"approach":
			var left := _remaining()
			# (2026-11-21 play test: "they walk over real close and then pause for like 3-5 seconds before hopping up":
			# the last step chased 2 cm against the rim it leans on and ran out its 8 s; it ends once she is within
			# 6 cm, has stopped closing in, or after APPROACH_LIMIT)
			if stage_seconds <= delta: _pass_rim(true)
			_stalled = _stalled + delta if stage_seconds > 0.8 and float(actor.get("actual_speed")) < 0.02 else 0.0
			if absf(left) < 0.03 * s or stage_seconds > APPROACH_LIMIT:
				actor.stop(); _steered = false
				_go("settle")
			elif _stalled > 0.2 or _sliding:
				# she walks the last of it slowly against the rim (her steering eases off by walls): she is slid in at
				# a walking pace instead, straight toward the water, her legs stepping as she goes
				_sliding = true
				var b: Dictionary = pose.basin()
				var move := minf(absf(left), clampf(WALK_SPEED * 1.4 * s, 0.15, 0.45) * delta) * signf(left)
				actor.global_position += -Vector3(b.out) * move
				_step(left, s)
			else:
				_step(left, s)
		"settle":
			actor.stop()
			if stage_seconds > 0.15 and float(actor.get("actual_speed")) < 0.05:
				pose.anchor_wanted = true
				_go("anchor")
		"anchor":
			if pose.anchored: _go("up" if kind == "rear" else "lower")
			elif stage_seconds > 2.0: _finish("failed", "Could not anchor her hooves")
		"up":
			# a hop: body and both forehooves up together (the right a beat behind the left)
			_rear = move_toward(_rear, 1.0, delta / HOP_UP_SECONDS)
			_hooves[0] = move_toward(_hooves[0], 1.0, delta / HOP_UP_SECONDS)
			if _hooves[0] >= 0.12: _hooves[1] = move_toward(_hooves[1], 1.0, delta / HOP_UP_SECONDS)
			if _rear >= 1.0 and _hooves[1] >= 1.0 and stage_seconds > HOP_UP_SECONDS + 0.25: _go("lower")
		"lower":
			_head = move_toward(_head, 1.0, delta / HEAD_SECONDS)
			if kind == "lean": _dip = move_toward(_dip, 1.0, delta / DIP_SECONDS)
			if _head >= 1.0 and (kind != "lean" or _dip >= 1.0): _sip_clock = 0.0; _sipped = 0; _go("sip")
		"sip":
			_sip_clock += delta
			_bob = SIP_LIFT * s * (0.5 - 0.5 * cos(TAU * _sip_clock / SIP_SECONDS))
			# a quiet sip at the bottom of each dip of her muzzle
			if _sipped < SIPS and _sip_clock >= (float(_sipped) + 0.05) * SIP_SECONDS:
				_sipped += 1
				SFX.play_event(actor, "prop_sip", {"intensity": 0.6})
			if _sip_clock >= SIPS * SIP_SECONDS: _bob = 0.0; _go("raise")
		"raise":
			# she leans back a little: head up, the dip out
			_head = move_toward(_head, 0.0, delta / HEAD_SECONDS)
			_dip = move_toward(_dip, 0.0, delta / DIP_SECONDS)
			if _head <= 0.0 and _dip <= 0.0 and stage_seconds > 0.3: _go("down" if kind == "rear" else "away")
		"down":
			# hops off: body and hooves straight down together
			pose.descending = true
			_rear = move_toward(_rear, 0.0, delta / HOP_DOWN_SECONDS)
			_hooves[0] = _rear
			_hooves[1] = _rear
			if _all_down(): pose.descending = false; _go("away")
		"away":
			# turns side-on to the fountain (whichever way is nearer the way she came)
			var b: Dictionary = pose.basin()
			if _away == Vector3.ZERO:
				var tangent: Vector3 = Vector3(b.out).cross(Vector3.UP).normalized()
				var forward: Vector3 = -actor.global_basis.z
				_away = tangent if tangent.dot(forward) >= 0.0 or randf() < 0.5 else -tangent
			actor.face_direction(_away)
			var facing: Vector3 = -actor.global_basis.z
			facing.y = 0.0
			if facing.normalized().dot(_away) > 0.94 or stage_seconds > AWAY_LIMIT: _go("off")
		"off":
			# walks on along the basin and out onto the walkable ring she came from
			var left := _home_r - POSE._r(actor.global_position, (pose.basin() as Dictionary).centre)
			if (left < 0.02 * s and stage_seconds > 0.6) or stage_seconds > STEP_LIMIT:
				actor.stop(); _steered = false
				_finish("done", "")
				return
			var out: Vector3 = (pose.basin() as Dictionary).out
			var way := (_away + out * (0.8 if left > 0.0 else 0.0)).normalized()
			actor.set_desired_velocity(way * clampf(WALK_SPEED * s, 0.15, 0.45)); _steered = true
		"hold":
			_bob = 0.0
			_dip = move_toward(_dip, 0.0, delta * HOLD_RATE / DIP_SECONDS)
			_head = move_toward(_head, 0.0, delta * HOLD_RATE / HEAD_SECONDS)
			if _head <= 0.3: _lower_hooves(delta * HOLD_RATE)
			if _all_down() and held.is_empty() and stage_seconds > 0.5:
				# Over: on with the drink from where she stands.
				if pose.anchored: _go("up" if kind == "rear" else "lower")
				else: _go("approach")
	_drive()


## Hooves down right first, then the left, the body level once both are off the rim.
func _lower_hooves(step: float) -> void:
	_head = move_toward(_head, 0.0, step / HEAD_SECONDS)
	_dip = move_toward(_dip, 0.0, step / DIP_SECONDS)
	if is_instance_valid(pose): pose.descending = true
	_rear = move_toward(_rear, 0.0, step / HOP_DOWN_SECONDS)
	_hooves[0] = minf(_hooves[0], _rear)
	_hooves[1] = minf(_hooves[1], _rear)


func _ease_all(step: float) -> void:
	_bob = 0.0
	_head = move_toward(_head, 0.0, step / HEAD_SECONDS)
	_lower_hooves(step)


func _all_down() -> bool:
	return _rear <= 0.0 and _head <= 0.0 and _dip <= 0.0 and _hooves[0] <= 0.0 and _hooves[1] <= 0.0


## The pose's controls, and her eyes: shut while her muzzle is down at the water.
func _drive() -> void:
	if _done or not is_instance_valid(pose): return
	pose.rear = _rear
	pose.hooves[0] = _hooves[0]
	pose.hooves[1] = _hooves[1]
	pose.head = _head
	pose.bob = _bob
	pose.dip = _dip
	_set_eyes(not _aborting and stage in ["lower", "sip"] and _head >= 0.75)


func _set_eyes(shut: bool) -> void:
	if shut == _eyes_shut: return
	_eyes_shut = shut
	var expressions: Object = actor.get("expressions") if is_instance_valid(actor) else null
	if expressions == null: return
	if shut: expressions.call("touch", EYES, 0.25, 1.0)
	else: expressions.call("release_touch", EYES)


## Metres still to walk toward the basin (negative: step back) to her plan's standing point.
func _remaining() -> float:
	var b: Dictionary = pose.basin()
	return POSE._r(actor.global_position, b.centre) - float(pose.plan.stand_r)


func _step(left: float, s: float) -> void:
	var speed := clampf(WALK_SPEED * 1.4 * s, 0.15, 0.45)
	if left > 0.0:
		var b: Dictionary = pose.basin()
		actor.set_desired_velocity(-Vector3(b.out) * speed)
	else:
		actor.back_up(minf(speed, actor.BACK_SPEED_MAX))
	_steered = true


func _go(next: String) -> void:
	stage = next
	stage_seconds = 0.0


## The plan for her from the probe: "lean" when her muzzle reaches the water over the rim standing
## on all fours; else "rear" when both forehooves land on the rim top (her muzzle then goes as low as
## her neck reaches); else "" (too small for this basin).
## Up to this body scale (the Canon and JRHNBR sizes, 1.0 and 1.35) she rears up with her forehooves on the rim
## whenever that reaches the water (2026-11-18 play test), even if she could lean over: a small pony at a big
## basin. Taller ones lean.
const REAR_UP_TO := 1.5
## (round 2 of that play test: her muzzle at the rim's inner lip is enough, "Not a big deal if her head is actually on
## the stone": at those sizes she rears whenever both forehooves land on the rim.) Taller ones lean, on buckled
## forelegs with a modest neck, however near the water their muzzle comes.
static func choose(probe: Dictionary, s: float) -> String:
	var lean: Dictionary = probe.get("lean", {})
	var lean_clear := float(lean.get("chest_clear", -1.0)) > -0.01
	var rears := _rear_fits(probe.get("rear", {}), s)
	if s <= REAR_UP_TO:
		if rears: return "rear"
		return "lean" if lean_clear and float(lean.get("mouth_gap", INF)) <= 0.12 * s else ""
	if lean_clear: return "lean"
	return "rear" if rears else ""


static func _rear_fits(rear: Dictionary, s: float) -> bool:
	for name: String in ["FL", "FR"]:
		if absf(float(rear.get(name + "_over_rim", INF))) > 0.07 * s: return false      # (0.02 refused every size, 2026-11-17)
		var r := float(rear.get(name + "_r", 0.0))
		if r < POSE.RIM_IN_R or r > POSE.RIM_OUT_R: return false
	for name: String in ["RL", "RR"]:
		if absf(float(rear.get(name + "_over_ground", INF))) > 0.03 * s: return false
	return true


func _finish(result: String, why: String) -> void:
	if _done: return
	_done = true
	outcome = result
	reason = why
	_cleanup()
	# Finished, she stays here (idle) until the step reads the outcome and frees her; an aborted
	# drink has nopony left to read it.
	if _aborting: queue_free()


## Her body and the fountain's round wall pass through each other while she drinks (2026-11-21: the drink's stand
## spot lies inside the wall's round collision, where the pose has her chest against the rim; walking into the wall
## she crept the last 0.4 m in 8 s). Given back when the drink ends, however it ends.
var _passing: Array = []
func _pass_rim(on: bool) -> void:
	if on:
		var fountain: Node = water.get_parent() if is_instance_valid(water) else null
		if fountain == null or not actor is PhysicsBody3D: return
		for body: Node in fountain.find_children("*", "StaticBody3D", true, false):
			(actor as PhysicsBody3D).add_collision_exception_with(body); _passing.append(weakref(body))
	else:
		for ref: WeakRef in _passing:
			var body: Object = ref.get_ref()
			if body != null and is_instance_valid(actor) and actor is PhysicsBody3D: (actor as PhysicsBody3D).remove_collision_exception_with(body as Node)
		_passing.clear()


func _cleanup() -> void:
	_pass_rim(false)
	if is_instance_valid(actor):
		if _steered: actor.stop()
		_set_eyes(false)
		var expressions: Object = actor.get("expressions")
		if expressions != null: expressions.call("release_touch", EYES)
		if lease != null and actor.get("activity_mouth_pose") == lease: actor.set("activity_mouth_pose", null)
	_steered = false
	lease = null
	if is_instance_valid(pose):
		pose.rear = 0.0; pose.head = 0.0; pose.hooves[0] = 0.0; pose.hooves[1] = 0.0
		pose.queue_free()
	pose = null


func _exit_tree() -> void:
	# Freed early (she streamed out, the world closed): never leave the pose, eyes or slot on her.
	if not _done:
		_done = true
		outcome = "failed"; reason = "Gone"
	_cleanup()


## Stands in her activity_mouth_pose slot while she drinks (the slot's contract: active(),
## apply_source(), apply_body_pivot(); this one changes nothing in the locomotion pose itself).
class Lease extends RefCounted:
	var drinker: WeakRef
	var owner := "fountain"
	var amount := 0.0
	var crouch_amount := 0.0

	func active() -> bool:
		var d: Object = drinker.get_ref() if drinker != null else null
		return d != null and bool(d.call("engaged"))

	func apply_source(_pose: Array[Transform3D], _delta: float) -> void:
		pass

	func apply_body_pivot(_pivot: Node3D) -> void:
		pass

	func release(_lease_owner: String) -> void:
		pass
