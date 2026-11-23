extends RefCounted
## Worlds from before the Ponyville overhaul (2026-11-17): the first time such a world loads with the overhaul, the
## things its save ties to the old town's layout are put right, once, without the player doing anything.
## arrival_story.gd prepare() runs it after the save is restored and before anyone is placed.
##
## A save keeps places by position, and the old town's houses and ground are gone, so on loading it:
## - the player's home (arrival "home", a place id of a house that is no longer there) is let go, so a pony who
##   gives homes (Mayor Mare, Princess Celestia) can give him a new one of his choosing (HorseBucker, 2026-11-18: players
##   may not like a house picked for them). In the story the old house needs renovating: the pony who gave it
##   alone is told (a memory of hers, world_context.record) that it is closed for repairs, that his belongings are
##   in the Town Hall chest, and that he is welcome to move into another house. Nothing says the town changed.
## - everything of his out in the world that the new town could have buried or walled in (furniture placed in the
##   old home, things left lying in town) goes into the storage chest in the Town Hall (chest_store.gd), never the
##   briefcase, which may be full;
## - the player saved in town is put at the Town Hall's door; ponies saved out in town (and their resumed day plans)
##   start at home instead; the balloon goes back to its pad.
## Before changing anything, the world's state and autosave are copied into its saves/archive folder
## (autosave_before_ponyville_overhaul.json, loadable from the saved games panel). The world is stamped
## (state "ponyville_overhaul") so it runs once; a new world is stamped at once.

const OLD_TOWN := "res://world/towns/ponyville/density/old_town.json"
const STORE := preload("res://world/inventory/inventory_store.gd")
const FURNISHING := preload("res://world/housing/home_furnishing.gd")
const CHEST := preload("res://world/props/town_chest/chest_store.gd")
const STAMP := "ponyville_overhaul"
const VERSION := 3
## What the pony who gave the old house remembers of it: short and plain, and to be left alone (2026-11-18 play test:
## the first version told of sagging floors and a leaking roof, and every pony talked about floors and roofs).
const HOME_NOTE := "Anon's old house is closed for some repair work, so he is free to choose any empty house in Ponyville to live in instead, and %s can give him one whenever he asks. His things are kept in the storage chest at the Town Hall. This is a small, settled matter: do not bring it up yourself, and if it does come up, keep it brief."
const OLD_NOTE_START := "Anon's house, the one "
## Who gives homes; the giver of an old home whose giver was not saved (the old opening's welcome) is the mayor.
const DEFAULT_GIVER := "mayor_mare"


static func run(arrival: Node, resumed: Dictionary) -> void:
	var game: Node = arrival.get("game")
	var context: Node = game.get("world_context") if game != null else null
	if context == null or context.get("_read_only") == true: return
	var state: Dictionary = context.get("state")
	if state.has(STAMP):
		_soften(context); _tidy(game, context); return
	var fresh := resumed.is_empty() and (state.get("events", []) as Array).is_empty() and str(arrival.call("stage")) in ["wake", "found", "rescue"]
	if fresh:
		_stamp(context, {"version": VERSION, "new": true}); return
	var data_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(OLD_TOWN)) if FileAccess.file_exists(OLD_TOWN) else null
	var old_town: Dictionary = data_v if data_v is Dictionary else {}
	var edge: Array = old_town.get("edge", [-300, -590, 500, 190])
	var in_town := func(p: Vector3) -> bool: return p.x >= float(edge[0]) - 40.0 and p.x <= float(edge[2]) + 40.0 and p.z >= float(edge[1]) - 40.0 and p.z <= float(edge[3]) + 40.0
	_backup(context)
	var notes: PackedStringArray = []
	var data: Dictionary = arrival.get("data")
	var tree := arrival.get_tree()
	# ---- the home: let go, its giver told it is being renovated ----
	var old_place := str(data.get("home", ""))
	var giver := ""
	if old_place != "" and arrival.call("_home_house") == null:
		giver = str(data.get("home_given_by", ""))
		if giver == "": giver = DEFAULT_GIVER
		data.erase("home"); data.erase("home_given_by"); data.erase("furnished"); data.erase("welcome_table_required")
		arrival.call("_save")
		preload("res://world/towns/ponyville/town_density.gd").forget_home(str(context.get("path")).get_base_dir())
		context.call("record", "home", HOME_NOTE % _name(giver), [giver], [giver])
	# ---- his things out in the world: into the Town Hall chest ----
	var store: RefCounted = CHEST.briefcase(game)
	var chested := 0; var left := 0; var carried := 0
	if store != null:
		var loans: Dictionary = (store.get("loans") as Dictionary).duplicate(true)
		for token: String in loans:
			var loan: Dictionary = loans[token]
			if not loan.get("world_transform") is Array or str(loan.get("furnishing_home", "")) == CHEST.CHEST_HOME: continue
			var pose := STORE.decode_pose(loan.world_transform)
			var homeless := loan.has("furnishing_home") and FURNISHING.home(tree, str(loan.furnishing_home)) == null
			if not homeless and not (not loan.has("furnishing_home") and in_town.call(pose.origin)): continue
			# a mod's item (the Pedal Copter, Watch Party's sets) into the briefcase, not the chest: its mod looks
			# for it there and would make another (2026-11-18 play test); with the case full, by the Town Hall door
			if CHEST.from_mod(str(loan.get("id", ""))):
				if bool(store.call("put", token, -1)): carried += 1
				elif _hall_door(tree).is_finite() and bool(store.call("set_dropped", token, Transform3D(Basis.IDENTITY, _hall_door(tree) + Vector3.UP * 0.3))): carried += 1
				else: left += 1
				continue
			if CHEST.store_loan(game, token): chested += 1
			else: left += 1
		var briefcase: Variant = game.get("inventory")
		if chested + carried > 0 and briefcase is Object and (briefcase as Object).has_method("restore_drops"): (briefcase as Object).call("restore_drops")
	if giver != "":
		notes.append("Your house is closed for repairs. %s will give you a new one whenever you ask." % _name(giver))
	# gifts the ponies keep set out in their old houses (a fish Twilight left on her library's floor) cannot be
	# picked up, and their places in the old houses are gone: into the chest too
	chested += _gifts_to_chest(game, context)
	if chested > 0:
		notes.append("Your belongings are safe in the storage chest in the Town Hall.")
	# ---- the player, the ponies, the balloon ----
	var body: Node3D = game.player.get_node("Body") if bool(game.get("xr_active")) else game.player
	if body != null and in_town.call(body.global_position):
		var spot := _hall_door(tree)
		if not spot.is_finite():
			var spawn: Node3D = game.get("spawn")
			spot = spawn.global_position if is_instance_valid(spawn) else body.global_position
		arrival.call("_place_player", spot, Vector3.FORWARD)
	var population: Node = game.get("population")
	if is_instance_valid(population):
		var saved: Variant = population.get("saved")
		if saved is Dictionary:
			for id: String in (saved as Dictionary).keys():
				var row: Variant = saved[id]
				if row is Dictionary and (row as Dictionary).get("position") is Vector3 and in_town.call(row.position): (saved as Dictionary).erase(id)
		if "resumed_plans" in population: population.set("resumed_plans", {})
	var balloon: Variant = game.get("balloon")
	if balloon is Node3D and is_instance_valid(balloon) and "home" in balloon:
		var pad: Transform3D = balloon.get("home")
		if (balloon as Node3D).global_position.distance_to(pad.origin) > 5.0:
			(balloon as Node3D).global_transform = pad
			var riders: Variant = balloon.get("saved_passengers")
			if riders is Dictionary: (riders as Dictionary).clear()
	_stamp(context, {"version": VERSION, "migrated": Time.get_datetime_string_from_system(), "old_home": old_place, "told": giver,
		"to_chest": chested, "carried": carried, "left": left, "tidied": true})
	var saves: Node = game.get("saves")
	if is_instance_valid(saves) and not notes.is_empty():
		saves.set("message", (str(saves.get("message")) + " " + " ".join(notes)).strip_edges())
		if saves.has_signal("changed"): saves.emit_signal("changed")
	print("[overhaul] old world brought up to date: home %s let go (told %s), %d things to the Town Hall chest, %d left" % [old_place, giver, chested, left])


## The Town Hall's door (where a pony goes in from), or INF.
static func _hall_door(tree: SceneTree) -> Vector3:
	for node: Node in tree.get_nodes_in_group("house_interiors"):
		if str(node.get("home_kind")) == "town_hall" and node.has_method("outside"): return node.call("outside")
	return Vector3.INF


## The ponies' belongings set out in their houses (pony_belongings rows with a "pose": mechanics/gifts/belongings.gd)
## go into the chest; those only kept (no pose) stay hers. Returns how many went.
static func _gifts_to_chest(game: Node, context: Node) -> int:
	var block: Variant = (context.get("state") as Dictionary).get("pony_belongings")
	if not block is Dictionary: return 0
	var moved := 0
	for pony: String in (block as Dictionary).keys():
		var rows: Variant = block[pony]
		if not rows is Array: continue
		var keep: Array = []
		for row: Variant in rows:
			if row is Dictionary and (row as Dictionary).get("pose") is Array and CHEST.add(game, str(row.get("id", "")), 1): moved += 1
			else: keep.append(row)
		block[pony] = keep
	if moved > 0 and context.has_method("_changed"): context.call("_changed")
	return moved


## A world brought up to date by version 2 (2026-11-18 play test): the Pedal Copter and Watch Party sets it put in
## the chest go back to the briefcase, or are let go where the player already has another (their mod made a new
## one); the gifts ponies had set out in their old houses go into the chest. Once (stamp "tidied").
static func _tidy(game: Node, context: Node) -> void:
	var stamp: Variant = (context.get("state") as Dictionary).get(STAMP)
	if not stamp is Dictionary or bool((stamp as Dictionary).get("tidied", false)) or (stamp as Dictionary).get("new", false): return
	var store: RefCounted = CHEST.briefcase(game)
	if store == null: return
	var rows := CHEST.entries(game)
	var kept: Array = []
	var back := 0; var dropped := 0
	for row: Dictionary in rows:
		if not CHEST.from_mod(str(row.id)): kept.append(row); continue
		var id := str(row.id)
		var owned := false
		for slot: Variant in store.get("slots"):
			if slot is Dictionary and str((slot as Dictionary).get("id", "")) == id: owned = true
		for loan: Variant in (store.get("loans") as Dictionary).values():
			if loan is Dictionary and str((loan as Dictionary).get("id", "")) == id: owned = true
		if owned: dropped += int(row.count); continue
		if int(store.call("grant", id, int(row.count))) >= 0: back += int(row.count)
		else: kept.append(row)
	if back + dropped > 0:
		(context.get("state") as Dictionary)[CHEST.KEY] = {"entries": kept}
	var gifts := _gifts_to_chest(game, context)
	(stamp as Dictionary).tidied = true
	if context.has_method("_changed"): context.call("_changed")
	print("[overhaul] tidied: %d mod items back to the briefcase, %d copies let go, %d ponies' gifts to the chest" % [back, dropped, gifts])


## A world brought up to date by an earlier version: its giver's memory of the old house, told in vivid detail
## then, is replaced by the short one (world_context correct_event).
static func _soften(context: Node) -> void:
	var stamp: Variant = (context.get("state") as Dictionary).get(STAMP)
	if not stamp is Dictionary or int((stamp as Dictionary).get("version", 0)) >= VERSION: return
	var giver := str((stamp as Dictionary).get("told", ""))
	for event: Variant in ((context.get("state") as Dictionary).get("events", []) as Array).duplicate():
		if event is Dictionary and str(event.get("kind", "")) == "home" and str(event.get("text", "")).begins_with(OLD_NOTE_START):
			context.call("correct_event", str(event.id), HOME_NOTE % _name(giver if giver != "" else DEFAULT_GIVER))
	(stamp as Dictionary).version = VERSION
	if context.has_method("_changed"): context.call("_changed")


static func _name(id: String) -> String:
	match id:
		"mayor_mare": return "Mayor Mare"
		"princess_celestia", "celestia": return "Princess Celestia"
	return id.replace("_", " ").capitalize()


static func _stamp(context: Node, row: Dictionary) -> void:
	(context.get("state") as Dictionary)[STAMP] = row
	if context.has_method("_changed"): context.call("_changed")


## The world's state and autosave as they were, in its saves/archive folder.
static func _backup(context: Node) -> void:
	var world := str(context.get("path")).get_base_dir()
	var archive := world.path_join("saves").path_join("archive")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(archive))
	for pair: Array in [[str(context.get("path")), archive.path_join("context_before_ponyville_overhaul.json")],
			[world.path_join("saves").path_join("autosave.json"), archive.path_join("autosave_before_ponyville_overhaul.json")],
			[world.path_join("saves").path_join("autosave.story.db"), archive.path_join("autosave_before_ponyville_overhaul.story.db")]]:
		if FileAccess.file_exists(pair[0]) and not FileAccess.file_exists(pair[1]):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(pair[0]), ProjectSettings.globalize_path(pair[1]))
