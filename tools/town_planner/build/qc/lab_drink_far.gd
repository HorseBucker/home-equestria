extends Node
## [use: fountain] for a pony ~15 m from the fountain (2026-11-21: Derpy agreed to a drink and never walked over):
## calls fountain_visit.gd drink_now as mechanics.gd does, then logs each second where she is, who steers her and
## whether the visit and the drinker are there. Prints DRINK lines; quits.
const VISIT := preload("res://world/life/day/actions/fountain_visit.gd")
var game: Node

func _ready() -> void:
	_go.call_deferred()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _go() -> void:
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.25)
	var water := get_tree().get_first_node_in_group("town_fountains") as Node3D
	var fountain := water.get_parent() as Node3D
	game.get("player").global_position = fountain.global_position + Vector3(12.0, 0.5, 8.0)
	await _wait(25.0)
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var executors: Dictionary = (director.get("actions") as Object).get("executors")
	var want := OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--pony") + 1] if "--pony" in OS.get_cmdline_user_args() else "derpy_hooves"
	var id := want if executors.has(want) else ""
	if id == "":
		for key: String in executors: if is_instance_valid(executors[key]) and is_instance_valid(executors[key].get("actor")): id = key; break
	var executor: Node = executors[id]
	var actor: Node3D = executor.get("actor")
	var spot := fountain.global_position + Vector3(14.0, 0, 6.0)
	if actor.has_method("reset_motion"): actor.call("reset_motion", Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.2))
	else: actor.global_position = spot + Vector3.UP * 0.2
	await _wait(4.0)
	var nav: Node = executor.get("navigator")
	print("DRINK %s owner before: '%s', %.1f m from the fountain" % [id, nav.get("command_owner"), actor.global_position.distance_to(fountain.global_position)])
	var result: Dictionary = VISIT.drink_now(get_tree(), id)
	print("DRINK drink_now -> ", result)
	var last := ""
	for i in 300:
		await _wait(0.2)
		if not is_instance_valid(actor): print("DRINK she is gone"); break
		var drinker := actor.find_child("FountainDrink", true, false)
		if drinker != null: set_meta("drank", true)
		elif has_meta("drank") and not has_meta("asked"):
			set_meta("asked", true); print("DRINK her model sees: ", executor.call("context_lines")); print("DRINK again -> ", VISIT.drink_now(get_tree(), id), " | meta ", actor.get_meta("fountain_drank_at", "none"))
		var line := "owner '%s' visit %s drinker %s stage %s" % [nav.get("command_owner"), actor.get_node_or_null("FountainVisit") != null, drinker != null, drinker.get("stage") if drinker else "-"]
		if line != last and drinker != null and str(drinker.get("stage")) == "settle": print("DRINK left to the rim plan: %.3f m, kind %s" % [float(drinker.call("_remaining")), drinker.get("kind")])
		if line != last: print("DRINK %5.1fs %.2f m | %s" % [i * 0.2, actor.global_position.distance_to(fountain.global_position), line]); last = line
	get_tree().quit()
