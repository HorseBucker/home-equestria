extends RefCounted
## Two parts of the remade Ponyville a player can switch off (2026-11-18 play test: "Add a setting option for the
## flower meadow and carrot farm to turn them on or off"), in Settings > Graphics under Town density
## (settings_page.gd _town_extras_rows). Kept in their own file, like the town density (the game's Settings
## autoload loads before mods, so it cannot be given new keys by the overhaul).
## - Flower meadow: "auto" follows the graphics preset (Quality "flower_meadow": off at the lowest), or on, or off.
## - Carrot farm: Carrot Top's crop rows by her farmhouse, east of the town (kit group "carrot-farm" east of
##   FARM_WEST; the few rows at Sweet Apple Acres stay). Off, she does not go to tend them either (tend_fields.gd).
## Both apply at once: kit_dressing.gd listens in the group GROUP.
## (2026-11-19: the meadow is gone from the town and neither is in Settings any more; the farm always shows.)

const CONFIG := "user://town_extras.cfg"
const GROUP := "town_extras"
const MEADOW_CHOICES := [["auto", "With preset"], ["on", "On"], ["off", "Off"]]
const FARM_CHOICES := [["on", "On"], ["off", "Off"]]
## Crop rows east of this x are Carrot Top's farm.
const FARM_WEST := 100.0


static func _read(key: String, fallback: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG) != OK: return fallback
	return str(cfg.get_value("town", key, fallback))


static func choice(key: String) -> String:
	return _read(key, "auto" if key == "flower_meadow" else "on")


static func set_choice(key: String, value: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG)
	cfg.set_value("town", key, value)
	cfg.save(CONFIG)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null: tree.call_group(GROUP, "town_extras_changed")


static func meadow_on() -> bool:
	match choice("flower_meadow"):
		"on": return true
		"off": return false
	var tree := Engine.get_main_loop() as SceneTree
	var quality: Node = tree.root.get_node_or_null("Quality") if tree != null else null
	return quality == null or bool(quality.call("get_value", "flower_meadow", true))


static func carrot_farm_on() -> bool:
	return true      # (no longer a setting: a choice saved earlier is not left hiding the farm)


## A placement row of Carrot Top's farm.
static func farm_row(row: Dictionary) -> bool:
	return str(row.get("group", "")) == "carrot-farm" and float(row.get("x", 0.0)) > FARM_WEST
