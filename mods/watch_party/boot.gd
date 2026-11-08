extends RefCounted
## Watch Party's earliest moment: listed in mod.json "extends", so the game's mod loader loads this
## script while it boots (world/modding/mod_loader.gd apply_extensions, from autoload/settings.gd
## _init: after the packs mount, before any other game script and before any mod's entry script).
## Godot runs _static_init() as the script compiles, and that applies the mod's script extensions
## (ext_loader.gd) right then. Applied later, from main.gd, they lost to other mods whose entry
## scripts preload game scripts on the way (playtest 2026-11-05: Pinkie's copter, PonyPussyParadise
## and others had already loaded the shop, furnishing and AI scripts, so four hooks were skipped).
## This script extends no game script, so the loader then says it "does not extend a game script"
## and leaves it be; that warning is expected.

const EXTENSIONS := preload("res://mods/watch_party/ext_loader.gd")
## Mods.data_folder("watch_party") + "/ext" (the Mods autoload does not exist yet).
const FOLDER := "user://mods/data/watch_party/ext"

static func _static_init() -> void:
	# The loader keeps no reference to this script, and the resource cache owns nothing: held by
	# the engine, ext_loader.gd (and the extensions it keeps in its static vars) stays loaded until
	# main.gd preloads it too.
	Engine.set_meta(&"watch_party_extensions", EXTENSIONS)
	EXTENSIONS.apply(FOLDER)
