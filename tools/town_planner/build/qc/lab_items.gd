extends Node
## What the item catalog says about items (2026-11-18: telling mods' items from the game's). Prints ITEM lines, quits.
##   godot --path <project> -- --new-game --skip-title --lab res://tools/town_planner/build/qc/lab_items.gd --ids a,b
var game: Node
func _ready() -> void: _go.call_deferred()
func _go() -> void:
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")): break
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(5.0).timeout
	var C := preload("res://world/inventory/item_catalog.gd")
	var args := OS.get_cmdline_user_args()
	for id: String in (args[args.find("--ids") + 1] if "--ids" in args else "food:pinkie-copter,goods:watch-tv-vintage,river-fish,notebook,goods:footstool").split(","):
		var sc: PackedScene = C.scene(id)
		var ic: Texture2D = C.icon(id)
		var def: Dictionary = C.definition(id)
		print("ITEM %s has %s scene %s icon %s def %s" % [id, C.has(id), sc.resource_path if sc != null else "null", ic.resource_path if ic != null else "null", str(def).left(200)])
	get_tree().quit()
