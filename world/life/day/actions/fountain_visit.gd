extends Node
## A drink at the fountain after a trip the model asked for ends there (2026-11-18 play test: Twilight asked Anon
## to walk with her, "I was heading for the fountain anyway", led him to it and talked of the cold water, but never
## drank: a [lead] or [go_to] to the fountain only walks there). When such a trip completes at the fountain,
## pony_action_coordinator.gd starts this: the day step drink_at_fountain.gd run on its own (its spot, its turn to
## the water, fountain_drinker.gd's drink, her size measured against the rim), ticked here every half second as the
## day runner would. Afterwards she stands resting as after any model's trip ("rest_after_command", with its time
## limit started again, pony_action_executor.gd _hold_rest), so a chat with Anon goes on where it was.
## Refused quietly (nothing happens) when the drink step refuses: no free spot, too small, someone else steering her.

const DRINK := preload("res://world/life/day/actions/drink_at_fountain.gd")
const NAME := "FountainVisit"
## Model trips to these places end with a drink.
const PLACES := ["landmark:fountain_01"]
const TICK := 0.5
const REST_OWNER := "rest_after_command"
## The walk grid round the basin may still be filling in as she arrives (it is sampled in the background): a refused
## start ("No free spot") is tried again every second this many times.
const START_TRIES := 8

var _action: RefCounted
var _ctx: Dictionary = {}
var _executor: Node
var _wait := 0.0
var _tries := 0


## Near enough the fountain for [use: fountain] to be offered (mechanics.gd): this many metres from its middle.
const NEAR := 25.0


static func near(tree: SceneTree, actor: Node3D) -> bool:
	var water: Node3D = DRINK.fountain_near(tree, actor.global_position)
	return water != null and Vector2(water.global_position.x - actor.global_position.x, water.global_position.z - actor.global_position.z).length() < NEAR


## [use: fountain]: she stops what the model had her doing (following Anon, standing with him) and goes to drink.
static func drink_now(tree: SceneTree, id: String) -> Dictionary:
	var director: Node = tree.get_first_node_in_group("conversation_director")
	var actions: Variant = director.get("actions") if director != null else null
	var executors: Variant = (actions as Object).get("executors") if actions is Object else null
	var executor: Node = (executors as Dictionary).get(id) if executors is Dictionary else null
	if not is_instance_valid(executor): return {"status": "failed", "reason": "Not possible right now"}
	var actor: Variant = executor.get("actor")
	if not actor is Node3D or not near(tree, actor as Node3D): return {"status": "failed", "reason": "The fountain is not near you"}
	# (2026-11-21 play test: Derpy sipped five times over, a new drink each time the model chose [use: fountain] again,
	# and said she never had a drop): a pony who drank in the last DRINK_AGAIN game hours is told so
	var since := hours_since_drink(tree, actor as Node3D)
	if since < DRINK_AGAIN:
		return {"status": "failed", "reason": "You just had a drink at the fountain %d minutes ago; you are not thirsty" % int(since * 60.0)}
	if (actor as Node3D).get_node_or_null(NAME) != null or (actor as Node3D).find_child("FountainDrink", true, false) != null:
		return {"status": "completed", "reason": "Already going for a drink"}
	if not (executor.get("movement") as Dictionary).is_empty() and executor.has_method("_end_move"):
		executor.call("_end_move", "completed", "Off for a drink at the fountain")
	var nav: Node = executor.get("navigator")
	if is_instance_valid(nav) and str(nav.get("command_owner")) not in ["", REST_OWNER] and not str(nav.get("command_owner")).begins_with("day:"):
		return {"status": "failed", "reason": "Busy; cannot go to the fountain right now"}
	# Her day plan takes the drink as its next step and walks her there (2026-11-21 play test: Derpy said yes to a drink
	# and never moved: borrowing her day step's navigator left her own day step steering her, standing where it was).
	# The finished step goes into the story journal, so she knows she drank.
	var runner: Node = tree.get_first_node_in_group("day_runner")
	if is_instance_valid(nav) and str(nav.get("command_owner")) == REST_OWNER: nav.set("command_owner", "")
	if runner != null and runner.has_method("inject_now") and bool(runner.call("inject_now", id, DRINK_STEP)):
		print("[ai] %s goes for a drink at the fountain" % id)
		return {"status": "completed", "reason": "Walking to the fountain for a drink"}
	if is_instance_valid(nav) and (str(nav.get("command_owner")).begins_with("day:") or str(nav.get("command_owner")) == ""):
		nav.set("command_owner", REST_OWNER)      # her own day step gives way, as to any model command
	if not after_trip(executor, id, PLACES[0]): return {"status": "failed", "reason": "No free spot at the fountain"}
	return {"status": "completed", "reason": "Walking to the fountain for a drink"}


## The day step [use: fountain] puts first in her day (day_tables.json drink_fountain).
## "ai": her model asked for it, so it starts while she is still talking with Anon (a day step waits for the end of a
## chat otherwise: 2026-11-21 play test, Cherry Berry and Fluttershy never went, Twilight only once Anon walked off).
const DRINK_STEP := {"action": "drink_fountain", "handler": "drink_at_fountain", "target": "fountain", "minutes": 4.0, "hours": 1.0,
	"phrase": "have a drink at the {target}", "reason": "because Anon asked her along", "ai": true}
## Not again within this many game hours of the last drink.
const DRINK_AGAIN := 1.5
const DRANK_META := "fountain_drank_at"


## Game hours since she last finished a drink at the fountain (INF if never this session).
static func hours_since_drink(tree: SceneTree, actor: Node3D) -> float:
	var clock: Node = tree.root.get_node_or_null("TimeOfDay")
	if clock == null or not actor.has_meta(DRANK_META): return INF
	return float(clock.get("day")) * 24.0 + float(clock.get("hours")) - float(actor.get_meta(DRANK_META))


## A drink finished (drink_at_fountain.gd): remembered on her for hours_since_drink, and told to her model as the
## outcome of an action (pony_action_executor.gd context_lines: the last four outcomes are in every prompt she gets;
## the story journal alone was not enough: a few lines of talk push a step out of what her prompt holds, and Twilight
## said she had not had a drop just after drinking).
static func mark_drank(tree: SceneTree, actor: Node3D, id := "") -> void:
	var clock: Node = tree.root.get_node_or_null("TimeOfDay")
	if clock != null and is_instance_valid(actor): actor.set_meta(DRANK_META, float(clock.get("day")) * 24.0 + float(clock.get("hours")))
	tell(tree, id, "completed", "You drank from the fountain just now: a few cool sips. You are not thirsty any more")


## An outcome told to her model as the result of her [use: fountain] (status "completed" or "failed").
static func tell(tree: SceneTree, id: String, status: String, text: String) -> void:
	if id.is_empty(): return
	var director: Node = tree.get_first_node_in_group("conversation_director")
	var actions: Variant = director.get("actions") if director != null else null
	var executors: Variant = (actions as Object).get("executors") if actions is Object else null
	var executor: Node = (executors as Dictionary).get(id) if executors is Dictionary else null
	if is_instance_valid(executor) and executor.has_method("_report"):
		executor.call("_report", {"id": "fountain-drink", "type": "use"}, status, text)


## Start a drink for the executor's pony after a trip to `place`; false when there is nothing to do.
static func after_trip(executor: Node, id: String, place: String) -> bool:
	if not PLACES.has(place) or not is_instance_valid(executor): return false
	var actor: Variant = executor.get("actor")
	var nav: Variant = executor.get("navigator")
	if not actor is Node3D or not is_instance_valid(nav) or (actor as Node3D).get_node_or_null(NAME) != null: return false
	# only a pony standing free after the trip: not one already given something else to do
	if str((nav as Node).get("command_owner")) not in ["", REST_OWNER] or not (executor.get("movement") as Dictionary).is_empty(): return false
	var visit: Node = (load("res://world/life/day/actions/fountain_visit.gd") as GDScript).new()
	visit.name = NAME
	(actor as Node3D).add_child(visit)
	return bool(visit.call("_begin", executor, id))


func _begin(executor: Node, id: String) -> bool:
	_executor = executor
	_ctx = {"id": id, "actor": executor.get("actor"), "nav": executor.get("navigator"), "step": {"target": "fountain"},
		"tree": get_tree()}
	return _try_start()


## The drink step's start; false (and gone) once it has refused START_TRIES times or for another reason.
func _try_start() -> bool:
	_tries += 1
	var action: RefCounted = DRINK.new()
	if bool(action.call("start", _ctx)):
		_action = action
		print("[ai] %s has a drink at the fountain after the walk" % str(_ctx.id))
		return true
	var why := str(action.get("reason"))
	if why == "No free spot at the fountain" and _tries < START_TRIES and is_instance_valid(_ctx.get("nav")) and str(_ctx.nav.get("command_owner")) in ["", REST_OWNER]:
		_wait = 1.0
		return true
	print("[ai] %s skips a drink at the fountain: %s" % [str(_ctx.id), why])
	queue_free()
	return false


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0: return
	_wait = TICK
	if _action == null:
		if not is_queued_for_deletion(): _try_start()
		return
	var nav: Node = _ctx.get("nav")
	# Anon or a new command took her over (the step's own checks end it too): stop where she is.
	if not is_instance_valid(nav) or not is_instance_valid(_ctx.get("actor")) or str(nav.get("command_owner")) != "day:" + str(_ctx.id):
		_end(false); return
	var result := str(_action.call("tick", _ctx, TICK))
	if result != "running": _end(true)


func _end(finished: bool) -> void:
	var nav: Node = _ctx.get("nav")
	if _action != null:
		if finished: _action.call("release", _ctx)
		else: _action.call("stop", _ctx)
	_action = null
	# back to resting after the model's trip (only if nopony else has taken her navigator meanwhile)
	if finished:
		# (the day runner journals its own steps; this drink ran outside it: the same line, so she knows she drank)
		var runner: Node = get_tree().get_first_node_in_group("day_runner") if is_inside_tree() else null
		var context: Variant = runner.get_parent().get("world_context") if runner != null and runner.get_parent() != null else null
		if context is Node and is_instance_valid(context) and (context as Node).has_method("record"):
			context.record("day", "%s finished: have a drink at the fountain." % str(_ctx.id).replace("_", " ").capitalize(), [str(_ctx.id)], [str(_ctx.id)])
	if finished and is_instance_valid(nav) and str(nav.get("command_owner")) == "":
		nav.set("command_owner", REST_OWNER)
		nav.set("wander_enabled", false)
		if is_instance_valid(_executor) and _executor.has_method("_hold_rest"): _executor.call("_hold_rest")
	queue_free()


func _exit_tree() -> void:
	if _action != null: _action.call("stop", _ctx)
	_action = null
