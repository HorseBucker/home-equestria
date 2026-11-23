extends "res://world/life/day/day_action.gd"
## Cherry Berry brings the hot-air balloon home on foot (Ponyville overhaul, 2026-11-22: "Cherry Berry can walk the
## balloon back to the pad holding a rope in her mouth, keeping the balloon elevated high enough above her to clear
## buildings through town"). A day step balloon_fetch.gd puts first in her day:
## travel (to the basket's ramp) -> ask (Anon close by: is he still using it? balloon_fetch.gd asks and answers)
## -> hitch (the balloon rises on its rope, balloon_tow.gd TOW_HEIGHT over her) -> tow (she walks home with the rope in her mouth,
## the balloon trailing above) -> land (it settles onto its pad) -> done.
## step.mode "fly": once Anon has said yes (or is not there to ask), the step ends at the basket and
## balloon_fetch.gd has her fly it home instead (fly_balloon.gd), from where she stands.
## Interrupted on the way, the balloon is let down where it is when that is open ground, else set on its pad.

const FETCH := "res://world/towns/ponyville/balloon_fetch.gd"
const TOW := "res://world/life/day/actions/balloon_tow.gd"
const RISE_SECONDS := 6.0        # (its height and trail: balloon_tow.gd)
const LAND_SECONDS := 7.0
const NEAR_BASKET := 4.0
const NEAR_PAD := 3.5
const TRAVEL_LIMIT := 420.0      # seconds to reach the basket
const TOW_LIMIT := 900.0         # seconds to walk it home

var _ship: CharacterBody3D
var _phase := "travel"
var _tow: Node                    # balloon_tow.gd, while the balloon is on her rope
var _pad_spot := Vector3.INF      # where she stops beside the pad
var _from := Vector3.INF
var _tries := 0
var _target := Vector3.INF
var reason := ""


func start(ctx: Dictionary) -> bool:
	_ship = _balloon(ctx.tree)
	if _ship == null: reason = "No balloon"; return false
	if not bool(_ship.get("landed")) or not (_ship.get("passengers") as Array).is_empty(): reason = "The balloon is in use"; return false
	var game: Node = _ship.get("game")
	var player: Variant = game.get("player") if game != null else null
	if player != null and _ship.has_method("holds_player") and bool(_ship.call("holds_player", player)): reason = "Anon is in the basket"; return false
	claim(ctx)
	_target = _reachable_near(ctx, 0)
	_go(ctx, _target)
	ctx.actor.set_meta("life_intent", "Going to fetch the hot-air balloon home")
	return true


func tick(ctx: Dictionary, delta: float) -> String:
	seconds += delta
	if not is_instance_valid(_ship): return _failed("The balloon is gone")
	var nav: Node = ctx.nav
	match _phase:
		"travel":
			if not bool(_ship.get("landed")): return _failed("Somepony took the balloon up")
			if arrived(ctx, _target, 2.0) or Vector2(ctx.actor.global_position.x - _ship.global_position.x, ctx.actor.global_position.z - _ship.global_position.z).length() < NEAR_BASKET + 1.5:
				nav.stay()
				_phase = "ask"; seconds = 0.0
				# (Anon sent her for it himself: nothing to ask)
				if not bool(ctx.step.get("asked", false)): fetch(ctx).call("begin_ask", ctx.tree, _ship)
				return "running"
			if seconds > TRAVEL_LIMIT: return _failed("Could not reach the balloon")
			# (her route ended short of it, or there is none: the next walkable point round the basket)
			if nav.state in [nav.State.UNREACHABLE, nav.State.BLOCKED] or (not nav._has_target and seconds > 3.0):
				_tries += 1
				if _tries > 8: return _failed("Could not reach the balloon")
				_target = _reachable_near(ctx, _tries)
				_go(ctx, _target)
		"ask":
			var answer := "take" if bool(ctx.step.get("asked", false)) else str(fetch(ctx).call("answer"))
			if answer == "": return "running"
			if answer != "take": reason = "Anon asked her to leave it"; return "done"
			if str(ctx.step.get("mode", "walk")) == "fly":
				fetch(ctx).call("fly_now")       # (balloon_fetch.gd starts her flight from here)
				return "done"
			_hitch(ctx)
		"hitch":
			if not is_instance_valid(_tow): return _failed("The rope slipped")
			if _tow.risen():
				_phase = "tow"; seconds = 0.0
				_go(ctx, _pad_spot)
				ctx.actor.set_meta("life_intent", "Walking the hot-air balloon home on its rope")
		"tow":
			if not is_instance_valid(_tow): return _failed("The rope slipped")
			if arrived(ctx, _pad_spot, NEAR_PAD):
				nav.stay()
				_phase = "land"; seconds = 0.0
				_tow.land((_ship.get("home") as Transform3D).origin)
				return "running"
			if seconds > TOW_LIMIT: _let_down(ctx); return _failed("Could not walk the balloon home")
			if nav.state in [nav.State.UNREACHABLE, nav.State.BLOCKED] or (not nav._has_target and seconds > 3.0):
				_tries += 1
				if _tries > 6: _let_down(ctx); return _failed("Could not walk the balloon home")
				_go(ctx, _pad_spot)
		"land":
			var home: Transform3D = _ship.get("home")
			if not is_instance_valid(_tow) or _tow.landed():
				_drop_rope()
				_set_on(home.origin, home.basis.get_euler().y)
				print("[balloon] Cherry Berry walked the balloon home on its rope")
				return "done"
	return "running"


## Why she gave up, in the log too (2026-11-22 play test: a fetch that ended said nothing).
func _failed(why: String) -> String:
	reason = why
	print("[balloon] Cherry Berry stopped fetching the balloon: %s (%s)" % [why, _phase])
	return "failed"


func stop(ctx: Dictionary) -> void:
	if _phase in ["hitch", "tow", "land"] and is_instance_valid(_ship): _let_down(ctx)
	_drop_rope()
	if str(fetch(ctx).call("answer")) == "" and _phase == "ask": fetch(ctx).call("end_ask")
	super.stop(ctx)


func release(ctx: Dictionary) -> void:
	_drop_rope()
	super.release(ctx)


static func fetch(ctx: Dictionary) -> Node:
	var node: Node = ctx.tree.root.find_child("BalloonFetch", true, false)
	if node == null: node = (load(FETCH) as GDScript).new()
	return node


static func _balloon(tree: SceneTree) -> CharacterBody3D:
	for node: Node in tree.get_nodes_in_group("hot_air_balloons"):
		if node is CharacterBody3D and node.is_inside_tree(): return node as CharacterBody3D
	return null


## Where she stands by the basket: its ramp's foot.
func _basket_spot() -> Vector3:
	return _ship.call("_ramp_foot") if _ship.has_method("_ramp_foot") else _ship.global_position


## A point she can stand on by the basket: its ramp's foot when walkable, else one round it (try k picks which).
func _reachable_near(ctx: Dictionary, k: int) -> Vector3:
	var nav: Node = ctx.nav
	var spots: Array[Vector3] = [_basket_spot()]
	for i in 8:
		var a := TAU * float(i) / 8.0
		spots.append(_ship.global_position + Vector3(cos(a), 0.0, sin(a)) * 5.0)
	for j in spots.size():
		var at: Vector3 = spots[(j + k) % spots.size()]
		var walkable: Vector3 = nav.call("command_support", at) if nav.has_method("command_support") else at
		if walkable.is_finite(): return walkable
	return _basket_spot()


func _go(ctx: Dictionary, at: Vector3) -> void:
	var far: bool = ctx.actor.global_position.distance_to(at) > 40.0
	ctx.nav.go_to(at, ctx.nav.Gait.TROT if far and _phase == "travel" else ctx.nav.Gait.WALK)


## The balloon is on her rope: it stops being a vehicle of its own until it is down again; balloon_tow.gd moves it
## and draws the rope every frame.
func _hitch(ctx: Dictionary) -> void:
	var home: Transform3D = _ship.get("home")
	# beside the pad where its ramp comes down, the way she walks up to it
	var local: Vector3 = _ship.global_transform.affine_inverse() * _basket_spot()
	_pad_spot = home * local
	_ship.set_physics_process(false); _ship.set_process(false)
	_ship.velocity = Vector3.ZERO
	_phase = "hitch"; seconds = 0.0
	_tow = (load(TOW) as GDScript).new()
	_tow.name = "BalloonTow"
	ctx.actor.add_child(_tow)
	_tow.rise_seconds = RISE_SECONDS; _tow.land_seconds = LAND_SECONDS
	_tow.begin(ctx.actor, _ship)
	print("[balloon] Cherry Berry takes the balloon's rope in her mouth")


func _drop_rope() -> void:
	if is_instance_valid(_tow): _tow.finish()
	_tow = null


## Down from the rope: on open ground below her when there is some, else on its pad.
func _let_down(ctx: Dictionary) -> void:
	_drop_rope()
	if not is_instance_valid(_ship): return
	var below: Vector3 = ctx.actor.global_position if is_instance_valid(ctx.actor) else _ship.global_position
	var space := _ship.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(below + Vector3.UP * 30.0, below + Vector3.DOWN * 5.0, 1, [_ship.get_rid()]))
	# open ground: nothing built there (the terrain's own collision is only made near the camera)
	var open: bool = (hit.is_empty() or (hit.collider as Object).is_class("Terrain3D")) and is_instance_valid(WorldTerrain.instance)
	var home: Transform3D = _ship.get("home")
	if open:
		var at: Vector3 = below + (ctx.actor.global_basis.z if is_instance_valid(ctx.actor) else Vector3.ZERO) * 4.0
		at.y = WorldTerrain.instance.height_at(at)
		_set_on(at, _ship.rotation.y)
	else: _set_on(home.origin, home.basis.get_euler().y)
	print("[balloon] Cherry Berry let the balloon down %s" % ("where she was" if open else "on its pad"))


func _set_on(at: Vector3, yaw: float) -> void:
	_ship.set_physics_process(true); _ship.set_process(true)
	_ship.call("restore", {"position": [at.x, at.y, at.z], "yaw": yaw})
