extends "res://world/mechanics/market/market.gd"
## Watch Party: a television lying in the Everfree is free to whoever finds it (dev 2026-11-07: "the
## whole point of going out and finding them"). The forest sets are one-item shop displays
## (res://mods/watch_party/forest_finds.gd, display ids "watch_party:forest:..."), so picking one up
## is the game's own purchase (world/shop/shop_purchase.gd), which asks this module for the price
## (live_price → price_for): for those displays it is nothing. The market tent's sets keep their
## prices. Applied by the game (mod.json "extends"); see res://mods/watch_party/hooks.gd.

## Marks this script as Watch Party's extension of the game script (hooks.gd).
const WATCH_PARTY_PATH := "res://world/mechanics/market/market.gd"
const WATCH_PARTY_LOADER := preload("res://mods/watch_party/hooks.gd")

const WATCH_PARTY_FOREST := "watch_party:forest:"

func price_for(display_id: String, item_id: String, default_price: int) -> int:
	if display_id.begins_with(WATCH_PARTY_FOREST): return 0
	return super(display_id, item_id, default_price)
