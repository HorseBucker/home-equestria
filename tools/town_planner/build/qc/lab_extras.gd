extends Node
## The flower meadow and carrot farm switches (town_extras.gd, 2026-11-18): how many of the kit's batches show with
## each choice. Prints EXTRAS lines; quits. Leaves the choices as they were.
##   godot --xr-mode off --path <project> -- --new-game --skip-title --lab res://tools/town_planner/build/qc/lab_extras.gd
const EXTRAS := preload("res://world/towns/ponyville/town_extras.gd")


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var kit: Node = null
	for i in 2400:
		kit = get_tree().get_first_node_in_group(EXTRAS.GROUP)
		if kit != null: break
		await get_tree().create_timer(0.25).timeout
	if kit == null: print("EXTRAS FAIL no kit"); get_tree().quit(); return
	await get_tree().create_timer(3.0).timeout
	var before := [EXTRAS.choice("flower_meadow"), EXTRAS.choice("carrot_farm")]
	for pair: Array in [["auto", "on"], ["off", "off"], ["on", "on"]]:
		EXTRAS.set_choice("flower_meadow", pair[0]); EXTRAS.set_choice("carrot_farm", pair[1])
		await get_tree().process_frame
		var meadow: Array = kit.get("_meadow"); var farm: Array = kit.get("_farm")
		print("EXTRAS meadow %s farm %s: meadow %d/%d shown, farm %d/%d shown" % [pair[0], pair[1],
			meadow.filter(func(p: Node3D) -> bool: return p.visible).size(), meadow.size(),
			farm.filter(func(p: Node3D) -> bool: return p.visible).size(), farm.size()])
	EXTRAS.set_choice("flower_meadow", before[0]); EXTRAS.set_choice("carrot_farm", before[1])
	print("EXTRAS done")
	get_tree().quit()
