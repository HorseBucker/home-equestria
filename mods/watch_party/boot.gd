extends RefCounted
## Watch Party's last step while the game boots. mod.json "extends" lists the mod's script
## extensions (ext/, which the game's mod loader applies: world/modding/mod_loader.gd
## apply_extensions, from autoload/settings.gd _init) and then this script, which extends no game
## script: the loader only loads it, and Godot runs _static_init() as it compiles. By then all of
## this mod's extensions stand at their game paths, so the scripts another mod had loaded before
## that are pointed at them (hooks.gd repair).
## The loader says this script "does not extend a game script"; that warning is expected.

const HOOKS := preload("res://mods/watch_party/hooks.gd")

static func _static_init() -> void:
	HOOKS.repair()
