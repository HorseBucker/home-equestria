extends "res://world/items/apple_sapling.gd"
## Watch Party: the televisions and the TV remote are shop goods. world/shop/shop_items.gd keeps
## its goods in constants a mod cannot add to; for an id it does not know it asks this script (its
## SAPLING): is_sapling() in has(), definition(), and build_visual() from shop_item_visual.gd. For
## the Watch Party ids these answer from res://mods/watch_party/catalog.gd; for every other id
## (the apple sapling itself, or a sapling planted at Sweet Apple Acres) they are the game's own.
## Applied by res://mods/watch_party/ext_loader.gd.

const WATCH_PARTY_PATH := "res://world/items/apple_sapling.gd"
const WATCH_PARTY_LOADER := preload("res://mods/watch_party/ext_loader.gd")
const WATCH_PARTY_CATALOG := "res://mods/watch_party/catalog.gd"
const WATCH_PARTY_PREFIX := "goods:watch-tv-"

static func _watch_party_good(id: String) -> bool:
	return id.begins_with(WATCH_PARTY_PREFIX) and bool(load(WATCH_PARTY_CATALOG).call("has", id))

static func is_sapling(id: String) -> bool:
	if _watch_party_good(id): return true
	return bool(WATCH_PARTY_LOADER.base(WATCH_PARTY_PATH).call("is_sapling", id))

static func definition(id: String) -> Dictionary:
	if _watch_party_good(id): return load(WATCH_PARTY_CATALOG).call("definition", id)
	return WATCH_PARTY_LOADER.base(WATCH_PARTY_PATH).call("definition", id)

static func build_visual(parent: Node3D, scale := 0.12, potted := true, seed_text := ID) -> AABB:
	var id := str(parent.get("item_id")) if is_instance_valid(parent) else ""
	if _watch_party_good(id): return load(WATCH_PARTY_CATALOG).call("build_visual", parent)
	return WATCH_PARTY_LOADER.base(WATCH_PARTY_PATH).call("build_visual", parent, scale, potted, seed_text)
