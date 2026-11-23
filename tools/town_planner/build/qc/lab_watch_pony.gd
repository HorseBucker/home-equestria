extends Node
## Quality control: what one pony's day sends her to do, and where she is, from a given hour (2026-11-19: Big Mac kept
## turning up in the schoolyard). Prints WATCH lines each time her step or target changes, and her place every 20 s.
##   godot --xr-mode off --path <project> -- --new-game --skip-title --lab res://tools/town_planner/build/qc/lab_watch_pony.gd [--id big_mcintosh] [--hour 7.5] [--seconds 300]
var game: Node


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"): await (arrival as Node).skip_to_free_home()
	var args := OS.get_cmdline_user_args()
	var id := args[args.find("--id") + 1] if "--id" in args else "big_mcintosh"
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null and "--hour" in args: tod.hours = float(args[args.find("--hour") + 1])
	var seconds := float(args[args.find("--seconds") + 1]) if "--seconds" in args else 300.0
	var runner: Node = get_tree().get_first_node_in_group("day_runner")
	var population: Node = get_tree().get_first_node_in_group("pony_populations")
	var last := ""
	var started := Time.get_ticks_msec()
	var next_place := 0.0
	while (Time.get_ticks_msec() - started) / 1000.0 < seconds:
		await get_tree().create_timer(0.5).timeout
		var card: Dictionary = runner.get("cards").get(id, {}) if runner != null else {}
		var step: Variant = card.get("step")
		var text := "%s" % (JSON.stringify({"action": step.get("action"), "target": step.get("target"), "goal": step.get("goal"), "start": step.get("start")}) if step is Dictionary else "no step")
		var actor: Variant = population.get("live").get(id, {}).get("actor") if population != null else null
		var at: Vector3 = (actor as Node3D).global_position if actor is Node3D and is_instance_valid(actor) else Vector3.INF
		var where := "live at %s" % at if at.is_finite() else "not in the world (essence)"
		if text != last:
			print("WATCH %.1f h  %s  | %s | intent %s" % [tod.hours if tod != null else -1.0, text, where, (actor as Node).get_meta("life_intent", "") if actor is Node and is_instance_valid(actor) else ""])
			last = text
		var t := (Time.get_ticks_msec() - started) / 1000.0
		if t >= next_place:
			next_place = t + 20.0
			var essence: Variant = population.call("candidate_position", id) if population != null else null
			var life: Variant = population.get("life") if population != null else null
			var info: Variant = (life as Object).call("debug_resident", id) if life is Object else {}
			print("WATCH %.1f h  place: %s, life %s, life says %s" % [tod.hours if tod != null else -1.0, where, essence, JSON.stringify(info)])
	var core: Variant = (population.get("life") as Object).get("core") if population != null and population.get("life") is Object else null
	if core is Object:
		var st: Dictionary = (core as Object).get("state")
		var r: Dictionary = st.residents.get(id, {})
		var o := Vector3(r.position[0], r.position[1], r.position[2]) if r.has("position") else Vector3.ZERO
		var same := 0; var near := 0; var enabled := 0; var reserved := 0
		for pid: String in st.places:
			var pl: Dictionary = st.places[pid]
			if pl.region != r.get("region"): continue
			same += 1
			if pl.enabled: enabled += 1
			if not pl.reserved.is_empty(): reserved += 1
			if o.distance_to(Vector3(pl.position[0], pl.position[1], pl.position[2])) < 180: near += 1
		print("WATCH wander_stops %s decisions %s place %s activity %s" % [r.get("wander_stops"), r.get("decisions"), r.get("place"), r.get("activity")])
		print("WATCH resident region %s home_region %s; places in region %d (enabled %d, reserved %d, within 180 m %d); bounds %s; leased %s" % [r.get("region"), r.get("home_region"), same, enabled, reserved, near, (core as Object).get("town_bounds"), ((core as Object).get("_leases") as Dictionary).has(id) if (core as Object).get("_leases") is Dictionary else "?"])
	print("WATCH done")
	get_tree().quit()
