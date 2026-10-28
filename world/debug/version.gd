extends RefCounted
## Game version. The base comes from project.godot application/config/version, written by
## tools/build/release.py. A patch pack (tools/build/release_patch.py) carries PATCH with its own
## version and the base it was made against; it counts only on that exact base.
##   label.text = preload("res://world/debug/version.gd").text()   # "0.1.0-alpha"

const PATCH := "res://world/update/patch_version.json"

static func text() -> String:
	# A run from source has every change since the last release: its project.godot number would
	# undersell it (dev 2026-10-28: "why is my equestria --desktop build on v0.0.4").
	if not OS.has_feature("template"): return "dev"
	var patch := patch_info()
	if not patch.is_empty(): return str(patch.version)
	var base := base_version()
	return base if base != "" else "dev"

## The full build this copy was installed from.
static func base_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

## {"version", "base"} of the mounted patch pack, {} without one (or one made for another base).
static func patch_info() -> Dictionary:
	if not FileAccess.file_exists(PATCH): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATCH))
	if not (parsed is Dictionary): return {}
	var info: Dictionary = parsed
	if str(info.get("base", "")) != base_version() or str(info.get("version", "")) == "": return {}
	return info
