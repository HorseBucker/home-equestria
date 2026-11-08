extends "res://world/housing/furnishing_rules.gd"
## Watch Party: the televisions are home furniture (the vintage set and the console flatscreen
## stand on a floor, the wall flatscreen hangs). The game's SURFACES table is a constant, so has()
## and wall() answer for the sets first. valid_loan() asks the game's own check about a game good on
## the same surface, so a placed set is kept in the save under exactly the game's rules.
## Applied by res://mods/watch_party/ext_loader.gd.

const WATCH_PARTY_PATH := "res://world/housing/furnishing_rules.gd"
const WATCH_PARTY_LOADER := preload("res://mods/watch_party/ext_loader.gd")
const WATCH_PARTY_SURFACES := {"goods:watch-tv-vintage": "floor", "goods:watch-tv-flat": "floor", "goods:watch-tv-flat-wall": "wall"}

static func has(id: String) -> bool:
	if WATCH_PARTY_SURFACES.has(id): return true
	return bool(WATCH_PARTY_LOADER.base(WATCH_PARTY_PATH).call("has", id))

static func wall(id: String) -> bool:
	if WATCH_PARTY_SURFACES.has(id): return WATCH_PARTY_SURFACES[id] == "wall"
	return bool(WATCH_PARTY_LOADER.base(WATCH_PARTY_PATH).call("wall", id))

static func valid_loan(loan: Dictionary) -> bool:
	var id := str(loan.get("id", ""))
	var game: Script = WATCH_PARTY_LOADER.base(WATCH_PARTY_PATH)
	if not WATCH_PARTY_SURFACES.has(id): return bool(game.call("valid_loan", loan))
	var stand_in := _watch_party_stand_in(str(WATCH_PARTY_SURFACES[id]))
	if stand_in.is_empty(): return false
	var asked := loan.duplicate()
	asked.id = stand_in
	return bool(game.call("valid_loan", asked))

## One of the game's own goods that goes on this surface ("floor" or "wall").
static func _watch_party_stand_in(surface: String) -> String:
	for key: String in SURFACES:
		if SURFACES[key] == surface: return key
	return ""
