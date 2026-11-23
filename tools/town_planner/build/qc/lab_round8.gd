extends Node
## Round 8 checks (2026-11-18) in the running game:
## - the chest keeps an item the way it keeps a mod's (a loan set out in CHEST_HOME): saved, valid, never a body in
##   the world, counted among his things, back into the briefcase on Take;
## - the fountain's collision is round, and a pony a model's trip leaves at the fountain has a drink
##   (fountain_visit.gd);
## - the Board Games table's spot (only when that mod is loaded) and the grass footprint.
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/lab_round8.gd
## Prints R8 lines; quits.
const CHEST := preload("res://world/props/town_chest/chest_store.gd")
const VISIT := preload("res://world/life/day/actions/fountain_visit.gd")
var game: Node


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		await get_tree().process_frame


func _go() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void: print("R8 watchdog"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"): await (arrival as Node).skip_to_free_home()
	await _wait(3.0)
	await _chest()
	await _fountain()
	var table := game.find_child("PlazaGameTable", true, false) as Node3D
	print("R8 chess table ", table.global_position if table != null else "not loaded (Board Games mod absent)")
	print("R8 done")
	get_tree().quit()


func _chest() -> void:
	var player: Node3D = game.get("player")
	var chest := get_tree().get_first_node_in_group("town_chests") as Node3D
	print("R8 chest node ", chest.global_position if chest != null else "MISSING")
	if chest == null: return
	player.global_position = chest.global_position + Vector3(0, 0.3, 1.5)
	await _wait(4.0)
	var store: RefCounted = CHEST.briefcase(game)
	var id := "goods:footstool"
	var slot := int(store.call("grant", id, 1))
	print("R8 granted ", id, " in slot ", slot)
	# as for a mod's item (from_mod is skipped: no mod is loaded here)
	var said := CHEST._store_mod_slot(game, slot, 1)
	var tokens: Array = CHEST.mod_tokens(game)
	print("R8 store says '%s'; chest loans %s; listing %s" % [said, tokens, CHEST.listing(game).filter(func(r: Dictionary) -> bool: return r.has("token"))])
	if tokens.is_empty(): print("R8 FAIL nothing kept"); return
	var token: String = tokens[0]
	print("R8 loan ", (store.get("loans") as Dictionary)[token])
	print("R8 valid document ", store.call("valid_document", store.call("document")))
	await _wait(4.0)
	var ui: Node = game.get("inventory")
	print("R8 body in the world: ", (ui.get("loose") as Dictionary).has(token))
	if ui.has_method("restore_drops"): ui.call("restore_drops")
	await _wait(2.0)
	print("R8 body after restore_drops: ", (ui.get("loose") as Dictionary).has(token))
	# saved and read back
	var path := str(store.get("save_path"))
	var other: RefCounted = (load("res://world/inventory/inventory_store.gd") as GDScript).new()
	var opened := bool(other.call("open", path)) if path != "" else false
	print("R8 reopened from %s: %s, loan kept %s" % [path, opened, (other.get("loans") as Dictionary).get(token, {}).get("furnishing_home", "-")])
	print("R8 take says '%s'; slots with it %d; chest loans %s" % [CHEST.take_mod(game, token),
		(store.get("slots") as Array).filter(func(s: Variant) -> bool: return s is Dictionary and str((s as Dictionary).get("id", "")) == id).size(), CHEST.mod_tokens(game)])


func _fountain() -> void:
	var water := get_tree().get_first_node_in_group("town_fountains") as Node3D
	if water == null: print("R8 FAIL no fountain"); return
	var fountain := water.get_parent() as Node3D
	for holder: Node in fountain.find_children("*", "CollisionShape3D", true, false):
		print("R8 fountain collision ", (holder as CollisionShape3D).shape)
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var actions: Variant = director.get("actions") if director != null else null
	var executors: Dictionary = (actions as Object).get("executors") if actions is Object else {}
	var id := ""
	for key: String in ["twilight_sparkle", "rarity", "applejack", "pinkie_pie", "fluttershy"]:
		if executors.has(key) and is_instance_valid(executors[key]) and is_instance_valid(executors[key].get("actor")): id = key; break
	if id == "": print("R8 FAIL no pony with an executor: ", executors.keys()); return
	var executor: Node = executors[id]
	var actor: Node3D = executor.get("actor")
	var player: Node3D = game.get("player")
	var spot := fountain.global_position + Vector3(5.5, 0, 2.0)
	player.global_position = fountain.global_position + Vector3(8.0, 0.5, 6.0)
	if actor.has_method("reset_motion"): actor.call("reset_motion", Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.2))
	else: actor.global_position = spot + Vector3.UP * 0.2
	await _wait(3.0)
	var nav: Node = executor.get("navigator")
	nav.set("command_owner", "rest_after_command")
	for i in 30:
		var probe: Vector3 = nav.call("command_support", (water.call("drink_spots")[0] as Dictionary).approach)
		if probe.is_finite(): print("R8 walk grid ready after %.0f s" % i); break
		await _wait(1.0)
	for spot_row: Variant in water.call("drink_spots"):
		var at: Vector3 = (spot_row as Dictionary).approach
		var walkable: Vector3 = nav.call("command_support", at) if nav.has_method("command_support") else at
		print("R8 spot %s -> walk grid %s (%.2f m off, %.2f from the middle)" % [at, walkable, Vector2(walkable.x - at.x, walkable.z - at.z).length() if walkable.is_finite() else -1.0,
			Vector2(walkable.x - fountain.global_position.x, walkable.z - fountain.global_position.z).length() if walkable.is_finite() else -1.0])
	var began := VISIT.after_trip(executor, id, "landmark:fountain_01")
	print("R8 %s visit began %s" % [id, began])
	var seen := {}
	for i in 120:
		await _wait(0.5)
		var intent := str(actor.get_meta("life_intent", ""))
		var drinker := actor.find_child("FountainDrink", true, false)
		var key := intent + (" +drinker" if drinker != null else "")
		if not seen.has(key): seen[key] = true; print("R8 %5.1fs %s | owner %s" % [i * 0.5, key, nav.get("command_owner")])
		if actor.get_node_or_null("FountainVisit") == null and i > 2: break
	print("R8 after the visit: owner %s at %s (%.1f m from the fountain)" % [nav.get("command_owner"), actor.global_position, actor.global_position.distance_to(fountain.global_position)])
