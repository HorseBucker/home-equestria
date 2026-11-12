extends "res://world/ai/pony_action_executor.gd"
## Watch Party: [watch_tv] (res://mods/watch_party/watch_invite.gd carries it out).
## - capabilities(): offers it while Anon has a television set up.
## - submit(): a [sit], [lie_down], [stay] or follow of Anon in a later reply leaves a watch be
##   instead of replacing it (watch_invite.gd keeps(); Luna, playtest 2026-11-03).
## - _physics_step(): while she is on her way to a set or watching, watch_invite.gd step() moves her.
##   The game's own step still runs first with the watch set aside, for its clock and her gaze;
##   then the same checks the game makes before any ground movement (being held or petted, flying).
##   While the watch is an ordinary follow of Anon (no set near yet), the game walks it as usual.
## - _end_move(): a watch that ends for any reason is tidied up (watch_invite.gd ended()).
## Applied by the game (mod.json "extends"); see res://mods/watch_party/hooks.gd.

## Marks this script as Watch Party's extension of the game script (hooks.gd).
const WATCH_PARTY_PATH := "res://world/ai/pony_action_executor.gd"
const WATCH_PARTY_LOADER := preload("res://mods/watch_party/hooks.gd")

const WATCH_PARTY_INVITE := "res://mods/watch_party/watch_invite.gd"
const WATCH_PARTY_TICK := 0.2
var _watch_party_tick := 0.0

static func _watch_party_on(m: Dictionary) -> bool:
	return not m.is_empty() and (m.get("type") == "watch_tv" or m.has("watch"))

func capabilities() -> Array:
	var result: Array = super()
	if not is_instance_valid(actor) or not actor.has_method("request_posture"): return result
	if not is_instance_valid(navigator) or not navigator.has_method("command_destination"): return result
	if bool(load(WATCH_PARTY_INVITE).call("offered", actor)):
		result.append("watch_tv")
		if not "cancel" in result: result.append("cancel")
	return result

func submit(actions: Array, targets: Dictionary, turn: int, ai_origin := false) -> void:
	if turn >= _latest_turn and _watch_party_on(movement):
		var invite: Script = load(WATCH_PARTY_INVITE)
		var rest: Array = []
		for source: Variant in actions:
			if source is Dictionary and bool(invite.call("keeps", movement, source)):
				var key := str(turn) + "/" + str((source as Dictionary).get("id", ""))
				if not _seen.has(key):
					_seen[key] = true
					_report((source as Dictionary).duplicate(true), "completed", "Already settling in to watch the television")
				continue
			rest.append(source)
		actions = rest
	super(actions, targets, turn, ai_origin)

func _physics_step(delta: float) -> void:
	if not _watch_party_on(movement):
		super(delta)
		return
	var invite: Script = load(WATCH_PARTY_INVITE)
	if str(movement.get("type")) == "follow":
		# Going along with Anon until a set is near: the game walks the follow; a set in reach
		# turns it back into a watch.
		_watch_party_tick += delta
		if _watch_party_tick >= WATCH_PARTY_TICK:
			var step_dt := _watch_party_tick
			_watch_party_tick = 0.0
			if _watch_party_free() and bool(invite.call("step", self, movement, step_dt)): return
		super(delta)
		return
	var watch: Dictionary = movement
	var dt := _tick + delta
	movement = {}
	super(delta)
	if not is_instance_valid(actor) or is_queued_for_deletion(): return
	movement = watch
	set_physics_process(true)
	if dt < WATCH_PARTY_TICK: return
	if not is_instance_valid(navigator):
		_end_move("failed", "Navigator unavailable"); return
	if str(navigator.command_owner) != str(movement.id):
		_end_move("cancelled", "Movement superseded by another owner"); return
	if not _watch_party_free(): return
	invite.call("step", self, movement, dt)

## The game's own holds on ground movement (pony_action_executor.gd _physics_step): held, petted
## or otherwise handled pauses the watch; a flying pony lands first.
func _watch_party_free() -> bool:
	var interruption: String = actor.action_interruption_reason() if actor.has_method("action_interruption_reason") else ""
	if interruption != "":
		if not _paused:
			navigator.stay()
			_last_goal = Vector3.INF
		_paused = true
		_report(movement, "blocked", interruption + "; intention retained")
		return false
	_paused = false
	if actor.get("flight") != null and actor.flight.active():
		if not movement.get("land_asked", false):
			movement.land_asked = true
			actor.flight.land()
		_report(movement, "blocked", "Landing before ground movement")
		return false
	return true

func _end_move(status: String, reason: String, routine := false) -> void:
	var was: Dictionary = movement
	super(status, reason, routine)
	if _watch_party_on(was): load(WATCH_PARTY_INVITE).call("ended", self, was, status + ": " + reason)
