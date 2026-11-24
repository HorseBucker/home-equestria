extends RefCounted
## Town density (2026-11-17): how many houses Ponyville has, for weaker PCs. Settings > Graphics > Town density
## (Follow preset, Minimum, Low, Medium, High; settings_page.gd draws the row). High is the full town (town.tscn,
## 260 houses); the lower settings are their own plans built beside it (tools/town_planner/build/build_density.py:
## town_<setting>.tscn, 75 / 130 / 190 houses), with the same streets, landmarks and lived-in homes.
##
## Made to ship as a mod pack (tools/town_planner/build/make_overhaul_pack.py) that changes none of the scripts
## other mods replace too: the choice is kept in its own file (user://town_density.cfg, not settings.cfg: the
## game's Settings script is loaded before any mod and knows no such row), and the town fills its own root in
## main.tscn (town_root.gd) instead of game.gd instancing it.
##
## The town is a different scene at each setting, so a change applies when the world next loads (Reload world now
## saves and loads it again). The title screen loads the chosen scene alongside main.tscn. A house has one name
## at every setting (a pony's garden finds her house by it).
##
## The player's home is kept at every setting: each world's home is remembered here (user://town_homes.json,
## arrival_story.gd), and when the town is built every remembered home that this setting does not have as a real
## home is put back where it stood, the background houses under it taken out (keep_homes). Homes from before this
## setting existed are found once from each world's saved state (house:x:y:z) against density/houses.json, every
## house that is a real home at any setting.

const SETTINGS := ["minimum", "low", "medium", "high"]
const CHOICES := [["preset", "Follow preset"], ["minimum", "Minimum (75 houses)"], ["low", "Low (130)"], ["medium", "Medium (190)"], ["high", "High (260)"]]
const LABELS := {"minimum": "Minimum", "low": "Low", "medium": "Medium", "high": "High"}
## Follow preset: the town for each quality preset (Very Low, Low, Medium, High, Ultra), when quality.gd has no
## town_density of its own.
const BY_PRESET := ["minimum", "low", "medium", "high", "high"]
const CONFIG := "user://town_density.cfg"
const HIGH_SCENE := "res://world/towns/ponyville/town.tscn"
const HOUSES := "res://world/towns/ponyville/density/houses.json"
const HOMES := "user://town_homes.json"
const WORLDS := "user://worlds"
## The setting the loaded town was built at ("" before a town is built by fill).
static var active := ""
## Names of the homes keep_homes put back into the loaded town.
static var restored: Array[String] = []
static var _kit_cache: Dictionary = {}


## The row's value: "preset" or one of SETTINGS.
static func choice() -> String:
	var config := ConfigFile.new()
	if config.load(CONFIG) != OK: return "preset"
	var value := str(config.get_value("town", "density", "preset"))
	return value if value == "preset" or value in SETTINGS else "preset"


static func set_choice(value: String) -> void:
	if value != "preset" and not value in SETTINGS: return
	var config := ConfigFile.new()
	config.load(CONFIG)
	config.set_value("town", "density", value)
	config.save(CONFIG)


## The setting the player chose, "Follow preset" resolved through the quality preset.
static func chosen() -> String:
	var value := choice()
	if value == "preset":
		var tree := Engine.get_main_loop() as SceneTree
		var quality: Node = tree.root.get_node_or_null("Quality") if tree != null else null
		value = "high"
		if quality != null:
			var own: Variant = quality.call("get_value", "town_density", null)
			value = str(own) if own != null else BY_PRESET[clampi(int(quality.get("preset")), 0, BY_PRESET.size() - 1)]
	return value if value in SETTINGS else "high"


## The setting of the town that is loaded, else of the one that would be.
static func current() -> String:
	return active if active != "" else chosen()


static func scene_path(setting: String) -> String:
	if setting == "high": return HIGH_SCENE
	var path := "res://world/towns/ponyville/town_%s.tscn" % setting
	return path if ResourceLoader.exists(path) else HIGH_SCENE


## Fills `root` (main.tscn's PonyvilleTown, town_root.gd) with the town at the chosen density, the remembered homes
## in it: its metadata, then its children, each owned by `root` as they were by the scene. Uses the title screen's
## threaded load of the same scene when there is one.
static func fill(root: Node3D) -> void:
	var setting := chosen()
	var path := scene_path(setting)
	if path == HIGH_SCENE: setting = "high"
	# for the terrain's pickers of the density's own ground and paint (terrain_sculptor.gd, biome_field.gd), which may run
	# on loading threads and so read a plain value instead of loading this script
	Engine.set_meta("ponyville_town_density", setting)
	var packed: PackedScene = null
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null: packed = load(path) as PackedScene
	if packed == null and path != HIGH_SCENE:
		setting = "high"; path = HIGH_SCENE; packed = load(HIGH_SCENE) as PackedScene
	if packed == null: push_error("[town] could not load " + path); return
	active = setting
	_kit_cache.clear()
	var town := packed.instantiate() as Node3D
	keep_homes(town)
	for key: StringName in town.get_meta_list(): root.set_meta(key, town.get_meta(key))
	if not root.has_meta("town_density"): root.set_meta("town_density", setting)
	var owned: Array[Node] = []
	for node: Node in town.find_children("*", "", true, false):
		if node.owner == town or node.owner == null: owned.append(node)
	for child: Node in town.get_children():
		town.remove_child(child)
		root.add_child(child)
	for node: Node in owned:
		if is_instance_valid(node) and root.is_ancestor_of(node): node.owner = root
	town.free()
	print("[town] density %s: %d houses (%s)" % [setting, _houses(root).size(), path.get_file()])
	# Still water in the Town Square fountain and where ponies drink from it (play test 2026-11-16), here rather than
	# in game_town_adapters.gd. Loaded, not preloaded: a broken script cannot stop boot.
	var fountain_water: Script = load("res://world/water/fountain_water.gd") as Script
	if fountain_water != null and fountain_water.can_instantiate(): fountain_water.call("attach", root)
	# The storage chest in the Town Hall (world/props/town_chest/), where an old world's belongings wait too.
	var chest: Script = load("res://world/props/town_chest/town_chest.gd") as Script
	if chest != null and chest.can_instantiate(): chest.call("attach", root)
	# The walk-in schoolhouse and its school day (mitty's Ponyville Schoolhouse, built in: schoolhouse/classroom.gd).
	var classroom: Script = load("res://world/towns/ponyville/schoolhouse/classroom.gd") as Script
	if classroom != null and classroom.can_instantiate():
		var school: Node = classroom.new()
		school.name = "SchoolhouseClassroom"
		root.add_child(school)
	_drop_lone_flowerbeds(root)


## A flowerbed stands by a house's door (plan_props.py, the full town's real homes); at a lower density the house may
## be gone (2026-11-19 play test: "Houses that are removed on a lower density setting still have their potted flowers
## displayed ... in front of an empty spot of land"). One with no house within LONE m (they all stand within 7 m of
## theirs) goes.
const LONE := 8.0
static func _drop_lone_flowerbeds(root: Node3D) -> void:
	var props := root.get_node_or_null("OutdoorProps")
	if props == null: return
	var houses: Array[Vector2] = []
	for child: Node in root.get_children():
		var n := str(child.name)
		if child is Node3D and (n.begins_with("plot_") or n.begins_with("bg_") or n.begins_with("overhaul_") or child.has_meta("background_house")):
			houses.append(Vector2((child as Node3D).position.x, (child as Node3D).position.z))
	var dropped := 0
	for bed: Node in props.get_children():
		if not (bed is Node3D and str(bed.name).begins_with("flowerbed")): continue
		var at := Vector2((bed as Node3D).position.x, (bed as Node3D).position.z)
		if houses.any(func(h: Vector2) -> bool: return h.distance_to(at) < LONE): continue
		props.remove_child(bed); bed.free(); dropped += 1
	if dropped > 0: print("[town] %d flowerbeds of houses this density does not build taken away" % dropped)


## Settings > Graphics > Reload world now: saves this world and loads it again, as leaving for the title and coming
## back does (the quit autosave is what the reload resumes). Returns what to tell the player.
static func reload_world() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.current_scene if tree != null else null
	var saves: Node = game.get("saves") if game != null and "saves" in game else null
	if not is_instance_valid(saves): return "Not in a world: the town density applies when you enter one."
	if bool(saves.get("busy")) or bool(saves.get("restoring")): return "Saving or loading just now; try again in a moment."
	var inventory: Variant = game.get("inventory")
	var customizer: Variant = (inventory as Object).get("customizer") if inventory is Object else null
	if customizer is Object and bool((customizer as Object).get("opened")): return "Close the wardrobe with Save or Cancel before reloading."
	if not bool(saves.call("save_before_quit")): return "Could not save this world; stayed here so you can retry."
	var script := load("res://world/game_saves.gd") as GDScript
	script.set("pending", {}); script.set("requested_world", str(game.get("context_world_id"))); script.set("start_fresh", false)
	saves.set("restoring", true)
	var director: Variant = game.get("director")
	if director is Object and is_instance_valid(director) and (director as Object).has_method("interrupt"): (director as Object).call("interrupt")
	tree.paused = false
	if tree.reload_current_scene() != OK:
		saves.set("restoring", false); saves.set("_quit_saved", false)
		return "Could not reload the game."
	return "Reloading the world…"


# ---- the player's home at every setting ----

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _homes_doc() -> Dictionary:
	var doc: Variant = _read_json(HOMES)
	if not doc is Dictionary: doc = {}
	if not (doc as Dictionary).get("worlds") is Dictionary: doc["worlds"] = {}
	if not (doc as Dictionary).get("scanned") is Dictionary: doc["scanned"] = {}
	return doc


static func _write_homes(doc: Dictionary) -> void:
	var file := FileAccess.open(HOMES, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(doc, "\t"))


## A house node's home record: its scene and where it stands in the town.
static func _record(house: Node3D) -> Dictionary:
	return {"name": str(house.name), "design": str(house.get_meta("building_design", "")), "scene": house.scene_file_path,
		"transform": var_to_str(house.transform)}


## arrival_story.gd, whenever the world's home is found in the town (every load, and at a grant).
static func remember_home(world_dir: String, interior: Node3D) -> void:
	if world_dir.is_empty() or not is_instance_valid(interior): return
	var house := interior.get_parent() as Node3D
	if house == null or not str(house.name).begins_with("plot_") or house.scene_file_path.is_empty(): return
	if house.get_parent() == null or str(house.get_parent().name) != "PonyvilleTown": return
	var doc := _homes_doc()
	var row := _record(house)
	if doc.worlds.get(world_dir) == row: return
	doc.worlds[world_dir] = row
	_write_homes(doc)


## Every world's remembered home: worlds that are gone are forgotten, and a world never seen here yet is read once
## (its saved home's place id matched to a house that is a real home at some setting).
static func _homes() -> Array:
	var doc := _homes_doc()
	var changed := false
	for world: String in (doc.worlds as Dictionary).keys():
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(world)):
			doc.worlds.erase(world); changed = true
	var dir := DirAccess.open(WORLDS)
	if dir != null:
		for name: String in dir.get_directories():
			var world := WORLDS.path_join(name)
			if doc.worlds.has(world): continue
			var context := world.path_join("context.json")
			if not FileAccess.file_exists(context): continue
			var stamp := str(FileAccess.get_modified_time(context))
			if str(doc.scanned.get(world, "")) == stamp: continue
			doc.scanned[world] = stamp; changed = true
			var row := _from_saved(context)
			if not row.is_empty(): doc.worlds[world] = row
	if changed: _write_homes(doc)
	return (doc.worlds as Dictionary).values()


## The home a world's saved state names (arrival.home, "house:x:y:z" in tenths of a metre), as a house record.
static func _from_saved(context_path: String) -> Dictionary:
	var place := _saved_home(context_path)
	if place.is_empty(): return {}
	var parts := place.split(":")
	if parts.size() != 4 or parts[0] != "house": return {}
	var at := Vector3(float(parts[1]), float(parts[2]), float(parts[3])) / 10.0
	var data: Variant = _read_json(HOUSES)
	if not data is Dictionary: return {}
	var best := {}
	var best_d := 0.6
	for name: String in (data as Dictionary).get("houses", {}):
		var row: Dictionary = data.houses[name]
		var t := _row_transform(row.transform)
		var d := Vector2(t.origin.x - at.x, t.origin.z - at.z).length()     # (the ground's height is the build's)
		if d < best_d: best_d = d; best = {"name": name, "design": str(row.design), "scene": str(row.scene), "transform": var_to_str(t)}
	return best


static func _saved_home(context_path: String) -> String:
	var doc: Variant = _read_json(context_path)
	if not doc is Dictionary: return ""
	var state: Variant = (doc as Dictionary).get("state", doc)
	if not state is Dictionary: return ""
	var arrival: Variant = (state as Dictionary).get("arrival")
	return str((arrival as Dictionary).get("home", "")) if arrival is Dictionary else ""


## houses.json writes a transform as the scene file does: the basis by rows, then the origin.
static func _row_transform(v: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(v[0], v[3], v[6]), Vector3(v[1], v[4], v[7]), Vector3(v[2], v[5], v[8])), Vector3(v[9], v[10], v[11]))


## The town's houses: real homes (plot_*) and background houses (bg_*), with their design.
static func _houses(town: Node) -> Array:
	var out: Array = []
	var holder := town.get_node_or_null("BackgroundHouses")
	for parent: Node in [town, holder]:
		if parent == null: continue
		for child: Node in parent.get_children():
			var name := str(child.name)
			if not child is Node3D or not (name.begins_with("plot_") or name.begins_with("bg_")): continue
			var design := str(child.get_meta("building_design", ""))
			if design.is_empty():
				var m := RegEx.create_from_string("house_(\\w)(_bg)?\\.").search(child.scene_file_path)
				if m != null: design = m.get_string(1)
			out.append([child, design])
	return out


static var _footprints: Dictionary = {}

## A house's footprint on the ground (x, z), from its design's outline at scale 1 and its transform.
static func _footprint(design: String, t: Transform3D) -> PackedVector2Array:
	if _footprints.is_empty():
		var data: Variant = _read_json(HOUSES)
		if data is Dictionary: _footprints = (data as Dictionary).get("footprints", {})
	var out := PackedVector2Array()
	for p: Array in _footprints.get(design, []):
		var w := t * Vector3(float(p[0]), 0.0, float(p[1]))
		out.append(Vector2(w.x, w.z))
	return out


## Puts every remembered home back into `town` (not yet in the tree) where this setting has no real home at its spot:
## the houses its footprint would stand on are taken out first, never a pony's home or another remembered one.
static func keep_homes(town: Node3D) -> void:
	restored.clear()
	var homes := _homes()
	if homes.is_empty(): return
	var houses := _houses(town)
	var kept_spots: Array[Vector3] = []
	for home: Variant in homes:
		var spot: Variant = str_to_var(str((home as Dictionary).get("transform", ""))) if home is Dictionary else null
		if spot is Transform3D: kept_spots.append((spot as Transform3D).origin)
	for home: Variant in homes:
		if not home is Dictionary: continue
		var t: Variant = str_to_var(str(home.get("transform", "")))
		var scene := str(home.get("scene", ""))
		var design := str(home.get("design", ""))
		if not t is Transform3D or not ResourceLoader.exists(scene): continue
		var at: Vector3 = (t as Transform3D).origin
		var standing := false
		for pair: Array in houses:
			var node: Node3D = pair[0]
			if is_instance_valid(node) and str(node.name).begins_with("plot_") and node.transform.origin.distance_to(at) < 0.3 and pair[1] == design:
				standing = true; break
		if standing: continue
		var mine := _footprint(design, t)
		if mine.size() >= 3:
			var inset := Geometry2D.offset_polygon(mine, -0.1)      # touching is not standing on
			if not inset.is_empty(): mine = inset[0]
		for pair: Array in houses:
			var node: Node3D = pair[0]
			if not is_instance_valid(node) or node.get_parent() == null: continue
			var spot: Transform3D = node.transform if node.get_parent() == town else (node.get_parent() as Node3D).transform * node.transform
			if spot.origin.distance_to(at) > 40.0: continue
			if node.has_meta("reserved_for"): continue        # a pony's home stays
			# another remembered home standing as a real one stays (a background house on a home's spot goes)
			if str(node.name).begins_with("plot_") and kept_spots.any(func(k: Vector3) -> bool: return k.distance_to(spot.origin) < 0.3): continue
			var theirs := _footprint(str(pair[1]), spot)
			if mine.size() < 3 or theirs.size() < 3 or Geometry2D.intersect_polygons(mine, theirs).is_empty(): continue
			node.get_parent().remove_child(node); node.free()
		var house := (load(scene) as PackedScene).instantiate() as Node3D
		var name := str(home.get("name", "plot_home"))
		house.name = name if town.get_node_or_null(name) == null else name + "_home"
		house.transform = t
		house.set_meta("building_design", design)
		house.set_meta("residential_plot", str(house.name))
		house.set_meta("vacant", true)
		town.add_child(house)
		restored.append(str(house.name))
		houses = _houses(town)
		var cleared := _clear_ground(town, _footprint(design, t))
		print("[town] kept a home at this density: %s (%s) at %s%s" % [house.name, design, at, " (%d trees and props on its spot taken away)" % cleared if cleared > 0 else ""])


## A kept home stands where this setting's own trees and street things may have been planted, as the house was not
## in its plan (2026-11-23 player report: "Changing from high to minimum density caused a tree to spawn in the house I
## claimed"): the trees within TREE_ROOM m of its footprint (a crown reaches that far), and the props (benches,
## lamps, flowerbeds) within PROP_ROOM m, are taken away. Returns how many went.
const TREE_ROOM := 2.5
const PROP_ROOM := 0.6
static func _clear_ground(town: Node3D, foot: PackedVector2Array) -> int:
	if foot.size() < 3: return 0
	var gone := 0
	for pair: Array in [["TownTrees", TREE_ROOM], ["OutdoorProps", PROP_ROOM]]:
		var holder := town.get_node_or_null(str(pair[0])) as Node3D
		var grown := Geometry2D.offset_polygon(foot, float(pair[1]))
		if holder == null or grown.is_empty(): continue
		var area: PackedVector2Array = grown[0]
		for child: Node in holder.get_children():
			if not child is Node3D: continue
			var p := holder.transform * (child as Node3D).position
			if not Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), area): continue
			holder.remove_child(child); child.free(); gone += 1
	return gone


# ---- the gardens ----

## The kit's rows (placements.json "entries") for the town at `setting`: below high, the full town's gardens (rows
## of group house:*, id *_ovNNNN) give way to that town's own (ponyville_kit/density/<setting>.json).
static func kit_entries(parsed: Dictionary, setting: String = "") -> Array:
	if setting.is_empty(): setting = current()
	var entries: Array = parsed.get("entries", [])
	if setting == "high": return entries
	if _kit_cache.has(setting): return _kit_cache[setting]
	var patch: Variant = _read_json("res://world/props/ponyville_kit/density/%s.json" % setting)
	if not patch is Dictionary: return entries
	var full_garden := RegEx.create_from_string("_ov\\d+$")
	var out: Array = []
	for row: Variant in entries:
		if row is Dictionary and str(row.get("group", "")).begins_with("house:") and full_garden.search(str(row.get("id", ""))) != null: continue
		out.append(row)
	out.append_array((patch as Dictionary).get("entries", []))
	_kit_cache[setting] = out
	return out


# ---- the settings row ----

## The note when the setting changes (settings.gd): when it applies, and any world whose home could not be found
## (it would be lost at a setting without it).
static func change_note() -> String:
	var setting := chosen()
	var text := "Town density %s: " % LABELS[setting]
	if active != "" and setting == active: return text + "as the town is now."
	text += "from the next time a world loads (in a world: Reload world now). Your home stays yours at every density."
	var lost := homes_at_risk()
	if not lost.is_empty():
		text += " Warning: the home in %s could not be found, so at this density it would be lost and you would need a new one." % ", ".join(lost)
	return text


## Worlds with a saved home in the town that is not remembered (user://town_homes.json could not be written): only
## those could lose it. (A home from before the overhaul is in no town at any setting, and is not counted.)
static func homes_at_risk() -> Array:
	_homes()
	var known := _homes_doc().worlds as Dictionary
	var out: Array = []
	var dir := DirAccess.open(WORLDS)
	if dir == null: return out
	for name: String in dir.get_directories():
		var world := WORLDS.path_join(name)
		if known.has(world): continue
		if not _from_saved(world.path_join("context.json")).is_empty(): out.append("world \"%s\"" % name)
	return out


## A world's home is no more (overhaul_migration.gd let it go): it is not put back at any setting.
static func forget_home(world_dir: String) -> void:
	var doc := _homes_doc()
	if not (doc.worlds as Dictionary).has(world_dir): return
	doc.worlds.erase(world_dir)
	_write_homes(doc)
