extends RefCounted
## Watch Party: the televisions the market sells. Shop goods ("goods:<model>") like the game's own
## (world/shop/shop_items.gd GOODS). The mod's script extensions call into this file: the shop
## (ext/apple_sapling.gd, ext/shop_world.gd), the briefcase and home furnishing
## (ext/furnishing_rules.gd, ext/home_furnishing.gd) then know the TVs.
## Prices are a first guess, to be tuned in play.

const MODEL := preload("res://mods/watch_party/tv_model.gd")
const FLAT := preload("res://mods/watch_party/flat_model.gd")
const SET := preload("res://mods/watch_party/tv_set.gd")
const VINTAGE := "goods:watch-tv-vintage"
const FLAT_STAND := "goods:watch-tv-flat"
const FLAT_WALL := "goods:watch-tv-flat-wall"
const REMOTE := "goods:watch-tv-remote"
## Each television's model script and variant (screen_common.gd).
const MODELS := {VINTAGE: [MODEL, ""], FLAT_STAND: [FLAT, "stand"], FLAT_WALL: [FLAT, "wall"]}
## id: name, longest edge in metres (the briefcase's size estimate), price, description. The
## descriptions are the seller's notes: the sets came out of the Everfree (finds.gd).
## Prices (2026-11-06, the dev's tuning): a seller's guess at what a curiosity nopony can use is
## worth, against the game's dearest furniture (the camera at 80 bits).
const GOODS := {
	VINTAGE: ["Vintage television", 1.12, 40, "Found at the edge of the Everfree. Heavy as a cart full of apples. Glass face, lots of knobs, does absolutely nothing. Probably wants some kind of magic. No refunds."],
	FLAT_STAND: ["Flatscreen TV (65\")", 1.7, 150, "Found deep in the Everfree. Very flat, very black, very shiny, and it came with its own little table! A mirror? A very fancy tray? Nopony can tell."],
	FLAT_WALL: ["Flatscreen TV, wall-mounted (65\")", 1.46, 150, "Found in the Everfree, tangled up in vines. Like the other black slab, but with a hook on the back, so maybe it hangs on a wall like a painting. Doesn't do anything yet."],
	REMOTE: ["TV remote", 0.17, 10, "A little stick covered in buttons. Pressing them does nothing at all. Very satisfying to press, though."],
}

## What the seller wrote on the market's plaques: ponies don't know what these are, so not the
## names Anon knows them by (those stay the goods' names, in the briefcase).
const PLAQUES := {
	VINTAGE: "Mystery box with a window",
	FLAT_STAND: "Black mirror on a little table",
	FLAT_WALL: "Black slab (for hanging?)",
	REMOTE: "Button stick",
}

static func plaque(id: String) -> String:
	return str(PLAQUES.get(id, GOODS[id][0] if GOODS.has(id) else id))

## Any Watch Party good (the shop and the briefcase know these).
static func has(id: String) -> bool:
	return GOODS.has(id)

## A television (home furniture with a screen).
static func is_tv(id: String) -> bool:
	return MODELS.has(id)

static func is_remote(id: String) -> bool:
	return id == REMOTE

static func definition(id: String) -> Dictionary:
	if not GOODS.has(id): return {}
	var row: Array = GOODS[id]
	return {"name": row[0], "description": row[3], "stack": 1, "price_bits": row[2], "size_m": row[1], "shop": true}

## The briefcase badges for these goods, in the shop's own style (world/shop/shop_items.gd icon(),
## which would paint them in the apple sapling's green: ext/apple_sapling.gd answers for them).
## Put in shop_items.gd's icon cache once per world.
static func paint_icons() -> void:
	var items := load("res://world/shop/shop_items.gd") as Script
	var icons: Variant = items.get("_icons") if items != null else null
	if not icons is Dictionary: return
	for id: String in GOODS:
		if (icons as Dictionary).has(id): continue
		var colour := Color("7a4e2d") if id == VINTAGE else Color("2b2622")
		var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length()
				if d < 30.0: image.set_pixel(x, y, colour.darkened(0.25) if d > 26.0 else colour)
		(icons as Dictionary)[id] = ImageTexture.create_from_image(image)

## The set's look and working parts under a shop visual (world/shop/shop_item_visual.gd); returns
## the bounds the briefcase sizes the set's collision box from.
static func build_visual(visual: Node3D) -> AABB:
	var id := str(visual.get("item_id"))
	if is_remote(id): return MODEL.build_remote(visual)
	var row: Array = MODELS.get(id, MODELS[VINTAGE])
	var model: Script = row[0]
	var variant: String = row[1]
	model.call("build", visual, variant)
	var working := SET.new()
	working.name = "WatchTv"
	working.model = model
	working.variant = variant
	visual.add_child(working)
	return model.call("bounds", variant)

## The house whose floor is under the first of `points` that is in one, or null
## (world/housing/home_furnishing.gd offer: a TV goes in any house).
static func house_at(tree: SceneTree, points: Array) -> Node3D:
	for point: Variant in points:
		if not point is Vector3: continue
		for candidate: Node in tree.get_nodes_in_group("house_interiors"):
			if not candidate is Node3D or not candidate.has_method("place_id") or not "floors" in candidate: continue
			var house := candidate as Node3D
			var local := house.to_local(point)
			for rect: Variant in house.get("floors"):
				if rect is Rect2 and (rect as Rect2).has_point(Vector2(local.x, local.z)): return house
	return null
