extends RefCounted
## The storage chest in the Town Hall (2026-11-18): what it holds, one chest per world. Kept in the world's
## state (world_context "town_hall_chest"), so it is saved and loaded with the rest of the world, and moves with
## saves (game_saves.gd checkpoints the context) without touching the save script.
##
## An entry is a briefcase stack: {"id", "count"} and, for a bitten portion, "bites" (one unit). Plain stacks of one
## id merge; the chest has no per-stack limit, only MAX_ENTRIES entries. Ids the game no longer knows (a mod
## taken out) are kept and shown by id; they can be discarded but not taken.
##
## A mod's item (the Pedal Copter, Watch Party's sets, the Mirror Pool) is kept another way (2026-11-18 play test:
## "I want to be able to store mod items in the chest"). Such mods count what the player owns from the briefcase's
## own books (inventory_store.gd: its slots and its loans, the things out of it) and make a new one when they find
## none, so the item stays one of his loans: set out "in a home" (furnishing_home) that is the chest, CHEST_HOME. The
## game makes a placed thing's body only inside its home (home_furnishing.gd home(), which never finds this one), so
## it is never in the world; the mods leave furnishings where they are (no recall, no rescue) and still count it.
## furnishing_rules.gd lets any item be set out in the chest. listing() shows both kinds; the chest's own state
## holds only the first.

const CATALOG := preload("res://world/inventory/item_catalog.gd")
const SHOP := preload("res://world/shop/shop_items.gd")
const SAPLING_ID := "goods:apple-sapling"
const KEY := "town_hall_chest"
const MAX_ENTRIES := 240
## The "home" a mod's item kept in the chest is set out in (furnishing_rules.gd CHEST_HOME).
const CHEST_HOME := "town_hall_chest"
## Mod items in the chest count among the things out of the briefcase (briefcase_inventory.gd MAX_LOOSE, 24 in
## all): at most this many, so the player can still set things down.
const MOD_MAX := 12


static func _context(game: Node) -> Node:
	return game.get("world_context") if is_instance_valid(game) else null


static func entries(game: Node) -> Array:
	var context := _context(game)
	if context == null: return []
	var row: Variant = (context.get("state") as Dictionary).get(KEY)
	if not row is Dictionary or not (row as Dictionary).get("entries") is Array: return []
	return ((row as Dictionary).entries as Array).filter(func(e: Variant) -> bool: return e is Dictionary and str(e.get("id", "")) != "" and int(e.get("count", 0)) > 0)


## What the chest shows: its own entries, then the mod items kept in it ({"id", "count": 1, "token"}).
static func listing(game: Node) -> Array:
	var rows := entries(game)
	var store := briefcase(game)
	for token: String in mod_tokens(game):
		rows.append({"id": str((store.get("loans") as Dictionary)[token].get("id", "")), "count": 1, "token": token})
	return rows


## The loans set out in the chest (see the top).
static func mod_tokens(game: Node) -> Array:
	var store := briefcase(game)
	var out: Array = []
	if store == null: return out
	var loans: Dictionary = store.get("loans")
	for token: Variant in loans:
		if loans[token] is Dictionary and str((loans[token] as Dictionary).get("furnishing_home", "")) == CHEST_HOME: out.append(str(token))
	out.sort()
	return out


## Sets loan `token` out in the chest (it leaves the world or the hand it is in). False if the store refused.
static func keep_loan(game: Node, token: String) -> bool:
	var store := briefcase(game)
	if store == null or not (store.get("loans") as Dictionary).has(token): return false
	var checked: Dictionary = (store.get("loans") as Dictionary).duplicate(true)
	var next: Array = (store.get("slots") as Array).duplicate(true)
	var loan: Dictionary = checked[token]
	if bool(loan.get("equipped", false)):
		var slot: Dictionary = next[int(loan.slot)]
		slot.count = int(slot.count) - 1
		if int(slot.count) <= 0: next[int(loan.slot)] = {}
		loan.erase("equipped")
	for key: String in ["picnic_deployed", "picnic_heights", "easel_open", "board_open", "furnishing_size", "cooking"]: loan.erase(key)
	loan.world_transform = store.call("encode_pose", _chest_pose(game))
	loan.furnishing_home = CHEST_HOME
	if not bool(store.call("_commit", next, checked)): return false
	_let_go_body(game, token)
	return true


## A loan's body out in the world (or in a hand) goes: the item is in the chest now.
static func _let_go_body(game: Node, token: String) -> void:
	var ui: Variant = game.get("inventory")
	if not ui is Object or not is_instance_valid(ui): return
	var loose: Variant = (ui as Object).get("loose")
	if not loose is Dictionary or not (loose as Dictionary).has(token): return
	var body: Variant = loose[token]
	var held: Variant = (ui as Object).get("held")
	if held is Dictionary:
		for side: Variant in (held as Dictionary).keys():
			if held[side] == body:
				(held as Dictionary).erase(side)
				if (ui as Object).has_method("_claim"): (ui as Object).call("_claim", str(side), false)
	(loose as Dictionary).erase(token)
	if body is Node and is_instance_valid(body): (body as Node).queue_free()


static func _chest_pose(game: Node) -> Transform3D:
	var tree: SceneTree = game.get_tree() if is_instance_valid(game) and game.is_inside_tree() else null
	var chest: Node = tree.get_first_node_in_group("town_chests") if tree != null else null
	return (chest as Node3D).global_transform if chest is Node3D else Transform3D.IDENTITY


static func _mod_room(game: Node) -> String:
	var store := briefcase(game)
	var ui: Variant = game.get("inventory")
	var most := 24
	if ui is Object and is_instance_valid(ui) and (ui as Object).get("MAX_LOOSE") != null: most = int((ui as Object).get("MAX_LOOSE"))
	if mod_tokens(game).size() >= MOD_MAX: return "The chest keeps at most %d things from mods." % MOD_MAX
	if (store.get("loans") as Dictionary).size() >= most: return "%d of your things are out of the briefcase, the most there can be. Put some away first." % most
	return ""


## Things set out in a Ponyville house the town no longer has (2026-11-19 play test: a television in a vacant house,
## then the town density turned down so the house was gone, and the set was nowhere: the game keeps a placed thing
## only inside its home, home_furnishing.gd): each goes into the chest (as a loan, like a mod's item), so it is
## still his and can be taken out. A home is Ponyville's when its id is a house place id ("house:x:y:z", tenths of a
## metre) inside the town's edge; a home elsewhere (a house streamed out in another place) is left alone.
const TOWN_EDGE := Rect2(-300.0, -589.0, 800.0, 778.0)
static func rescue_homeless(game: Node) -> int:
	var store := briefcase(game)
	if store == null or not bool(store.get("writable")) or not game.is_inside_tree(): return 0
	var tree := game.get_tree()
	var furnishing: Script = load("res://world/housing/home_furnishing.gd")
	var moved := 0
	for token: Variant in (store.get("loans") as Dictionary).keys():
		var loan: Dictionary = (store.get("loans") as Dictionary).get(token, {})
		var home := str(loan.get("furnishing_home", ""))
		if home == "" or home == CHEST_HOME or not home.begins_with("house:"): continue
		var parts := home.split(":")
		if parts.size() < 4 or not TOWN_EDGE.has_point(Vector2(float(parts[1]) / 10.0, float(parts[3]) / 10.0)): continue
		if furnishing.call("home", tree, home) != null: continue
		if keep_loan(game, str(token)): moved += 1
	if moved > 0: print("[chest] %d thing(s) set out in a house this town density does not have went into the chest" % moved)
	return moved


## A mod's item kept in the chest back into the briefcase.
static func take_mod(game: Node, token: String) -> String:
	var store := briefcase(game)
	if store == null or not mod_tokens(game).has(token): return ""
	var id := str((store.get("loans") as Dictionary)[token].get("id", ""))
	if not bool(store.call("put", token, -1)): return "No room in the briefcase."
	return "Took %s." % name_of(id)


## A mod's item kept in the chest thrown away (its mod may make another, as when one is lost).
static func discard_mod(game: Node, token: String) -> String:
	var store := briefcase(game)
	if store == null or not mod_tokens(game).has(token): return ""
	var id := str((store.get("loans") as Dictionary)[token].get("id", ""))
	if not bool(store.call("consume", token)): return "Could not discard that."
	return "Discarded %s." % name_of(id)


static func _write(game: Node, rows: Array) -> bool:
	var context := _context(game)
	if context == null or context.get("_read_only") == true: return false
	(context.get("state") as Dictionary)[KEY] = {"entries": rows}
	if context.has_method("_changed"): context.call("_changed")
	return true


## Puts `count` of `id` (or one bitten portion) in the chest. False when it is full.
static func add(game: Node, id: String, count: int = 1, bites: int = 0) -> bool:
	if id.is_empty() or count <= 0: return false
	var rows := entries(game)
	if bites <= 0:
		for row: Dictionary in rows:
			if str(row.id) == id and not row.has("bites"):
				row.count = int(row.count) + count
				return _write(game, rows)
	if rows.size() >= MAX_ENTRIES: return false
	var entry := {"id": id, "count": 1 if bites > 0 else count}
	if bites > 0: entry.bites = bites
	rows.append(entry)
	return _write(game, rows)


## An item a mod adds (2026-11-18 play test: the Pedal Copter mod and Watch Party give a new copter or put a set
## back on sale when they find none in the briefcase or out in the world, so one simply listed in the chest came
## back twice): goods the game's own list does not have (Watch Party adds its sets as goods), or anything drawn
## from a mod's folder. Kept in the chest as loans (see the top).
static func from_mod(id: String) -> bool:
	id = CATALOG.canonical(id)
	if id.begins_with("goods:") and id != SAPLING_ID and not SHOP.GOODS.has(id.substr(6)): return true
	if not CATALOG.has(id): return false
	var icon := CATALOG.icon(id)
	if icon != null and icon.resource_path.begins_with("res://mods/"): return true
	var scene := CATALOG.scene(id)
	return scene != null and scene.resource_path.begins_with("res://mods/")


static func name_of(id: String) -> String:
	if not CATALOG.has(CATALOG.canonical(id)): return "Unknown item (%s)" % id
	return str(CATALOG.definition(CATALOG.canonical(id)).get("name", id))


## The briefcase's store (inventory_store.gd) of this world.
static func briefcase(game: Node) -> RefCounted:
	var ui: Variant = game.get("inventory") if is_instance_valid(game) else null
	return (ui as Object).get("inventory") if ui is Object and is_instance_valid(ui) else null


## Moves `amount` (-1: all that are not in a hand) of briefcase slot `index` into the chest. Returns what to say.
static func store_slot(game: Node, index: int, amount: int = -1) -> String:
	var store := briefcase(game)
	if store == null: return "The briefcase is not here."
	var slots: Array = store.get("slots")
	if index < 0 or index >= slots.size() or (slots[index] as Dictionary).is_empty(): return ""
	var slot: Dictionary = slots[index]
	var free: int = int(store.call("available", index))
	if from_mod(str(slot.id)): return _store_mod_slot(game, index, free if amount < 0 else mini(amount, free))
	var moving: int = free if amount < 0 else mini(amount, free)
	if moving <= 0: return "That one is in your hand."
	if not add(game, str(slot.id), moving, int(slot.get("bites", 0))): return "The chest is full."
	var next: Array = slots.duplicate(true)
	next[index].count = int(next[index].count) - moving
	if int(next[index].count) <= 0: next[index] = {}
	if not bool(store.call("_commit", next, store.get("loans"))):
		_take_back(game, str(slot.id), moving, int(slot.get("bites", 0)))
		return str(store.get("last_error")) if str(store.get("last_error")) != "" else "Could not move that."
	return "Put %s in the chest." % _amount_text(str(slot.id), moving)


## `count` units of a mod's item from briefcase slot `index`, each set out in the chest as its own loan.
static func _store_mod_slot(game: Node, index: int, count: int) -> String:
	if count <= 0: return "That one is in your hand."
	var store := briefcase(game)
	var id := str((store.get("slots") as Array)[index].id)
	var moved := 0
	while moved < count:
		var full := _mod_room(game)
		if full != "": return full if moved == 0 else "Put %s in the chest. %s" % [_amount_text(id, moved), full]
		var token := str(store.call("take", index))
		if token == "": break
		if not keep_loan(game, token):
			store.call("put", token, index)
			break
		moved += 1
	if moved <= 0: return str(store.get("last_error")) if str(store.get("last_error")) != "" else "Could not move that."
	return "Put %s in the chest." % _amount_text(id, moved)


## Moves `amount` (-1: all) of chest entry `index` into the briefcase, as much as fits. Returns what to say.
static func take(game: Node, index: int, amount: int = -1) -> String:
	var store := briefcase(game)
	var rows := entries(game)
	if store == null or index < 0 or index >= rows.size(): return ""
	var entry: Dictionary = rows[index]
	var id := CATALOG.canonical(str(entry.id))
	if not CATALOG.has(id): return "The game does not know that item any more; it can only be discarded."
	var want: int = int(entry.count) if amount < 0 else mini(amount, int(entry.count))
	var moved := 0
	if entry.has("bites"):
		var slots: Array = (store.get("slots") as Array).duplicate(true)
		var free := slots.find({})
		if free >= 0:
			slots[free] = {"id": id, "count": 1, "bites": int(entry.bites)}
			if bool(store.call("_commit", slots, store.get("loans"))): moved = 1
	else:
		while moved < want:
			var part := mini(want - moved, maxi(1, CATALOG.stack(id)))
			if int(store.call("grant", id, part)) < 0:
				if part > 1 and int(store.call("grant", id, 1)) >= 0: moved += 1; continue
				break
			moved += part
	if moved <= 0: return "No room in the briefcase."
	rows = entries(game)
	rows[index].count = int(rows[index].count) - moved
	if int(rows[index].count) <= 0: rows.remove_at(index)
	_write(game, rows)
	return "Took %s.%s" % [_amount_text(id, moved), "" if moved >= want else " The briefcase is full."]


## Throws away `amount` (-1: all) of chest entry `index`.
static func discard(game: Node, index: int, amount: int = -1) -> String:
	var rows := entries(game)
	if index < 0 or index >= rows.size(): return ""
	var entry: Dictionary = rows[index]
	var gone: int = int(entry.count) if amount < 0 else mini(amount, int(entry.count))
	entry.count = int(entry.count) - gone
	if int(entry.count) <= 0: rows.remove_at(index)
	_write(game, rows)
	return "Discarded %s." % _amount_text(str(entry.id), gone)


## Throws away `amount` (-1: all not in a hand) of briefcase slot `index`.
static func discard_slot(game: Node, index: int, amount: int = -1) -> String:
	var store := briefcase(game)
	if store == null: return ""
	var slots: Array = store.get("slots")
	if index < 0 or index >= slots.size() or (slots[index] as Dictionary).is_empty(): return ""
	var free: int = int(store.call("available", index))
	var gone: int = free if amount < 0 else mini(amount, free)
	if gone <= 0: return "That one is in your hand."
	var id := str(slots[index].id)
	var next: Array = slots.duplicate(true)
	next[index].count = int(next[index].count) - gone
	if int(next[index].count) <= 0: next[index] = {}
	if not bool(store.call("_commit", next, store.get("loans"))): return "Could not discard that."
	return "Discarded %s." % _amount_text(id, gone)


## A loan out in the world (placed furniture, something left lying) into the chest: the unit leaves the world.
static func store_loan(game: Node, token: String) -> bool:
	var store := briefcase(game)
	if store == null: return false
	var loans: Dictionary = store.get("loans")
	if not loans.has(token): return false
	var loan: Dictionary = loans[token]
	if str(loan.get("furnishing_home", "")) == CHEST_HOME: return true
	if from_mod(str(loan.get("id", ""))): return _mod_room(game) == "" and keep_loan(game, token)
	if not add(game, str(loan.get("id", "")), 1, int(loan.get("bites", 0))): return false
	if bool(store.call("consume", token)): return true
	_take_back(game, str(loan.get("id", "")), 1, int(loan.get("bites", 0)))
	return false


static func _take_back(game: Node, id: String, count: int, bites: int) -> void:
	var rows := entries(game)
	for i in range(rows.size() - 1, -1, -1):
		var row: Dictionary = rows[i]
		if str(row.id) != id or row.has("bites") != (bites > 0): continue
		row.count = int(row.count) - count
		if int(row.count) <= 0: rows.remove_at(i)
		_write(game, rows)
		return


static func _amount_text(id: String, count: int) -> String:
	return name_of(id) if count == 1 else "%d × %s" % [count, name_of(id)]
