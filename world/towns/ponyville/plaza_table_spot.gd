extends Node
## The Board Games mod's public chess table in the remade town (2026-11-18 play test: "There's a chess set floating
## in the sky at X 252 Z -258. Move it to X 119 Z -188, and have it so both players have the fountain to their side").
## The mod (MLPChag's board_games, world/minigames/board_games/plaza_table.gd) builds the table at a fixed pose
## measured in the old town, under the town root, before navigation is built. Its files stay as they are: town_root.gd
## watches for the table and, the moment its first part goes in (after the mod has set the old pose, before the
## seats and the game exist), sets it at the spot the plan's "chess table" note gives (density/houses.json,
## build_density.py). Everything else of the table is built relative to it, so it all moves together.
## Grass grows on under it (play test: "I want to play chess on the grass near the fountain"): the mod's grass
## patch is taken back.

const NAME := "PlazaGameTable"
const GRASS_KEY := "plaza-game-table"
const HOUSES := "res://world/towns/ponyville/density/houses.json"


## Watch `town` for the mod's table: a watcher node under it. Idempotent.
static func watch(town: Node) -> void:
	if town.get_node_or_null("PlazaTableSpot") != null: return
	var watcher: Node = (load("res://world/towns/ponyville/plaza_table_spot.gd") as GDScript).new()
	watcher.name = "PlazaTableSpot"
	town.add_child(watcher)
	town.child_entered_tree.connect(watcher._on_town_child)


func _on_town_child(node: Node) -> void:
	if str(node.name) != NAME or not node is Node3D: return
	node.child_entered_tree.connect(_place.bind(node), CONNECT_ONE_SHOT)


func _place(_part: Node, table: Node3D) -> void:
	var spot: Variant = pose()
	if spot == null: return
	table.global_transform = spot
	if table.is_in_group("grass_patches"): table.remove_from_group("grass_patches")
	if table.has_meta("grass_key"): table.remove_meta("grass_key")
	if table.is_inside_tree(): table.get_tree().call_group("grass_footprints", "remove_footprint", GRASS_KEY)
	print("[town] chess table at (%.1f, %.1f), on the grass by the fountain" % [(spot as Transform3D).origin.x, (spot as Transform3D).origin.z])


## The table's pose from the build, or null.
static func pose() -> Variant:
	if not FileAccess.file_exists(HOUSES): return null
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(HOUSES))
	if not doc is Dictionary or not (doc as Dictionary).get("chess_table") is Dictionary: return null
	var row: Dictionary = doc.chess_table
	return Transform3D(Basis(Vector3.UP, float(row.get("yaw", 0.0))), Vector3(float(row.x), float(row.y), float(row.z)))
