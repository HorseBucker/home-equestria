extends RefCounted
## Watch Party's game hooks: the scripts in res://mods/watch_party/ext/, each an ordinary
## `extends "res://<game script>"`. Since game 0.3.1 the game's own mod loader applies them (mod.json
## "extends", world/modding/mod_loader.gd apply_extensions): it works in the exported game and it
## stacks, so another mod can extend the same game script before or after this one. (Up to 1.1.0
## this mod applied them itself, which lost to any mod that had loaded a game script first and
## would have been dropped by any mod that extended the same script later.)
## This script does the two things the game's loader does not:
## - base(): the script below this mod's extension of a game script, for the static functions an
##   extension overrides (they call the game's version through it; `super` is for instances).
## - repair(): a game script that was loaded before its extension was applied (a mod earlier in
##   the list loaded it: in 0.3.1 Mirror Pool's patch pack loads Mirror Pool's main script while
##   the game boots, and with it the shop goods, the furniture rules, the action schema and the
##   market; game log 2026-11-12, no television existed) is still what the scripts compiled
##   before then hold in their preload constants. Those holders are compiled again, which makes
##   them read the game path anew and get the extension. Nothing runs yet while the game boots,
##   so compiling them again is safe; a script that has instances is left alone.
## Every ext script preloads this file, so the first one the loader compiles runs _static_init()
## below, before any of this mod's extensions stands at a game path.

## The game scripts this mod extends (mod.json "extends" lists the extensions in this order: each
## game script's own preloads reach only the ones above it).
const TARGETS := [
	"res://world/items/apple_sapling.gd",
	"res://world/housing/furnishing_rules.gd",
	"res://world/ai/pony_intent_consistency.gd",
	"res://world/ai/speech_vocabulary.gd",
	"res://world/ai/pony_action_executor.gd",
	"res://world/housing/home_furnishing.gd",
	"res://world/ai/pony_action_schema.gd",
	"res://world/mechanics/market/market.gd",
	"res://world/shop/shop_world.gd",
	"res://world/ai/speech_input.gd",
	"res://world/ai/conversation_director.gd",
	"res://world/ui/interaction_hints.gd",
]
## How an extension's source names its game script (every ext script has this constant).
const MARK := "const WATCH_PARTY_PATH := \"%s\""
## The game's loader keeps its copies of the scripts it extends here.
const BASES := "user://mods/.bases"
## Never compiled again: the mod loader is running, and Settings is being made, while repair() runs.
const LEFT_ALONE := ["res://autoload/settings.gd", "res://world/modding/mod_loader.gd", "res://world/modding/bundled_mods.gd", "res://world/modding/mods.gd"]

## Game path -> the script that stood there before this mod's extension (loaded early by another
## mod). Emptied by repair().
static var _early: Dictionary = {}
## Game path -> [the script standing at the game path when it was looked up, the script below this
## mod's extension].
static var _bases: Dictionary = {}
## After the game has booted nothing changes at the game paths any more (settle()).
static var _settled := false
## What repair() did, for the log line main.gd prints: [early scripts, holders compiled again, failed].
static var report: Array = [0, 0, PackedStringArray()]

static func _static_init() -> void:
	for target: String in TARGETS:
		if ResourceLoader.has_cached(target):
			var standing: Variant = ResourceLoader.get_cached_ref(target)
			if standing is Script: _early[target] = standing

## The script below this mod's extension of `target` (the game's own, or another mod's extension
## of it).
static func base(target: String) -> Script:
	var kept: Variant = _bases.get(target)
	if _settled and kept is Array: return (kept as Array)[1] as Script
	var top := load(target) as Script
	if kept is Array and (kept as Array)[0] == top: return (kept as Array)[1] as Script
	var mine := _mine(top, target)
	# Not among the scripts standing there (this mod's hook is missing): the game's own answers.
	var below: Script = mine.get_base_script() if mine != null else top
	_bases[target] = [top, below]
	return below

## This mod's extension among the scripts standing at a game path (`top` and the scripts it
## extends), or null: the one whose source names the game path (MARK); a script kept without its
## source is known by the constant instead, the lowest that has it (a script extending this mod's
## may show the constant too).
static func _mine(top: Script, target: String) -> Script:
	var mark := MARK % target
	var script := top
	while script != null:
		if script.has_source_code() and script.source_code.contains(mark): return script
		script = script.get_base_script()
	var lowest: Script = null
	script = top
	while script != null:
		if str(script.get_script_constant_map().get("WATCH_PARTY_PATH", "")) == target: lowest = script
		script = script.get_base_script()
	return lowest

## Called once the game has booted (main.gd): the bases are looked up one last time and kept.
static func settle() -> void:
	_settled = false
	_bases.clear()
	for target: String in TARGETS: base(target)
	_settled = true

## Whether this mod's extension is among the scripts standing at `target`.
static func hooked(target: String) -> bool:
	return _mine(load(target) as Script, target) != null

## Compiles again every loaded script that still holds a game script as it was before this mod
## extended it. Called by boot.gd, the last entry of mod.json "extends".
static func repair() -> void:
	var stale: Array = []
	for target: String in _early:
		if hooked(target): stale.append(_early[target])
	report = [stale.size(), 0, PackedStringArray()]
	if stale.is_empty():
		_early.clear()
		return
	var holders: Array = []
	var paths: Array = []
	for path: String in _script_paths():
		if path in LEFT_ALONE or not ResourceLoader.has_cached(path): continue
		var found: Variant = ResourceLoader.get_cached_ref(path)
		if not found is Script or found in stale or found in holders: continue
		if _holds(found as Script, stale):
			holders.append(found)
			paths.append(path)
	var failed: PackedStringArray = []
	for index in holders.size():
		var script: Script = holders[index]
		if script.reload() != OK or _holds(script, stale): failed.append(str(paths[index]).get_file())
	report = [stale.size(), holders.size() - failed.size(), failed]
	_early.clear()
	if failed.is_empty():
		print("[watch_party] %d game script(s) were loaded before Watch Party (by another mod); the %d script(s) that used them now use the hooks" % [stale.size(), holders.size()])
	else:
		push_warning("[watch_party] %d game script(s) were loaded before Watch Party (by another mod), and these could not be pointed at the hooks: %s. Some of the mod will not work; switching the other mods off one at a time shows which one it is" % [stale.size(), ", ".join(failed)])

## A script whose parent, or one of whose constants (its preloads), is one of `stale`.
static func _holds(script: Script, stale: Array) -> bool:
	if script.get_base_script() in stale: return true
	for value: Variant in script.get_script_constant_map().values():
		if value is Script and value in stale: return true
	return false

## Every script path that may be loaded: the game's and the mods' (res://, where the exported game
## lists x.gd as x.gdc and x.gd.remap) and the loader's copies.
static func _script_paths() -> PackedStringArray:
	var out: PackedStringArray = []
	var seen := {}
	var folders: Array = ["res://", BASES]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		var dir := DirAccess.open(folder)
		if dir == null: continue
		for sub: String in dir.get_directories():
			if not sub.begins_with("."): folders.append(folder.path_join(sub))
		for name: String in dir.get_files():
			var path := ""
			if name.ends_with(".gd"): path = folder.path_join(name)
			elif name.ends_with(".gdc"): path = folder.path_join(name.get_basename() + ".gd")
			elif name.ends_with(".gd.remap"): path = folder.path_join(name.trim_suffix(".remap"))
			if path.is_empty() or seen.has(path): continue
			seen[path] = true
			out.append(path)
	return out
