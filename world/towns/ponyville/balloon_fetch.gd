extends Node
## The hot-air balloon goes home (2026-11-19 play test: "I moved the hot air balloon to town hall, and slept 3 days and
## it's still there"; reworked 2026-11-22: "Cherry Berry actually locate and return the balloon manually, either
## flying it back or walking it back as appropriate", without stranding Anon). Checked every CHECK_EVERY seconds:
##
## When: the balloon stands on the ground at least AWAY_FAR from its pad, empty, for AWAY_HOURS game hours.
## Never while Anon is in its basket, nor while he is far from Ponyville (TOWN_RADIUS) and near the balloon (STRAND_NEAR):
## then it may be his only way home, and it stays where he left it for as long as that holds.
## Who and how:
## - within RETRIEVE_RANGE of the pad, Cherry Berry goes for it herself (in daylight and fair weather, when her day
##   lets her): within WALK_RANGE she walks it home on its rope (walk_balloon.gd), farther she flies it (fly_balloon.gd);
##   if Anon is not within UNSEEN of the balloon or its pad, it is simply back on its pad, as if she had done it while
##   he was away;
## - farther than RETRIEVE_RANGE she does not trek out for it: it waits for Anon. Only after LONG_AWAY_HOURS, and only
##   while Anon is nowhere near it, is it back on its pad (somepony brought it home).
## Asking: Anon within ASK_RANGE of the balloon when she reaches it, she asks him in her own words whether he is still
## using it (conversation_director.gd queue_generated_intent) and waits for his reply; her model decides from what he
## says (mechanics.gd offers her [use: balloon_take_home], [use: balloon_leave_it] (not again for LEAVE_HOURS) and
## [use: balloon_wait] (LATER_HOURS) while she waits; 2026-11-22: "She should ask in her own words with the AI, and wait
## for a player response ... This is an AI-driven game"). No answer within ASK_SECONDS: she takes it home.
## Kept with the world (state): "balloon_away_since" and "balloon_hold_until" (game hours).

const KEY := "balloon_away_since"
const HOLD_KEY := "balloon_hold_until"
const AWAY_HOURS := 6.0
const AWAY_FAR := 60.0
const WALK_RANGE := 350.0
const RETRIEVE_RANGE := 700.0
const LONG_AWAY_HOURS := 72.0
const TOWN_RADIUS := 600.0
const STRAND_NEAR := 400.0
const UNSEEN := 160.0
const ASK_RANGE := 12.0
const ASK_SECONDS := 90.0
const LEAVE_HOURS := 24.0
const LATER_HOURS := 3.0
const CHECK_EVERY := 15.0
const RETRY_EVERY := 240.0
const PILOT_ID := "cherry_berry"
const PILOT := preload("res://world/vehicles/balloon/pony_pilot.gd")

var _wait := 20.0
var _asked := -INF
var _said := ""
var _answer := ""
var _asking := false
var _ask_left := 0.0

var _ship: Node3D
var _fly := false


static func attach(town: Node) -> void:
	if town.get_node_or_null("BalloonFetch") != null: return
	var node: Node = (load("res://world/towns/ponyville/balloon_fetch.gd") as GDScript).new()
	node.name = "BalloonFetch"
	town.add_child(node)


## Logged once each time the reason changes, so a balloon that is not being fetched says why.
func _note(text: String) -> void:
	if text == _said: return
	_said = text
	if not text.is_empty(): print("[balloon] " + text)


func _process(delta: float) -> void:
	if _asking:
		_ask_left -= delta
		if _ask_left <= 0.0:
			print("[balloon] Anon did not answer Cherry Berry: she takes the balloon home")
			_answered("take")
	_wait -= delta
	if _wait > 0.0: return
	_wait = CHECK_EVERY
	var game: Node = get_tree().current_scene
	if game == null or not ("balloon" in game) or game.get("title_active") == true: return
	var ship: Variant = game.get("balloon")
	var context: Variant = game.get("world_context")
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if not ship is Node3D or not is_instance_valid(ship) or not context is Object or tod == null: return
	var state: Variant = (context as Object).get("state")
	if not state is Dictionary: return
	_ship = ship as Node3D
	var home: Transform3D = _ship.get("home")
	var at: Vector3 = _ship.global_position
	var from_pad := Vector2(at.x - home.origin.x, at.z - home.origin.z).length()
	var pilot := PILOT.of(_ship as CharacterBody3D)
	var flying: bool = pilot != null and bool(pilot.call("active"))
	var on_rope := _ship.find_child("BalloonRope", true, false) != null or not _ship.is_physics_processing()
	if from_pad <= AWAY_FAR or flying or on_rope:
		state.erase(KEY)
		if from_pad <= AWAY_FAR: _note("")
		return
	var now := float(tod.get("day")) * 24.0 + float(tod.get("hours"))
	if not state.has(KEY):
		state[KEY] = now
		_note("away from its pad (%d m); Cherry Berry will see to it after %d hours" % [roundi(from_pad), int(AWAY_HOURS)])
		return
	var away := now - float(state[KEY])
	if not bool(_ship.get("landed")): _note("away and still in the air: left be"); return
	var player: Variant = game.get("player")
	var anon: Vector3 = (player as Node3D).global_position if player is Node3D and is_instance_valid(player) else Vector3.INF
	if player != null and _ship.has_method("holds_player") and bool(_ship.call("holds_player", player)):
		_note("Anon is in its basket: left be"); return
	# his way home: far from town and near the balloon, it stays with him
	if anon.is_finite() and anon.distance_to(home.origin) > TOWN_RADIUS and anon.distance_to(at) < STRAND_NEAR:
		_note("Anon is out with it, far from Ponyville: it stays where he left it"); return
	if float(state.get(HOLD_KEY, -INF)) > now: _note("Anon asked her to leave it for now"); return
	var unseen := not anon.is_finite() or (anon.distance_to(at) > UNSEEN and anon.distance_to(home.origin) > UNSEEN)
	if from_pad > RETRIEVE_RANGE:
		if away >= LONG_AWAY_HOURS and (not anon.is_finite() or anon.distance_to(at) > STRAND_NEAR):
			_home(state, "back on its pad: somepony brought it home from far away")
		else:
			_note("%d m from its pad, too far for Cherry Berry to go for it: it waits for Anon" % roundi(from_pad))
		return
	if away < AWAY_HOURS: return
	if unseen:
		_home(state, "back on its pad (Cherry Berry fetched it while Anon was away)")
		return
	var clock := Time.get_ticks_msec() / 1000.0
	if _fly:
		_fly = false
		_start_fly(); return
	if clock - _asked < RETRY_EVERY: return
	if not PILOT.fair_weather(get_tree()): _note("foul weather: Cherry Berry waits to fetch it"); return
	if float(get_node("/root/TimeOfDay").call("daylight")) < 0.5: _note("after dark: Cherry Berry waits for morning to fetch it"); return
	_asked = clock
	var runner: Node = get_tree().get_first_node_in_group("day_runner")
	if runner == null or not runner.has_method("inject_now"): return
	var walk := from_pad <= WALK_RANGE
	var step := {"action": "balloon_fetch", "handler": "walk_balloon", "target": "landmark:airballoon_01", "mode": "walk" if walk else "fly",
		"phrase": "fetch the hot-air balloon back to its pad", "reason": "to bring the balloon home", "minutes": 20.0, "hours": 1.5}
	if bool(runner.call("inject_now", PILOT_ID, step)):
		_note("Cherry Berry is going to %s the balloon home (%d m from its pad)" % ["walk" if walk else "fly", roundi(from_pad)])
	else:
		_note("Cherry Berry cannot go for the balloon just now (%s)" % _busy_why())


func _home(state: Dictionary, why: String) -> void:
	var home: Transform3D = _ship.get("home")
	_ship.call("restore", {"position": [home.origin.x, home.origin.y, home.origin.z], "yaw": home.basis.get_euler().y})
	state.erase(KEY)
	_note(why)


## After Anon's yes at the basket in "fly" mode (walk_balloon.gd): she takes it up from where she stands.
func fly_now() -> void:
	_fly = true; _wait = 0.5


func _start_fly() -> void:
	var runner: Node = get_tree().get_first_node_in_group("day_runner")
	if runner == null: return
	var step := {"action": "balloon_fetch", "handler": "fly_balloon", "target": "landmark:airballoon_01", "fetch": true, "ai": true,
		"phrase": "fly the hot-air balloon back to its pad", "reason": "to bring the balloon home", "minutes": 10.0, "hours": 0.5}
	if bool(runner.call("inject_now", PILOT_ID, step)): _note("Cherry Berry is flying the balloon home")


# ------------------------------------------------------------------ asking Anon

## She has reached the balloon: Anon close by is asked; else the answer is yes at once.
func begin_ask(tree: SceneTree, ship: Node3D) -> void:
	_answer = ""
	var game: Node = tree.current_scene
	var player: Variant = game.get("player") if game != null else null
	if not (player is Node3D and is_instance_valid(player) and (player as Node3D).global_position.distance_to(ship.global_position) <= ASK_RANGE):
		_answer = "take"; return
	_asking = true; _ask_left = ASK_SECONDS
	_say(game, "You have come to take the hot-air balloon back to its pad in town, and Anon is standing right by it. Ask him, briefly and warmly, whether he is still using it or whether you can take it home now, and wait for his answer.", "ask")
	_refresh_actions()


func answer() -> String:
	return _answer


func end_ask() -> void:
	_asking = false
	_refresh_actions()


## Cherry Berry's model is offered the answers only while she waits for one (mechanics.gd caches her actions).
func _refresh_actions() -> void:
	var mechanics: Node = (load("res://world/mechanics/mechanics.gd") as Script).call("of", get_tree()) if is_inside_tree() else null
	if mechanics != null and mechanics.has_method("invalidate"): mechanics.call("invalidate", PILOT_ID)


func asking() -> bool:
	return _asking


func _answered(choice: String) -> void:
	if not _asking: return
	_asking = false
	_answer = choice
	_refresh_actions()
	var game: Node = get_tree().current_scene
	var context: Variant = game.get("world_context") if game != null else null
	var state: Variant = (context as Object).get("state") if context is Object else null
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	var now := float(tod.get("day")) * 24.0 + float(tod.get("hours")) if tod != null else 0.0
	if state is Dictionary and choice in ["leave", "later"]: state[HOLD_KEY] = now + (LEAVE_HOURS if choice == "leave" else LATER_HOURS)
	print("[balloon] Cherry Berry and the balloon: %s" % {"take": "she takes it home", "leave": "she leaves it with Anon for now", "later": "she will come back for it in a few hours"}[choice])


func _say(game: Node, intent: String, tag: String) -> void:
	var director: Node = game.get("director") if game != null else null
	if director == null or not director.has_method("queue_generated_intent"): return
	var valid := func() -> bool: return is_instance_valid(self)
	director.call("queue_generated_intent", PILOT_ID, intent, "balloon_fetch:%s:%d" % [tag, Time.get_ticks_msec()], valid, Callable(), false, true)


## Why day_runner.inject_now refused her, for the log.
func _busy_why() -> String:
	var actor: Node3D = _pilot_body()
	if actor == null: return "she is not in Ponyville, or has no day today"
	if actor.get("_held"): return "Anon is holding her"
	var nav: Node = actor.get_node_or_null("Navigator")
	var owner := str(nav.get("command_owner")) if nav != null else ""
	if not owner.is_empty() and not owner.begins_with("day:") and not owner.begins_with("life:") and not owner.begins_with("social:"):
		return "she is busy with something from a chat (%s)" % owner
	return "her day, or she is not free"


func _pilot_body() -> Node3D:
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var actions: Variant = director.get("actions") if director != null else null
	var executors: Variant = (actions as Object).get("executors") if actions is Object else null
	var executor: Node = (executors as Dictionary).get(PILOT_ID) if executors is Dictionary else null
	var actor: Variant = executor.get("actor") if is_instance_valid(executor) else null
	return actor as Node3D if actor is Node3D and is_instance_valid(actor) else null


# ------------------------------------------------------------------ her model's choice
# (2026-11-22 play test: Anon told Cherry Berry where the balloon was; she said she would walk it home, ran there with
# a plain go_to and stood by it, telling him she would walk it home, and never did: nothing let her model start it.)

## The balloon as her model sees it (mechanics.gd): {} when there is nothing for her to fetch, else {"metres", "walk"}.
## Anon telling her or asking her is enough: no AWAY_HOURS wait.
func fetchable() -> Dictionary:
	var game: Node = get_tree().current_scene if is_inside_tree() else null
	var ship: Variant = game.get("balloon") if game != null and "balloon" in game else null
	if not ship is Node3D or not is_instance_valid(ship): return {}
	var body := ship as Node3D
	var home: Transform3D = body.get("home")
	var at: Vector3 = body.global_position
	var from_pad := Vector2(at.x - home.origin.x, at.z - home.origin.z).length()
	if from_pad <= AWAY_FAR or from_pad > RETRIEVE_RANGE or not bool(body.get("landed")): return {}
	if not body.is_physics_processing() or body.find_child("BalloonRope", true, false) != null: return {}
	var pilot := PILOT.of(body as CharacterBody3D)
	if pilot != null and bool(pilot.call("active")): return {}
	var player: Variant = game.get("player")
	if player != null and body.has_method("holds_player") and bool(body.call("holds_player", player)): return {}
	return {"metres": roundi(from_pad), "walk": from_pad <= WALK_RANGE}


## [use: balloon_fetch]: she goes for it now, as her own day step ("ai": it starts while she is still talking with Anon).
func fetch_now(tree: SceneTree) -> Dictionary:
	var away := fetchable()
	if away.is_empty(): return {"status": "failed", "reason": "The balloon is not out waiting to be brought home"}
	if not PILOT.fair_weather(tree): return {"status": "failed", "reason": "The weather is too rough to handle the balloon"}
	var director: Node = tree.get_first_node_in_group("conversation_director")
	var actions: Variant = director.get("actions") if director != null else null
	var executors: Variant = (actions as Object).get("executors") if actions is Object else null
	var executor: Node = (executors as Dictionary).get(PILOT_ID) if executors is Dictionary else null
	if is_instance_valid(executor) and not (executor.get("movement") as Dictionary).is_empty() and executor.has_method("_end_move"):
		executor.call("_end_move", "completed", "Off to bring the balloon home")
	var nav: Node = executor.get("navigator") if is_instance_valid(executor) else null
	if is_instance_valid(nav) and not str(nav.get("command_owner")).begins_with("day:"): nav.set("command_owner", "")
	var runner: Node = tree.get_first_node_in_group("day_runner")
	var walk: bool = away.walk
	var step := {"action": "balloon_fetch", "handler": "walk_balloon", "target": "landmark:airballoon_01", "mode": "walk" if walk else "fly",
		"phrase": "fetch the hot-air balloon back to its pad", "reason": "because Anon told her where it was", "minutes": 20.0, "hours": 1.5,
		"ai": true, "asked": true}
	if runner == null or not bool(runner.call("inject_now", PILOT_ID, step)):
		return {"status": "failed", "reason": "Not possible right now (%s)" % _busy_why()}
	var game: Node = tree.current_scene
	var context: Variant = game.get("world_context") if game != null else null
	var state: Variant = (context as Object).get("state") if context is Object else null
	if state is Dictionary: (state as Dictionary).erase(HOLD_KEY)
	_asked = Time.get_ticks_msec() / 1000.0
	print("[balloon] Cherry Berry chose to %s the balloon home (%d m from its pad)" % ["walk" if walk else "fly", int(away.metres)])
	return {"status": "completed", "reason": "Going to the balloon to %s it home" % ("walk" if walk else "fly")}
