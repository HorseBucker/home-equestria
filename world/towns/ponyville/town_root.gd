extends Node3D
## Ponyville's town root in main.tscn (2026-11-17): it fills itself with the town at the chosen density
## (town_density.gd fill) as it becomes ready, before game.gd's own _ready finds it at Zones/PonyvilleTown and
## attaches its buildings. So the game's own scripts (game.gd, which other mods replace too) need no change.

func _ready() -> void:
	# built-in mods' own packs stand down first, before any house or walk grid is made (built_in_mods.gd)
	preload("res://world/towns/ponyville/built_in_mods.gd").stand_down(get_tree())
	preload("res://world/towns/ponyville/town_density.gd").fill(self)
	# the Board Games mod's chess table, at the remade town's spot (plaza_table_spot.gd)
	preload("res://world/towns/ponyville/plaza_table_spot.gd").watch(self)
	# the Pedal Copter mod's parking spot by Sugarcube Corner (copter_spot.gd)
	preload("res://world/towns/ponyville/copter_spot.gd").attach(self)
	# the hot-air balloon goes back to its pad after a while away (balloon_fetch.gd)
	preload("res://world/towns/ponyville/balloon_fetch.gd").attach(self)
	# street lamps do not light the rooms through their walls (interior_light_layer.gd)
	preload("res://world/towns/ponyville/interior_light_layer.gd").attach(self)
	# a safety net and a trace for quitting (quit_watch.gd)
	preload("res://world/towns/ponyville/quit_watch.gd").attach(self)
	# the watch's day: counted from the world's first day, with the day of the week (watch_day.gd, world_days.gd)
	preload("res://world/towns/ponyville/watch_day.gd").attach(self)
	# Flower Gifts' patches and Anon's Mailbox, set off the old town's spots (mod_spots.gd)
	preload("res://world/towns/ponyville/mod_spots.gd").attach(self)
