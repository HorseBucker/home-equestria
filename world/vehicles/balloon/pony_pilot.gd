extends Node
## A pony flies the hot-air balloon herself (play test 2026-11-16: "Cherry Berry should be able to get
## in the hot air balloon and go flying around town on her own ... Don't let her go TOO far, and have
## her come home and land before her bed time"). Started by her day step
## (world/life/day/actions/fly_balloon.gd); this node then owns the whole flight, so the balloon always
## comes home and lands, whatever happens to the step (bedtime, a command, a chat, the step's end):
##   boarding  - a short hop up the ramp to the helm (as balloon.gd's _climb)
##   preflight - a moment at the helm with the gate open: Anon can still climb in and ride along
##   climb, cruise - gate shut, up to cruising height, a slow wandering loop of waypoints over
##              Ponyville and its near outskirts (inside ROUTE_RADIUS of the Town Hall), turning gently
##   return    - back over the pad; descend - straight down onto it; landed - gate open
##   leaving   - she hops down the ramp and is let go; done
## Aboard she is a balloon passenger to every other system (meta "balloon_passenger": the population
## keeps her loaded, saves skip her move state, the AI executor holds walking moves until she lands)
## and "balloon_pilot" (awareness says she is the one flying it). Her navigator and AI executor are
## paused while aboard, as balloon.gd does for passengers; her navigator's owner is left as it is.
## The balloon follows ship.autopilot (a wanted world velocity) instead of its rope controls.
## A save made while she is away keeps the balloon on its pad (balloon.gd checkpoint), her beside it.

const TOWN: Vector3 = preload("res://world/audio/soundscape.gd").TOWN
const PLACES := preload("res://world/navigation/place_directory.gd")
const CLOUD_DRIFT := preload("res://world/buildings/cloudominium/cloud_drift.gd")
const OWNER := "vehicle:balloon:pilot"
## Where the pilot stands in the basket (balloon frame), facing the helm (+Z).
const PILOT_SPOT := Vector3(0.0, 0.27, 0.12)
## The route's waypoints stay within this of the Town Hall; turns overshoot them by well under 50 m.
const ROUTE_RADIUS := 380.0
const ROUTE_MIN := 150.0
## Slow, like a real balloon on a light breeze; at most TURN_RATE rad/s of turning.
const CRUISE_SPEED := 4.0
const TURN_RATE := 0.09
const WAYPOINT_REACHED := 28.0
## Basket height above the highest ground, roof, tree or cloud under and ahead of her.
const CRUISE_CLEARANCE := 32.0
const OBSTACLE_CLEARANCE := 20.0
## Never higher than this above the pad's ground; waypoints over ground this much higher are skipped.
const CEILING := 120.0
const HIGH_GROUND := 45.0
const LOOKAHEAD := [0.0, 20.0, 40.0, 60.0, 85.0]
## Rainbow Dash's drifting Cloudominium: kept this far (horizontally) beyond its own extent.
const CLOUD_MARGIN := 35.0
const PREFLIGHT := 10.0
## Anon standing near but not aboard: she gives him up to this long to climb in.
const PREFLIGHT_MAX := 30.0
const CLIMB_RATE := 1.6
const SINK_RATE := 1.1
const TOUCHDOWN_RATE := 0.45
const LANDED_WAIT := 2.5
## The weather kinds a flight goes up in (weather.gd); anything else brings her home.
const FAIR := ["clear", "cloudy", "mist"]

var ship: CharacterBody3D
var state := ""
var actor: Node3D
var id := ""
var row: Dictionary = {}
## Card hour (past midnight counts on from 24) by which she turns for home.
var turn_home_at := 99.0
var cut_reason := ""
var route: Array[Vector3] = []
var route_index := 0
var visited: PackedStringArray = []
var player_rode := false
## A ride for Anon he asked for (play test 2026-11-17, fly_balloon.gd ride steps): she waits at the
## helm with the gate open until he is aboard (up to RIDE_WAIT s), and the flight is for him.
var ride := false
const RIDE_WAIT := 90.0
var lost := false
## Measured along the flight (lab and debug).
var max_town_distance := 0.0
var min_clearance := INF
var max_height := 0.0
var _heading := Vector3.ZERO
var _clock := 0.0
var _sample_left := 0.0
var _target_y := NAN
var _floor_y := NAN
var _check_left := 0.0
var _where := ""
var _where_left := 0.0
var _clouds: Array[Node3D] = []
var _home_ground := NAN


static func of(balloon: CharacterBody3D) -> Node:
	var existing: Node = balloon.get_node_or_null("PonyPilot")
	if existing != null: return existing
	var made: Node = load("res://world/vehicles/balloon/pony_pilot.gd").new()
	made.name = "PonyPilot"
	made.ship = balloon
	made.process_physics_priority = -85   # after the rope controls (-90), before the balloon (-80)
	balloon.add_child(made)
	return made


## Why the balloon cannot be taken up now, or "" when it can: it must be resting on its pad's
## ground (not on a cloud, not where Anon left it far away), nopony flying it, and Anon not working
## its ropes or helm. Anon merely standing in the basket is welcome: he rides along.
## Fetching it home from wherever Anon left it (world/towns/ponyville/balloon_fetch.gd, Ponyville overhaul 2026-11-19
## play test: "I moved the hot air balloon to town hall, and slept 3 days and it's still there"): the pad need not be
## near; she flies it straight home (fly_balloon.gd cuts the cruise short).
var fetching := false

func refusal() -> String:
	if not is_instance_valid(ship) or not ship.is_inside_tree(): return "No balloon"
	if active(): return "Somepony is already flying it"
	if not bool(ship.landed) or ship.velocity.length() > 0.2: return "The balloon is not resting on the ground"
	if not fetching and Vector2(ship.global_position.x - ship.home.origin.x, ship.global_position.z - ship.home.origin.z).length() > 60.0: return "The balloon is not at its pad"
	if ship.lift > 0.02 or ship.vent > 0.02 or ship.steering != Vector2.ZERO: return "Anon is flying the balloon"
	var hands: Node = ship.get("hands")
	if is_instance_valid(hands) and not (hands.get("held") as Dictionary).is_empty(): return "Anon is at the balloon's controls"
	return ""


func active() -> bool:
	return not state.is_empty() and state != "done"


## Up in the air (or on the way up or down), not on the pad.
func away() -> bool:
	return state in ["climb", "cruise", "return", "descend"]


static func fair_weather(tree: SceneTree) -> bool:
	var weather: Node = tree.get_first_node_in_group("weather") if tree != null else null
	return weather == null or str(weather.get("kind")) in FAIR


## Takes `pony` aboard and starts the flight: `seconds` of cruising (real time), home by `home_by`
## (card hours). False when she cannot board now.
func begin(pony: Node3D, pony_id: String, seconds: float, home_by: float, seed_value: int) -> bool:
	if not refusal().is_empty() or not is_instance_valid(pony): return false
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav == null or pony.get("_held") == true or pony.get("sleeping") == true: return false
	actor = pony
	id = pony_id
	turn_home_at = home_by
	cut_reason = ""
	lost = false
	player_rode = false
	ride = false   # a ride step sets it right after begin()
	visited = []
	max_town_distance = 0.0
	min_clearance = INF
	max_height = 0.0
	_clock = 0.0
	_target_y = NAN
	_home_ground = _ground(ship.home.origin)
	_find_clouds()
	_plan(seconds, seed_value)
	if ship.can_open_gate() and not bool(ship.gate_open): ship._set_gate(true)
	row = {"nav": nav, "nav_processing": nav.is_physics_processing(), "executors": []}
	var game: Node = ship.get("game")
	if is_instance_valid(game) and game.get("director") != null:
		var actions: Node = game.director.get("actions") as Node
		if actions != null:
			for executor: Node in actions.executors.values():
				if is_instance_valid(executor) and executor.actor == pony:
					row.executors.append({"node": executor, "processing": executor.is_physics_processing()})
					executor.set_physics_process(false)
	nav.stay()
	nav.wander_enabled = false
	nav.set_physics_process(false)
	ship.pilot = pony
	ship.autopilot = Vector3.ZERO
	pony.set_meta("balloon_passenger", ship)
	pony.set_meta("balloon_pilot", true)
	state = "boarding"
	# Up the ramp and in, as balloon.gd's _climb: a short eased hop to the helm.
	pony.motion_paused = true
	var from := pony.global_position
	var to := ship.to_global(PILOT_SPOT)
	# Facing the helm (the basket's +Z), as balloon.gd's looking_at faces a pony along a direction.
	var facing := Basis.looking_at(ship.global_basis.z, Vector3.UP)
	var size := float(pony.get("body_scale")) if pony.get("body_scale") != null else 1.0
	var tween := create_tween().bind_node(pony)
	tween.tween_method(func(t: float) -> void:
		pony.global_position = from.lerp(to, t) + Vector3.UP * sin(PI * t) * .45 * size, 0.0, 1.0, 1.1)
	tween.tween_callback(func() -> void:
		if state != "boarding" or actor != pony: return
		pony.motion_paused = false
		pony.reset_motion(Transform3D(facing, ship.to_global(PILOT_SPOT) + Vector3.UP * .02))
		pony.set_moving_support(ship)
		state = "preflight"; _clock = 0.0)
	return true


## Bring her home now (bedtime, the weather, her step ended): from the air she flies back and lands;
## before take-off she just climbs out.
func cut_short(reason: String) -> void:
	if not active(): return
	if cut_reason.is_empty(): cut_reason = reason
	match state:
		"boarding", "preflight": _land_now()
		"climb", "cruise": state = "return"


## What she is doing, for her current activity line (fly_balloon.gd) and debug.
func status_text() -> String:
	var aboard := " Anon is riding along in the basket with you." if _player_aboard() else ""
	match state:
		"boarding": return "Climbing into the hot-air balloon's basket to take it up"
		"preflight":
			if ride and not _player_aboard(): return "At the helm of the hot-air balloon on its pad with the gate open, waiting for Anon to climb into the basket for the ride he asked for"
			return "At the helm of the hot-air balloon on its pad, about to take off for a flight over Ponyville." + aboard
		"climb": return "Taking off in the hot-air balloon, rising %s; you are flying it yourself.%s" % [_where_now(), aboard]
		"cruise": return "%s, drifting %s, about %d m up.%s" % ["Giving Anon the balloon ride he asked for, flying it yourself" if ride else "Flying the hot-air balloon yourself", _where_now(), roundi(_height()), aboard]
		"return": return "Flying the hot-air balloon back home to land it on its pad%s, %s.%s" % [(" (" + cut_reason + ")") if not cut_reason.is_empty() else "", _where_now(), aboard]
		"descend": return "Bringing the hot-air balloon down onto its pad.%s" % aboard
		"landed", "leaving": return "Just landed the hot-air balloon on its pad after a flight over %s; climbing out." % _places_text()
	return ""


## The places she flew over, "the town" when nothing named stood out.
func _places_text() -> String:
	if visited.is_empty(): return "Ponyville"
	if visited.size() == 1: return visited[0]
	return ", ".join(visited.slice(0, visited.size() - 1)) + " and " + visited[visited.size() - 1]


func _player_aboard() -> bool:
	return is_instance_valid(ship) and ship.holds_player(ship.get("_player"))


func _height() -> float:
	var ground := _ground(ship.global_position)
	return ship.global_position.y - ground if is_finite(ground) else 0.0


static func _ground(at: Vector3) -> float:
	return WorldTerrain.instance.height_at(at) if is_instance_valid(WorldTerrain.instance) else NAN


# --- The route ---------------------------------------------------------------------------------

func _find_clouds() -> void:
	_clouds.clear()
	for node: Node in ship.get_tree().root.find_children("UsableCloudominium", "", true, false):
		if node is Node3D: _clouds.append(node as Node3D)


## Horizontal centre and keep-out radius of each Cloudominium now (it drifts).
func _cloud_zones() -> Array:
	var zones: Array = []
	var box: AABB = CLOUD_DRIFT.ABOARD
	var radius: float = Vector2(box.size.x, box.size.z).length() * 0.5 + CLOUD_MARGIN
	for cloud: Node3D in _clouds:
		if not is_instance_valid(cloud) or not cloud.is_inside_tree(): continue
		var centre: Vector3 = cloud.global_transform * box.get_center()
		zones.append([Vector2(centre.x, centre.z), radius])
	return zones


func _point_ok(p: Vector3, zones: Array) -> bool:
	if Vector2(p.x - TOWN.x, p.z - TOWN.z).length() > ROUTE_RADIUS + 1.0: return false
	var ground := _ground(p)
	if not is_finite(ground) or (is_finite(_home_ground) and ground > _home_ground + HIGH_GROUND): return false
	if ground < WorldLayout.sea_level() - 1.0: return false
	for zone: Array in zones:
		if Vector2(p.x, p.z).distance_to(zone[0]) < float(zone[1]) + 15.0: return false
	return true


func _segment_ok(a: Vector3, b: Vector3, zones: Array) -> bool:
	var steps := maxi(1, int(a.distance_to(b) / 25.0))
	for i: int in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var ground := _ground(p)
		if is_finite(ground) and is_finite(_home_ground) and ground > _home_ground + HIGH_GROUND + 10.0: return false
		for zone: Array in zones:
			if Vector2(p.x, p.z).distance_to(zone[0]) < float(zone[1]): return false
	return true


## A loop of waypoints round the town from the pad's side, about as long as the cruise time allows.
func _plan(seconds: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	route.clear()
	route_index = 0
	var pad: Vector3 = ship.home.origin
	var zones := _cloud_zones()
	var budget := maxf(300.0, seconds * CRUISE_SPEED)
	var a0 := atan2(pad.z - TOWN.z, pad.x - TOWN.x)
	var turn := 1.0 if rng.randf() < 0.5 else -1.0
	var angle := a0
	var last := pad
	var total := 0.0
	for i: int in 10:
		var chosen := Vector3.INF
		for attempt: int in 14:
			var a := angle + turn * rng.randf_range(0.45, 0.95)
			# Now and then right over the middle of the town, else out over the edges and fields.
			var r := rng.randf_range(40.0, 110.0) if (i == 1 and rng.randf() < 0.5) else rng.randf_range(ROUTE_MIN, ROUTE_RADIUS)
			var p := TOWN + Vector3(cos(a), 0.0, sin(a)) * r
			p.y = pad.y
			if not _point_ok(p, zones) or not _segment_ok(last, p, zones): continue
			chosen = p
			angle = a
			break
		if not chosen.is_finite():
			angle += turn * 0.6
			continue
		var leg := Vector2(chosen.x - last.x, chosen.z - last.z).length()
		var back := Vector2(chosen.x - pad.x, chosen.z - pad.z).length()
		if not route.is_empty() and total + leg + back > budget: break
		route.append(chosen)
		total += leg
		last = chosen
		if total > budget * 0.8: break
	if route.is_empty():
		# Nowhere clear to wander: once over the middle of the town and home.
		var over := TOWN.lerp(pad, 0.35)
		over.y = pad.y
		route.append(over)


# --- Flying ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active() or not is_instance_valid(ship): return
	_clock += delta
	if state != "boarding" and state != "leaving" and not _pilot_ok():
		_lose_pilot()
	if _player_aboard() and away(): player_rode = true
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = 2.0
		_checks()
	match state:
		"boarding":
			ship.autopilot = Vector3.ZERO
			if _clock > 6.0 and is_instance_valid(actor) and actor.motion_paused == false and state == "boarding": state = "preflight"
		"preflight":
			ship.autopilot = Vector3.ZERO
			var wait := PREFLIGHT
			# Anon close by but not in yet: a little longer, so he can climb aboard.
			if not _player_aboard() and _player_distance() < 20.0: wait = PREFLIGHT_MAX
			if ride and not _player_aboard():
				# His ride: no take-off without him; he did not come, so she climbs out again.
				if _clock > RIDE_WAIT: cut_short("Anon did not climb aboard")
				return
			if _clock < wait or _player_in_gateway() or (_talking() and not _player_aboard() and _clock < 120.0): return
			ship._set_gate(false)
			_heading = Vector3.ZERO
			state = "climb"; _clock = 0.0
		"climb", "cruise", "return":
			_fly(delta)
		"descend":
			_descend()
		"landed":
			ship.autopilot = Vector3.ZERO
			if _clock > LANDED_WAIT: _disembark()
	_measure()


## Bedtime coming, weather turning, or the cruise time used up: home.
func _checks() -> void:
	if state == "cruise" or state == "climb":
		if _card_hours() >= turn_home_at: cut_short("it is getting late")
		elif not fair_weather(get_tree()): cut_short("the weather is turning")
	elif state == "preflight":
		if not fair_weather(get_tree()): cut_short("the weather is turning")
		elif _card_hours() >= turn_home_at: cut_short("it is getting late")


func _card_hours() -> float:
	var clock: Node = get_node_or_null("/root/TimeOfDay")
	if clock == null: return 12.0
	var h := float(clock.hours)
	return h + 24.0 if h < 5.0 else h


func _talking() -> bool:
	var game: Node = ship.get("game")
	var director: Variant = game.get("director") if is_instance_valid(game) else null
	return is_instance_valid(director) and director is Node and (director as Node).has_method("holds_in_place") and bool((director as Node).call("holds_in_place", id))


func _player_body() -> Node3D:
	var inventory: Node = ship.get("inventory")
	return inventory.get("player_body") as Node3D if is_instance_valid(inventory) else null


func _player_distance() -> float:
	var body := _player_body()
	return body.global_position.distance_to(ship.global_position) if is_instance_valid(body) else INF


## Anon on the ramp or in the gateway: the gate does not shut on him.
func _player_in_gateway() -> bool:
	var body := _player_body()
	if not is_instance_valid(body): return false
	var p: Vector3 = ship.to_local(ship.player_feet(body))
	return absf(p.x) < 0.9 and p.z < -1.05 and p.z > -2.7 and p.y > -1.0 and p.y < 2.5


func _fly(delta: float) -> void:
	var here := ship.global_position
	var flat := Vector3(here.x, 0.0, here.z)
	var goal: Vector3 = ship.home.origin if state == "return" else route[mini(route_index, route.size() - 1)]
	var to_goal := Vector3(goal.x, 0.0, goal.z) - flat
	var distance := to_goal.length()
	if state != "return" and distance < WAYPOINT_REACHED:
		route_index += 1
		if route_index >= route.size(): state = "return"
		return
	if state == "return" and distance < 3.0 and ship.velocity.length() < 1.0:
		state = "descend"; _clock = 0.0
		return
	var height := _height()
	if state == "climb" and height > CRUISE_CLEARANCE - 6.0: state = "cruise"
	var wanted := to_goal.normalized() if distance > 0.01 else Vector3.ZERO
	# Round Rainbow Dash's cloud house, never through it.
	for zone: Array in _cloud_zones():
		var away := Vector2(here.x, here.z) - (zone[0] as Vector2)
		var reach := float(zone[1]) + 40.0
		if away.length() < reach and away.length() > 0.1:
			var push := (reach - away.length()) / 40.0
			wanted += Vector3(away.x, 0.0, away.y).normalized() * push * 2.0
	wanted = wanted.normalized() if wanted.length() > 0.01 else Vector3.ZERO
	if _heading == Vector3.ZERO: _heading = wanted
	elif wanted != Vector3.ZERO:
		# Gentle turns: the heading swings toward the wanted one at most TURN_RATE a second (faster
		# right over the pad, so she does not circle it).
		var rate := TURN_RATE * (3.0 if state == "return" and distance < 45.0 else 1.0)
		var angle := _heading.signed_angle_to(wanted, Vector3.UP)
		_heading = _heading.rotated(Vector3.UP, clampf(angle, -rate * delta, rate * delta)).normalized()
	var speed := CRUISE_SPEED
	if state == "return": speed *= clampf(distance / 30.0, 0.12, 1.0)
	# Up first: no drifting sideways until she is clear of the roofs round the pad.
	speed *= clampf((height - 8.0) / 14.0, 0.0, 1.0) if state == "climb" else 1.0
	var vertical := 0.0
	_sample_left -= delta
	if _sample_left <= 0.0 or not is_finite(_target_y):
		_sample_left = 0.25
		_target_y = _cruise_height(here)
	if _talking() and not _player_aboard():
		# Anon flew up to talk: she holds the balloon still for the chat.
		speed = 0.0
	vertical = clampf((_target_y - here.y) * 0.3, -SINK_RATE, CLIMB_RATE)
	if state == "climb": vertical = CLIMB_RATE if here.y < _target_y - 1.0 else vertical
	ship.autopilot = _heading * speed + Vector3.UP * vertical


## The height the basket should hold: clear of the ground and of anything standing under and ahead.
func _cruise_height(here: Vector3) -> float:
	var highest := -INF
	var ahead := _heading if _heading != Vector3.ZERO else Vector3.FORWARD
	var side := ahead.cross(Vector3.UP).normalized()
	var space := ship.get_world_3d().direct_space_state
	var excluded: Array[RID] = [ship.get_rid()]
	for name: String in ["Gate", "Ramp"]:
		var body := ship.get_node_or_null(name) as CollisionObject3D
		if body != null: excluded.append(body.get_rid())
	# Nothing riding in the basket counts as ground under it (she would climb away from herself).
	var riders: Array = [_player_body(), actor]
	for passenger: Dictionary in ship.passengers: riders.append(passenger.get("actor"))
	for rider: Variant in riders:
		if is_instance_valid(rider) and rider is CollisionObject3D: excluded.append((rider as CollisionObject3D).get_rid())
	var points: Array[Vector3] = []
	for d: float in LOOKAHEAD: points.append(here + ahead * d)
	points.append(here + side * 10.0); points.append(here - side * 10.0)
	points.append(here + ahead * 40.0 + side * 12.0); points.append(here + ahead * 40.0 - side * 12.0)
	_floor_y = -INF
	for p: Vector3 in points:
		var ground := _ground(p)
		if not is_finite(ground): continue
		highest = maxf(highest, ground + CRUISE_CLEARANCE)
		if p.distance_to(here) < 1.0: _floor_y = maxf(_floor_y, ground)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, maxf(here.y, ground) + 70.0, p.z), Vector3(p.x, ground - 1.0, p.z), 1 | (1 << 18), excluded))
		if not hit.is_empty():
			var top: float = (hit.position as Vector3).y
			highest = maxf(highest, top + OBSTACLE_CLEARANCE)
			if p.distance_to(here) < 1.0: _floor_y = maxf(_floor_y, top)
	if not is_finite(highest): return here.y
	if is_finite(_home_ground): highest = minf(highest, _home_ground + CEILING)
	return highest


func _descend() -> void:
	var here := ship.global_position
	var pad: Vector3 = ship.home.origin
	var off := Vector3(pad.x - here.x, 0.0, pad.z - here.z)
	var horizontal := (off * 0.4).limit_length(0.8)
	var ground: float = ship.get("_ground_height") if is_finite(float(ship.get("_ground_height"))) else _ground(here)
	var height: float = here.y - ground if is_finite(ground) else 0.0
	var vertical := -SINK_RATE if height > 8.0 else -TOUCHDOWN_RATE
	if off.length() > 4.0 and height < 6.0: vertical = 0.0   # line up over the pad first
	ship.autopilot = horizontal + Vector3.UP * vertical
	if (bool(ship.landed) or height < 0.12) and off.length() < 2.0:
		# Down: settled exactly on its spot, gate open.
		ship.velocity = Vector3.ZERO
		ship.autopilot = Vector3.ZERO
		if off.length() < 1.5: ship.global_transform = Transform3D(ship.home.basis, Vector3(pad.x, maxf(here.y, ground), pad.z))
		if ship.can_open_gate(): ship._set_gate(true)
		state = "landed"; _clock = 0.0
	elif _clock > 90.0:
		# Something under the basket kept it off the pad: down where it is, and done.
		ship.autopilot = Vector3(0.0, -TOUCHDOWN_RATE, 0.0)
		if bool(ship.landed) or height < 0.12:
			if ship.can_open_gate(): ship._set_gate(true)
			state = "landed"; _clock = 0.0


func _measure() -> void:
	if not away(): return
	var here := ship.global_position
	max_town_distance = maxf(max_town_distance, Vector2(here.x - TOWN.x, here.z - TOWN.z).length())
	if state in ["cruise", "return"]:
		var ground := _ground(here)
		if is_finite(ground): max_height = maxf(max_height, here.y - ground)
		if is_finite(_floor_y): min_clearance = minf(min_clearance, here.y - _floor_y)
	_where_left -= get_physics_process_delta_time()
	if _where_left <= 0.0:
		_where_left = 8.0
		_where = _where_words(here)
		var named := _where.trim_prefix("over ")
		if not named.begins_with("the outskirts") and not named.begins_with("the middle") and not named.is_empty() and named not in visited and visited.size() < 6:
			visited.append(named)


func _where_now() -> String:
	if _where.is_empty(): _where = _where_words(ship.global_position)
	return _where


## Where she is over, in her words: the nearest named place under her, else the town or its edges.
func _where_words(at: Vector3) -> String:
	var best := ""
	var best_d := INF
	var near := ""
	var near_d := INF
	for entry: Dictionary in PLACES.entries(get_tree()):
		var kind := str(entry.get("kind", ""))
		if kind != "landmark" and kind != PLACES.HOUSE_KIND: continue
		# Unbuilt or unnamed plots ("House plot_071") mean nothing to her.
		if str(entry.get("label", "")).begins_with("House plot"): continue
		var node: Variant = entry.get("node")
		if is_instance_valid(node) and (node == ship or ship.is_ancestor_of(node as Node)): continue
		var p: Vector3 = entry.get("position", Vector3.INF)
		if not p.is_finite(): continue
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		var reach := 30.0 if kind == PLACES.HOUSE_KIND else 60.0
		if d < reach and d < best_d: best = str(entry.label); best_d = d
		if kind == "landmark" and d < near_d: near = str(entry.label); near_d = d
	if not best.is_empty(): return "over " + best
	var from_town := Vector2(at.x - TOWN.x, at.z - TOWN.z).length()
	if from_town < 130.0: return "over the middle of Ponyville"
	if near_d < 160.0: return "over the outskirts of Ponyville, near " + near
	return "over the fields at the edge of Ponyville"


# --- Getting her in and out --------------------------------------------------------------------

func _pilot_ok() -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return false
	if actor.get("_held") == true: return false
	return ship.contains(actor.global_position, 0.6)


## She was taken out of the basket (picked up, streamed away): the balloon still comes home.
func _lose_pilot() -> void:
	if lost: return
	lost = true
	_release()
	if cut_reason.is_empty(): cut_reason = "she left the basket"
	if state in ["preflight", "landed"]:
		_finish()
	elif state != "descend":
		state = "return"
	# Nopony near enough to see it: straight back on its pad.
	if away() and _player_distance() > 150.0 and not _player_aboard():
		ship.global_transform = ship.home
		ship.velocity = Vector3.ZERO
		ship._set_gate(true, true)
		_finish()


## Before take-off: out again and done, no flight.
func _land_now() -> void:
	if state == "boarding" and is_instance_valid(actor):
		actor.motion_paused = false
	if ship.can_open_gate(): ship._set_gate(true)
	state = "landed"; _clock = LANDED_WAIT


## Down the ramp to its foot, as balloon.gd's _disembark, then let go.
func _disembark() -> void:
	state = "leaving"
	ship.autopilot = Vector3.ZERO
	if not is_instance_valid(actor) or lost:
		_finish(); return
	var pony := actor
	if pony.has_method("posture_status") and str(pony.posture_status().get("requested", "stand")) != "stand": pony.request_posture("stand")
	var from := [Vector3.ZERO]
	var tween := create_tween().bind_node(pony)
	tween.tween_interval(.4)
	tween.tween_callback(func() -> void:
		pony.set_moving_support(null); pony.motion_paused = true; from[0] = pony.global_position)
	tween.tween_method(func(t: float) -> void:
		pony.global_position = (from[0] as Vector3).lerp(ship._ramp_foot(), t) + Vector3.UP * sin(PI * t) * .3, 0.0, 1.0, .9)
	tween.tween_callback(func() -> void:
		pony.motion_paused = false
		pony.reset_motion(Transform3D(Basis.looking_at(-ship.global_basis.z, Vector3.UP), ship._ramp_foot() + Vector3.UP * .02))
		_release()
		_finish())


func _release() -> void:
	var pony := actor
	if is_instance_valid(pony):
		pony.motion_paused = false
		pony.set_moving_support(null)
		if pony.get_meta("balloon_passenger", null) == ship: pony.remove_meta("balloon_passenger")
		pony.remove_meta("balloon_pilot")
	var nav: Node = row.get("nav") if is_instance_valid(row.get("nav")) else null
	if nav != null:
		nav.set_physics_process(bool(row.get("nav_processing", true)))
		if str(nav.command_owner) == OWNER: nav.command_owner = ""
	for executor: Dictionary in row.get("executors", []):
		if is_instance_valid(executor.node): executor.node.set_physics_process(executor.processing)
	row = {}
	if is_instance_valid(ship) and ship.pilot == pony: ship.pilot = null


func _finish() -> void:
	if not row.is_empty(): _release()
	state = "done"
	if is_instance_valid(ship):
		ship.autopilot = Vector3.INF
		ship.pilot = null


## A loaded save moved the balloon (balloon.gd restore): no flight survives that; she is set down
## at the ramp foot.
func abort() -> void:
	if not active(): return
	if is_instance_valid(actor) and not lost and actor.is_inside_tree():
		actor.set_moving_support(null)
		actor.reset_motion(Transform3D(Basis.looking_at(-ship.global_basis.z, Vector3.UP), ship._ramp_foot() + Vector3.UP * .02))
	_finish()


func _exit_tree() -> void:
	if active(): _finish()
