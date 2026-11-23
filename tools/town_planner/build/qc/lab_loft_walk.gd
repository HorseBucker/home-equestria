extends Node
## Twilight (at --scale, default 1.35, JRHNBR) set at her bed's approach in the Golden Oak loft, sent down to the
## ground floor's middle, then back to her bed's approach: where she is each second. Prints WALK lines; quits.
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
	game.get("player").global_position = Vector3(-6, -11, -250)
	await _wait(25.0)
	var inside: Node3D = get_tree().root.find_child("LibraryInterior", true, false)
	var population: Node = get_tree().get_first_node_in_group("pony_populations")
	var live: Dictionary = population.get("live")
	var id := "twilight_sparkle" if live.has("twilight_sparkle") else str(live.keys()[0])
	print("WALK pony ", id)
	var actor: Node3D = live[id].get("actor")
	var scale := float(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--scale") + 1]) if "--scale" in OS.get_cmdline_user_args() else 1.35
	if actor.has_method("set_body_scale"): actor.call("set_body_scale", scale)
	else: actor.set("body_scale", scale)
	var approach: Node3D = inside.find_child("TwilightBedApproach", true, false)
	actor.call("reset_motion", Transform3D(actor.global_basis, approach.global_position + Vector3.UP * 0.1))
	await _wait(3.0)
	var nav: Node = actor.get_node("Navigator"); nav.set("command_owner", "lab"); nav.set("wander_enabled", false)
	for leg: Array in [["down", inside.to_global(Vector3(0, 0, 2.5))], ["up", approach.global_position]]:
		nav.call("go_to", leg[1], 1)
		var t0 := Time.get_ticks_msec()
		for i in 60:
			await _wait(1.0)
			var p := actor.global_position
			if i % 3 == 0: print("WALK %s %2ds at %s, %.1f m to go, state %s" % [leg[0], i, p.round(), p.distance_to(leg[1]), nav.get("state")])
			if p.distance_to(leg[1]) < 0.8: print("WALK %s arrived in %d s" % [leg[0], (Time.get_ticks_msec() - t0) / 1000]); break
	get_tree().quit()
