extends RefCounted
## Watch Party's story in each world, kept in the world save (Mods.state("watch_party")):
## - The televisions came out of the Everfree. For the first days they lie in the forest, free to
##   whoever finds them (forest_finds.gd); then somepony else finds them, has no idea what they
##   are and puts them up for sale at the market (ext/shop_world.gd): the vintage set and the
##   remote from the second day, both flatscreens from the third.
## - Days count from the first day the mod saw this world, not from the game's first day, so a
##   save the mod is added to late still gets its days in the forest. Seen in the evening or at
##   night (the forest intro starts at dusk), the count starts with the next morning.
## - A set does nothing until somepony who knows magic (Twilight, Celestia, Luna or Trixie:
##   magic_quest.gd) has woken one of its kind; after that every set of that kind works. "Skip the
##   magic" (watch_settings.gd skip_quest) makes them all work at once.
## - Trixie's spell may blow the set up (tv_blast.gd): it is gone for good (destroyed), until Anon
##   puts it back at the market from Settings → Watch Party (respawn).
## - Who saw what (seen): each pony near a set when it woke or blew up remembers it, so a helper
##   treats a set as "another one" only when she saw one before (dev 2026-11-06).
## - The remote comes free with the first television (forest_finds.gd).
## - Only three sets ever came over from Anon's world, one of each kind: a set Anon has (found or
##   bought) is gone from the forest and the market for good. Only the remote restocks.
## Nothing here preloads a game script: tv_set.gd preloads this file, and main.gd loads tv_set.gd
## before the mod's script extensions are applied (ext_loader.gd).
## State: {first_day, found: {id: true}, bought: {id: true}, remote_given, powered: [ids, in the
## order they were woken], woke_by: {id: pony}, seen: {pony: [{id, by, blew}]}, destroyed: {id:
## true}, market_now: {id: true}, remote_powered, spots: {id: [x, y, z]}, scorches (tv_blast.gd),
## attempt}.

const ID := "watch_party"
const HUB := "/root/Mods/watch_party"
const VINTAGE := "goods:watch-tv-vintage"
const FLAT_STAND := "goods:watch-tv-flat"
const FLAT_WALL := "goods:watch-tv-flat-wall"
const REMOTE := "goods:watch-tv-remote"
const TVS := [VINTAGE, FLAT_STAND, FLAT_WALL]
## The shops' day starts at the 06:00 restock (world/shop/shop_world.gd RESTOCK_HOUR).
const RESTOCK_HOUR := 6.0
## First seen after this hour (or before the restock): the count starts with the next morning.
const LATE_HOUR := 12.0
## The story day (0 = the first) from which each good is at the market instead of in the forest.
const MARKET_FROM := {VINTAGE: 1, REMOTE: 1, FLAT_STAND: 2, FLAT_WALL: 2}
## The market table's order, two to a row, back row first: the tall flatscreens behind, the vintage
## set and the remote in front (playtest 2026-11-05: the console flatscreen in front hid the
## vintage set).
const MARKET_ORDER := [FLAT_STAND, FLAT_WALL, VINTAGE, REMOTE]
## Where each set lies in the Everfree (game metres, and the way its screen faces in degrees): the
## vintage set at the edge, about 120 m from Fluttershy's cottage (a spot chosen in play with the
## debug console's "tv here", 2026-11-05), the flatscreens deeper, toward Zecora's hut (forest
## edge near (60, 312), the hut at (-34, 990)). A spot with a height (y not 0) is exact and used as
## it is; one at y 0 is a guess, and the ground and a clear spot near it are found when it is laid
## out (forest_finds.gd). A world keeps the spot it was laid out at (spots); "tv here" moves it.
const FOREST := {
	VINTAGE: [Vector3(136.26, -22.55, 104.24), 330.0],
	# Chosen in play with "tv here" (2026-11-07: the guessed spot had put it in a tree).
	FLAT_STAND: [Vector3(13.54, 4.27, 608.73), 155.0],
	FLAT_WALL: [Vector3(-55.0, 0.0, 780.0), 140.0],
}
## The place Zecora can lead Anon to while the flatscreen on its stand still lies in the forest
## (ext/pony_action_schema.gd adds it to her locations): this far short of it, on the way in.
const SLAB_LABEL := "the strange black slab in the Everfree"
const SLAB_SHORT := 2.5

static func state() -> Dictionary:
	return Mods.state(ID) if is_instance_valid(Mods.game) else {}

static func changed() -> void:
	Mods.save_changed()

static func _clock() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("TimeOfDay") if tree != null else null

## The game day that began at the last 06:00 restock (-1 with no clock).
static func market_day() -> int:
	var clock := _clock()
	if clock == null: return -1
	return int(clock.day) if float(clock.hours) >= RESTOCK_HOUR else int(clock.day) - 1

## The first time the mod sees this world: its day 0, and a TV already owned (a world from before
## this story) counts as found and woken, so nothing that worked stops working.
static func begin(owned: Array) -> void:
	var data := state()
	if data.is_empty() and not is_instance_valid(Mods.game): return
	if data.has("first_day"): return
	var clock := _clock()
	var start := market_day()
	if clock != null and (float(clock.hours) >= LATE_HOUR or float(clock.hours) < RESTOCK_HOUR): start += 1
	data.found = {}
	data.powered = []
	data.remote_given = false
	data.spots = {}
	# A world that already has a set skips the forest: everything is at the market already.
	if owned.any(func(id: Variant) -> bool: return id in TVS): start -= int(MARKET_FROM[FLAT_STAND])
	data.first_day = start
	for id: String in owned:
		if id in TVS and not id in data.powered: (data.powered as Array).append(id)
		if id in TVS: data.found[id] = true
		if id == REMOTE or id in TVS: data.remote_given = true
	changed()
	print("[watch_party] story: first day %d (game day %d)%s" % [start, market_day(), (", already had " + ", ".join(PackedStringArray(owned))) if not owned.is_empty() else ""])

## 0 on the mod's first day in this world, 1 on the second... (-1 on the evening it was first seen).
static func story_day() -> int:
	var data := state()
	if not data.has("first_day"): return 0
	return market_day() - int(data.first_day)

static func at_market(id: String) -> bool:
	return story_day() >= int(MARKET_FROM.get(id, 0)) or _flag("market_now", id)

## Still lying in the forest: not found yet and nopony has taken it to the market.
static func in_forest(id: String) -> bool:
	return id in TVS and not had(id) and not _flag("market_now", id) and story_day() < int(MARKET_FROM.get(id, 0))

static func _flag(group: String, id: String) -> bool:
	var rows: Variant = state().get(group, {})
	return rows is Dictionary and bool((rows as Dictionary).get(id, false))

static func _set_flag(group: String, id: String, on: bool) -> void:
	var data := state()
	if not data.get(group) is Dictionary: data[group] = {}
	if on: data[group][id] = true
	else: (data[group] as Dictionary).erase(id)

static func found(id: String) -> bool:
	return bool((state().get("found", {}) as Dictionary).get(id, false))

static func mark_found(id: String) -> void:
	var data := state()
	if not data.get("found") is Dictionary: data.found = {}
	data.found[id] = true
	changed()

static func bought(id: String) -> bool:
	return bool((state().get("bought", {}) as Dictionary).get(id, false))

static func mark_bought(id: String) -> void:
	var data := state()
	if not data.get("bought") is Dictionary: data.bought = {}
	data.bought[id] = true
	changed()
	print("[watch_party] story: Anon bought the %s; there is no other" % kind_name(id))

## Anon has had this set (found or bought): there was only ever one.
static func had(id: String) -> bool:
	return found(id) or bought(id)

## The goods on the market's television table today (empty: no table yet). A set Anon found in
## the forest is the one the seller would have found, and one he bought was the only one, so
## neither is for sale (only the remote comes back).
static func market_items() -> Array:
	return MARKET_ORDER.filter(func(id: String) -> bool: return at_market(id) and not had(id))

## Where a set lies (or would lie) in this world's forest: its kept spot, else FOREST.
static func forest_point(id: String) -> Vector3:
	var kept: Variant = spot(id)
	if kept is Transform3D: return (kept as Transform3D).origin
	return (FOREST[id] as Array)[0] if FOREST.has(id) else Vector3.INF

## The point Zecora leads Anon to ({id, label}), or {} once the flatscreen is no longer in the forest.
static func slab_place() -> Dictionary:
	if not in_forest(FLAT_STAND): return {}
	var at := forest_point(FLAT_STAND)
	var edge := Vector3(60.0, at.y, 312.0) - at
	if edge.length() > 0.1: at += edge.normalized() * SLAB_SHORT
	return {"id": "point:%.1f,%.1f" % [at.x, at.z], "label": SLAB_LABEL}

static func _settings() -> RefCounted:
	var tree := Engine.get_main_loop() as SceneTree
	var hub: Node = tree.root.get_node_or_null(HUB) if tree != null else null
	return hub.get("settings") as RefCounted if hub != null else null

static func quest_skipped() -> bool:
	var settings := _settings()
	return settings != null and bool(settings.get("skip_quest"))

## Sets of this kind work (somepony woke one, or the magic is skipped).
static func powered(id: String) -> bool:
	if quest_skipped(): return true
	return id in (state().get("powered", []) as Array)

## `by`: the pony whose spell woke it ("" when not known).
static func power(id: String, by := "") -> void:
	var data := state()
	if not data.get("powered") is Array: data.powered = []
	if id in data.powered: return
	(data.powered as Array).append(id)
	if not by.is_empty():
		if not data.get("woke_by") is Dictionary: data.woke_by = {}
		data.woke_by[id] = by
	changed()
	print("[watch_party] story: %s woke the %s (%d so far)" % [by if not by.is_empty() else "somepony", kind_name(id), (data.powered as Array).size()])

## A pony saw a set wake (or blow up: `blew`) close by, by `by`'s spell.
static func witness(pony: String, id: String, by: String, blew := false) -> void:
	var data := state()
	if not data.get("seen") is Dictionary: data.seen = {}
	var rows: Variant = (data.seen as Dictionary).get(pony, [])
	if not rows is Array: rows = []
	(rows as Array).append({"id": id, "by": by, "blew": blew})
	data.seen[pony] = rows
	changed()

## What this pony saw happen to the sets, in order: [{id, by, blew}].
static func seen(pony: String) -> Array:
	var all: Variant = state().get("seen", {})
	var rows: Variant = (all as Dictionary).get(pony, []) if all is Dictionary else []
	return (rows as Array).duplicate(true) if rows is Array else []

## Blown up (Trixie's spell, tv_blast.gd): gone from the world, the forest and the market.
static func destroyed(id: String) -> bool:
	return _flag("destroyed", id)

static func destroyed_list() -> Array:
	return TVS.filter(func(id: String) -> bool: return destroyed(id))

static func mark_destroyed(id: String) -> void:
	_set_flag("destroyed", id, true)
	var data := state()
	if data.get("powered") is Array: (data.powered as Array).erase(id)
	if data.get("woke_by") is Dictionary: (data.woke_by as Dictionary).erase(id)
	changed()
	print("[watch_party] story: the %s blew up; it is gone" % kind_name(id))

## Settings → Watch Party: a blown-up set is for sale at the market again (ext/shop_world.gd builds
## the stand again within a second, when its goods change), asleep until somepony wakes it again.
static func respawn(id: String) -> void:
	var data := state()
	_set_flag("destroyed", id, false)
	_set_flag("market_now", id, true)
	for group: String in ["found", "bought"]:
		if data.get(group) is Dictionary: (data[group] as Dictionary).erase(id)
	if data.get("powered") is Array: (data.powered as Array).erase(id)
	changed()
	print("[watch_party] story: the %s is back at the market" % kind_name(id))

## The kinds woken, in order.
static func powered_list() -> Array:
	return (state().get("powered", []) as Array).duplicate()

static func is_flat(id: String) -> bool:
	return id in [FLAT_STAND, FLAT_WALL]

static func kind_name(id: String) -> String:
	match id:
		VINTAGE: return "vintage television"
		FLAT_STAND: return "flatscreen on its stand"
		FLAT_WALL: return "wall flatscreen"
	return id

## Every good of this mod Anon has: in the briefcase, in his hands or placed (its loans).
static func owned(inventory: Node) -> Array:
	var ids: Array = []
	var store: Variant = inventory.get("inventory") if is_instance_valid(inventory) else null
	if not store is Object: return ids
	var slots: Variant = (store as Object).get("slots")
	if slots is Array:
		for slot: Variant in slots:
			if slot is Dictionary and str((slot as Dictionary).get("id", "")).begins_with("goods:watch-tv-"): ids.append(str(slot.id))
	var loans: Variant = (store as Object).get("loans")
	if loans is Dictionary:
		for loan: Variant in (loans as Dictionary).values():
			if loan is Dictionary and str((loan as Dictionary).get("id", "")).begins_with("goods:watch-tv-"): ids.append(str(loan.id))
	var unique: Array = []
	for id: Variant in ids:
		if not id in unique: unique.append(id)
	return unique

## The spot chosen in the forest for a set, or null before one was found.
static func spot(id: String) -> Variant:
	var spots: Variant = state().get("spots", {})
	var at: Variant = (spots as Dictionary).get(id) if spots is Dictionary else null
	if at is Array and (at as Array).size() == 4:
		return Transform3D(Basis(Vector3.UP, float(at[3])), Vector3(float(at[0]), float(at[1]), float(at[2])))
	return null

static func keep_spot(id: String, where: Transform3D) -> void:
	var data := state()
	if not data.get("spots") is Dictionary: data.spots = {}
	data.spots[id] = [where.origin.x, where.origin.y, where.origin.z, where.basis.get_euler().y]
	changed()

## The debug console's "tv restart": this world's story from the start (today is its first day,
## nothing found or woken, the remote not given; chosen spots kept).
static func restart() -> void:
	var data := state()
	if data.is_empty() and not is_instance_valid(Mods.game): return
	var spots: Variant = data.get("spots", {})
	var attempt := int(data.get("attempt", 0))
	data.clear()
	data.spots = spots if spots is Dictionary else {}
	data.attempt = attempt
	data.first_day = market_day()
	data.found = {}
	data.bought = {}
	data.powered = []
	data.remote_given = false
	data.remote_powered = false
	for group: String in ["seen", "woke_by", "destroyed", "market_now"]: data[group] = {}
	data.scorches = []
	changed()

## A number for each helper's try (an encounter id is used once: world/ai/encounters).
static func next_attempt() -> int:
	var data := state()
	data.attempt = int(data.get("attempt", 0)) + 1
	changed()
	return int(data.attempt)

## Before the mod is removed (Settings → Watch Party → Before you uninstall): every TV and remote
## leaves this world, set up anywhere or in the briefcase. The game rejects a briefcase that holds
## an item it does not know (world/inventory/inventory_store.gd valid_document), so with the mod
## gone a single TV left behind would set the whole briefcase aside, bits and all. Placed ones end
## like eaten food (consume), the rest leave their slots (discard). The sets go back to the market,
## should the mod stay after all. Returns how many items went, or -1 with nothing done (`why`).
static func remove_all(inventory: Node, why: Array) -> int:
	var store: Variant = inventory.get("inventory") if is_instance_valid(inventory) else null
	if not store is Object or not (store as Object).has_method("consume"):
		why.append("The briefcase is not loaded. Load your world first.")
		return -1
	var ours := func(id: Variant) -> bool: return str(id).begins_with("goods:watch-tv-")
	# One in a hand stays put (its hand would be left holding nothing real): it is put down first.
	var held: Variant = inventory.get("held")
	if held is Dictionary:
		for body: Variant in (held as Dictionary).values():
			if is_instance_valid(body) and ours.call((body as Node).get_meta("item_id", "")):
				why.append("Put down the TV or remote you're holding first.")
				return -1
	var count := 0
	var loose: Variant = inventory.get("loose")
	var loans: Dictionary = ((store as Object).get("loans") as Dictionary).duplicate()
	for token: Variant in loans:
		if not ours.call((loans[token] as Dictionary).get("id", "")): continue
		if loose is Dictionary:
			var body: Variant = (loose as Dictionary).get(token)
			if is_instance_valid(body): (body as Node).queue_free()
			(loose as Dictionary).erase(token)
		if (store as Object).call("consume", str(token)): count += 1
	for slot: Variant in ((store as Object).get("slots") as Array).duplicate(true):
		if slot is Dictionary and ours.call((slot as Dictionary).get("id", "")): count += int((slot as Dictionary).get("count", 0))
	for id: String in TVS + [REMOTE]: (store as Object).call("discard", id)
	if not owned(inventory).is_empty():
		why.append("Some could not be removed. Try again, or pick them up and press it again.")
		return -1
	var data := state()
	if not data.is_empty():
		for id: String in TVS:
			if had(id) or destroyed(id): respawn(id)
		data.remote_given = false
		changed()
	print("[watch_party] packed away for uninstalling: %d item(s) removed" % count)
	return count
