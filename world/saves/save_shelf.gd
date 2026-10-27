extends RefCounted
## The player's own order on the saved games (dev 2026-10-27: "we need more place with folders
## and tag for save"): a name, tags and a star per checkpoint, and a name, colour and picture per
## world, which the saves browser (world/ui/save_browser.gd) shows as a folder. Kept per world in
## <world>/shelf.json beside the checkpoints, so a checkpoint is never rewritten to rename it.
##
## Also the file work the title can do without gameplay loaded (save_catalogue.gd's rule): a
## checkpoint moves to or from the archive with all its companions, or is deleted with them, and a
## whole world can be deleted. GameSaves uses the same moves for the running world.
const SAVE_FILE := preload("res://world/save_file.gd")
const FILE := "shelf.json"
const VERSION := 1
const MAX_NAME := 60
const MAX_TAG := 24
const MAX_TAGS := 8
## World folder pictures (world/ui/menu_icon.gd FOLDER_KINDS) and swatch count (menu_style.gd).
const ICONS := ["heart", "star_filled", "apple", "cloud", "moon", "sun", "flower", "gem", "butterfly", "cupcake", "horseshoe", "tree"]
const COLORS := 8


## <root>/<world>/saves/<file> or <root>/<world>/saves/archive/<file> → <root>/<world>.
static func world_folder_of(save_path: String) -> String:
	var folder := save_path.get_base_dir()
	if folder.get_file() == "archive": folder = folder.get_base_dir()
	return folder.get_base_dir()


## A checkpoint's key in its world's shelf: "slot_1.json", "archive/autosave_….json".
static func key_of(save_path: String) -> String:
	return ("archive/" if save_path.get_base_dir().get_file() == "archive" else "") + save_path.get_file()


# ------------------------------------------------------------------ reading and writing
## {"version", "world": {"name", "color", "icon"}, "saves": {key: {"name", "tags", "star"}}}; a missing
## or damaged file reads as an empty shelf.
static func read(world_folder: String) -> Dictionary:
	var doc: Variant = SAVE_FILE.parse(world_folder.path_join(FILE), 256 * 1024)
	return _clean(doc if doc is Dictionary else {})


static func _clean(doc: Dictionary) -> Dictionary:
	var world: Dictionary = doc.get("world") if doc.get("world") is Dictionary else {}
	var out_world := {}
	if world.get("name") is String and not str(world.name).strip_edges().is_empty(): out_world.name = clean_name(str(world.name))
	if (world.get("color") is int or world.get("color") is float) and int(world.color) >= 0 and int(world.color) < COLORS: out_world.color = int(world.color)
	if world.get("icon") is String and str(world.icon) in ICONS: out_world.icon = str(world.icon)
	var saves := {}
	var rows: Dictionary = doc.get("saves") if doc.get("saves") is Dictionary else {}
	for key: Variant in rows:
		if not key is String or not rows[key] is Dictionary: continue
		var row: Dictionary = rows[key]
		var out := {}
		if row.get("name") is String and not str(row.name).strip_edges().is_empty(): out.name = clean_name(str(row.name))
		if row.get("tags") is Array:
			var tags: Array[String] = []
			for tag: Variant in row.tags:
				if tag is String and not clean_tag(tag).is_empty() and clean_tag(tag) not in tags and tags.size() < MAX_TAGS: tags.append(clean_tag(tag))
			if not tags.is_empty(): out.tags = tags
		if row.get("star") == true: out.star = true
		if not out.is_empty(): saves[key] = out
	return {"version": VERSION, "world": out_world, "saves": saves}


static func write(world_folder: String, doc: Dictionary) -> bool:
	return SAVE_FILE.write(world_folder.path_join(FILE), _clean(doc)) == OK


static func clean_name(text: String) -> String:
	return text.strip_edges().replace("\n", " ").left(MAX_NAME)


static func clean_tag(text: String) -> String:
	return text.strip_edges().replace("\n", " ").left(MAX_TAG)


# ------------------------------------------------------------------ one checkpoint
## {"name", "tags", "star"} the player gave the checkpoint at `save_path` ({} when none).
static func save_info(save_path: String, shelf: Dictionary = {}) -> Dictionary:
	if shelf.is_empty(): shelf = read(world_folder_of(save_path))
	return (shelf.saves.get(key_of(save_path), {}) as Dictionary).duplicate(true)


## Merges `changes` ("name", "tags", "star") into the checkpoint's row; empty values clear.
static func set_save(save_path: String, changes: Dictionary) -> bool:
	var folder := world_folder_of(save_path)
	var shelf := read(folder)
	var row: Dictionary = (shelf.saves.get(key_of(save_path), {}) as Dictionary).duplicate(true)
	row.merge(changes, true)
	shelf.saves[key_of(save_path)] = row
	return write(folder, shelf)


## The checkpoint moved (archive, back from it): its name, tags and star go with it.
static func move(from_path: String, to_path: String) -> void:
	var folder := world_folder_of(from_path)
	if world_folder_of(to_path) != folder: return
	var shelf := read(folder)
	if not shelf.saves.has(key_of(from_path)): return
	shelf.saves[key_of(to_path)] = shelf.saves[key_of(from_path)]
	shelf.saves.erase(key_of(from_path))
	write(folder, shelf)


static func forget(save_path: String) -> void:
	var folder := world_folder_of(save_path)
	var shelf := read(folder)
	if shelf.saves.erase(key_of(save_path)): write(folder, shelf)


# ------------------------------------------------------------------ worlds
## Changes the world folder's "name", "color" (swatch index) or "icon".
static func set_world(world_folder: String, changes: Dictionary) -> bool:
	var shelf := read(world_folder)
	var world: Dictionary = shelf.world.duplicate()
	world.merge(changes, true)
	shelf.world = world
	return write(world_folder, shelf)


## A world's folder look: its chosen picture and swatch, else ones picked from its id.
static func world_look(world_id: String, shelf: Dictionary) -> Dictionary:
	var digest := world_id.md5_text()
	var world: Dictionary = shelf.get("world", {})
	return {"icon": str(world.get("icon", ICONS[("0x" + digest.substr(12, 4)).hex_to_int() % ICONS.size()])),
		"color": int(world.get("color", ("0x" + digest.substr(16, 4)).hex_to_int() % COLORS)),
		"name": str(world.get("name", ""))}


## Every tag used in any world under `root`, most used first.
static func all_tags(root: String) -> Array[String]:
	var counts := {}
	if DirAccess.dir_exists_absolute(root):
		for world: String in DirAccess.get_directories_at(root):
			var shelf := read(root.path_join(world))
			for key: String in shelf.saves:
				for tag: String in shelf.saves[key].get("tags", []): counts[tag] = int(counts.get(tag, 0)) + 1
	var tags: Array[String] = []
	for tag: String in counts: tags.append(tag)
	tags.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b] or (counts[a] == counts[b] and a < b))
	return tags


# ------------------------------------------------------------------ files
## The menu sidecars beside a checkpoint (save_catalogue.gd): screenshot, header, story journal.
static func sidecars(save_path: String) -> Array[String]:
	var base := save_path.get_basename()
	return [base + ".preview.jpg", base + ".preview.meta", base + ".story.db", base + ".story.db.previous"]


## Every file of one checkpoint: the file, its backup and its sidecars.
static func files_of(save_path: String) -> Array[String]:
	var files: Array[String] = [save_path, save_path + ".previous"]
	files.append_array(sidecars(save_path))
	return files


## Where archiving a checkpoint puts it: <saves>/archive/<name>_<time>.json.
static func archive_target(save_path: String) -> String:
	var folder := save_path.get_base_dir()
	return folder.path_join("archive").path_join("%s_%s_%s.json" % [save_path.get_file().get_basename(),
		str(Time.get_unix_time_from_system()).replace(".", "_"), str(Time.get_ticks_usec())])


## Where a checkpoint taken back out of the archive goes: a manual save of its world.
static func restore_target(save_path: String) -> String:
	var folder := save_path.get_base_dir()
	if folder.get_file() == "archive": folder = folder.get_base_dir()
	return new_save_path(folder)


## A free name for a new manual save in a world's saves folder: save_<time>.json.
static func new_save_path(saves_folder: String) -> String:
	var target := saves_folder.path_join("save_%s.json" % SAVE_FILE.stamp())
	var n := 2
	while FileAccess.file_exists(target) or FileAccess.file_exists(target + ".previous"):
		target = saves_folder.path_join("save_%s_%d.json" % [SAVE_FILE.stamp(), n]); n += 1
	return target


## Moves every file of a checkpoint together (a backup left behind would come back as a save).
## "" when done; otherwise what went wrong, with any moved file put back.
static func move_checkpoint(source: String, target: String) -> String:
	if not FileAccess.file_exists(source) and not FileAccess.file_exists(source + ".previous"):
		return "no checkpoint file was found"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	var sources := files_of(source)
	var targets := files_of(target)
	var moved: Array[int] = []
	for i in sources.size():
		if not FileAccess.file_exists(sources[i]): continue
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(sources[i]), ProjectSettings.globalize_path(targets[i])) != OK:
			# A denied companion move must not report success or silently split a save.
			var restored := true
			moved.reverse()
			for prior in moved:
				if DirAccess.rename_absolute(ProjectSettings.globalize_path(targets[prior]), ProjectSettings.globalize_path(sources[prior])) != OK: restored = false
			return "the files could not be moved" if restored else "only some files moved; nothing was deleted"
		moved.append(i)
	move(source, target)
	return ""


## Deletes a checkpoint and its companions, companions first so a denied deletion leaves the
## primary loadable. "" when done.
static func delete_checkpoint(path: String) -> String:
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".previous"): return "no checkpoint file was found"
	var files := files_of(path)
	files.reverse()
	for file in files:
		if FileAccess.file_exists(file) and DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) != OK:
			return "not every file could be deleted"
	forget(path)
	return ""


## Deletes the world `world_id` under `root`: its saves, journal, books, everything. "" when done.
static func delete_world(root: String, world_id: String) -> String:
	if world_id.is_empty() or world_id in [".", ".."] or world_id.contains("/") or world_id.contains("\\"): return "not a world folder"
	var folder := root.path_join(world_id)
	if not DirAccess.dir_exists_absolute(folder): return "the world is already gone"
	return "" if _remove_tree(ProjectSettings.globalize_path(folder)) else "some of its files could not be deleted"


## Depth first; a linked folder inside is unlinked, never followed.
static func _remove_tree(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null: return false
	# A stray dotfile left behind would keep the folder (and report a failure).
	dir.include_hidden = true
	var ok := true
	for child: String in dir.get_directories():
		if dir.is_link(child): ok = DirAccess.remove_absolute(path.path_join(child)) == OK and ok
		else: ok = _remove_tree(path.path_join(child)) and ok
	for file: String in dir.get_files():
		ok = DirAccess.remove_absolute(path.path_join(file)) == OK and ok
	return DirAccess.remove_absolute(path) == OK and ok
