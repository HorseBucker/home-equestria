extends RefCounted
## Watch Party: applies the mod's script extensions (res://mods/watch_party/ext/, each an ordinary
## `extends "res://<game script>"` that calls the game's own code for everything it does not
## change). It works like world/modding/mod_loader.gd apply_extensions, with one fix that makes
## extensions work in the exported game:
## - The game's loader copies a compiled game script to user://mods/.bases/N.gdc and lets the
##   extension extend that .gdc path. Godot names a script's class after its .gd path
##   (GDScript::canonicalize_path), so the compile fails ("Could not find class N.gd in N.gdc",
##   game log 2026-11-01). The loader then falls back to a plain take-over, which broke every later
##   preload of that game script (game_saves.gd would not parse). So mod.json "extends" lists only
##   boot.gd, which extends no game script: the loader loading it is what runs apply() (boot.gd
##   _static_init), while the game boots and before any mod's entry script.
## - Here the copy is N.gdc behind an N.gd.remap, and the extension extends N.gd. That is exactly how
##   the exported game reaches its own scripts (res://x.gd.remap -> x.gdc).
## Nothing is taken over unless the extension compiled; a failure only logs, and that game script
## stays the game's own. main.gd runs apply() again from _init (switched on mid-game: nothing was
## applied at boot); targets applied already are skipped. A game script loaded before that (another
## mod loaded it first) is left alone: the hook waits for the next launch.

## Game script -> this mod's extension. The order matters: each game script's own preloads reach
## only the ones above it, so every script is extended before anything else loads it.
const EXTENSIONS := [
	["res://world/items/apple_sapling.gd", "res://mods/watch_party/ext/apple_sapling.gd"],
	["res://world/housing/furnishing_rules.gd", "res://mods/watch_party/ext/furnishing_rules.gd"],
	["res://world/ai/pony_intent_consistency.gd", "res://mods/watch_party/ext/pony_intent_consistency.gd"],
	["res://world/ai/speech_vocabulary.gd", "res://mods/watch_party/ext/speech_vocabulary.gd"],
	["res://world/ai/pony_action_executor.gd", "res://mods/watch_party/ext/pony_action_executor.gd"],
	["res://world/housing/home_furnishing.gd", "res://mods/watch_party/ext/home_furnishing.gd"],
	["res://world/ai/pony_action_schema.gd", "res://mods/watch_party/ext/pony_action_schema.gd"],
	# The market preloads the shop goods (apple_sapling) and furniture rules, so it comes after them;
	# the shop and the director preload the market, so they come after it (playtest 2026-11-07: with
	# the market first, four hooks above were skipped and no television existed in a new world).
	["res://world/mechanics/market/market.gd", "res://mods/watch_party/ext/market.gd"],
	["res://world/shop/shop_world.gd", "res://mods/watch_party/ext/shop_world.gd"],
	# The director preloads the microphone (speech_input), so it comes after it.
	["res://world/ai/speech_input.gd", "res://mods/watch_party/ext/speech_input.gd"],
	["res://world/ai/conversation_director.gd", "res://mods/watch_party/ext/conversation_director.gd"],
	["res://world/ui/interaction_hints.gd", "res://mods/watch_party/ext/interaction_hints.gd"],
]

## Game path -> the script its extension extends (the game's own, as copied), for the static
## functions an extension overrides: they call the game's version through it (base()).
static var _bases: Dictionary = {}
## The extensions in use. The resource cache does not own a script it lists, so this keeps them.
static var _kept: Array[Script] = []
## Game paths extended this run (switching the mod off and on again does not apply them twice).
static var applied: PackedStringArray = []

## The game's own script below this mod's extension of `target`.
static func base(target: String) -> Script:
	return _bases.get(target) as Script

static func apply(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var skipped: PackedStringArray = []
	for index in EXTENSIONS.size():
		var target: String = EXTENSIONS[index][0]
		if target in applied: continue
		if not _apply(target, EXTENSIONS[index][1], folder, index): skipped.append(target.get_file())
	if skipped.is_empty(): print("[watch_party] game hooks ready (%d script extensions)" % applied.size())
	else: push_warning("[watch_party] game hooks missing for %s; see the lines above" % ", ".join(skipped))

static func _apply(target: String, extension: String, folder: String, index: int) -> bool:
	if ResourceLoader.has_cached(target):
		push_warning("[watch_party] %s was loaded before Watch Party started (switched on mid-game, or another mod loaded it); its hook starts after a restart" % target)
		return false
	var text := FileAccess.get_file_as_string(extension)
	var head := RegEx.create_from_string("(?m)^extends\\s+\"" + _escape(target) + "\"")
	if text.is_empty() or head.search(text) == null:
		push_warning("[watch_party] %s is missing or does not extend %s" % [extension, target])
		return false
	var copy := _copy_base(target, folder, index)
	if copy.is_empty():
		push_warning("[watch_party] could not read the game's %s" % target)
		return false
	var own := folder.path_join("wp_%d_extension.gd" % index)
	if not _write_text(own, head.sub(text, "extends \"%s\"" % copy)): return false
	var script := ResourceLoader.load(own, "", ResourceLoader.CACHE_MODE_REPLACE) as GDScript
	if script == null:
		push_warning("[watch_party] %s did not compile over %s (the errors above say why); the game's script is unchanged" % [extension, target])
		return false
	# Taking over moves the script onto the game path in both caches; the reload compiles it under
	# the game path's class name, so later preloads of the game script find the class they expect.
	script.take_over_path(target)
	if script.reload() != OK:
		script.take_over_path(own)   # gives the game path back: the game's own script loads there
		push_warning("[watch_party] %s did not compile at %s; the game's script is unchanged" % [extension, target])
		return false
	_bases[target] = script.get_base_script()
	_kept.append(script)
	applied.append(target)
	print("[watch_party] extends ", target)
	return true

## The script that stands at `target` now, copied to `folder` as wp_N.gd: as source in a source
## run (or when another mod replaced the file with source), else as compiled tokens wp_N.gdc behind
## wp_N.gd.remap. The copy's path ("wp_N.gd"), or "" when the game script cannot be read.
static func _copy_base(target: String, folder: String, index: int) -> String:
	var copy := folder.path_join("wp_%d.gd" % index)
	var tokens := copy.get_basename() + ".gdc"
	var real := target
	if FileAccess.file_exists(target + ".remap"):
		var remap := ConfigFile.new()
		if remap.load(target + ".remap") == OK: real = str(remap.get_value("remap", "path", target))
	elif not FileAccess.file_exists(target) and FileAccess.file_exists(target.get_basename() + ".gdc"):
		real = target.get_basename() + ".gdc"
	for stale: String in [copy, copy + ".remap", tokens]:
		if FileAccess.file_exists(stale): DirAccess.remove_absolute(ProjectSettings.globalize_path(stale))
	if real.get_extension() == "gdc":
		var bytes := FileAccess.get_file_as_bytes(real)
		if bytes.is_empty(): return ""
		var file := FileAccess.open(tokens, FileAccess.WRITE)
		if file == null: return ""
		file.store_buffer(bytes)
		file.close()
		if not _write_text(copy + ".remap", "[remap]\n\npath=\"%s\"\n" % tokens): return ""
		return copy
	var source := FileAccess.get_file_as_string(real)
	if source.is_empty(): return ""
	# A copy must not claim the game script's global class name (mod_loader.gd _write does the same).
	source = RegEx.create_from_string("(?m)^class_name\\s+\\w+\\s*").sub(source, "", true)
	return copy if _write_text(copy, source) else ""

static func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[watch_party] cannot write %s" % path)
		return false
	file.store_string(text)
	file.close()
	return true

static func _escape(text: String) -> String:
	var out := ""
	for c in text: out += ("\\" + c) if c in ".^$*+?()[]{}|\\/" else c
	return out
