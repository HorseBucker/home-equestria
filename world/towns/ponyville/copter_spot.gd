extends Node
## Where the Pedal Copter mod (pinkie_copter, by another author; its files stay as they are) parks a world's copter
## in the remade town (2026-11-18 play test: "make it so that the one in town hall spawns facing south east and is
## positioned at X -4 Z -127"). The mod works its spot out once from Sugarcube Corner's door and keeps it with the
## world (Mods.state("pinkie_copter").home); a world from the old town kept the old town's spot, which in the new
## one is beside the Town Hall. This sets the kept spot to SPOT, facing FACING, and moves the copter
## set down in town (not in the player's hands or the chest) there too, once. Height: the mod's own fit test there
## (copter_home.gd _fits) once the ground is loaded, else the terrain's height plus the copter's half height (the
## mod checks the spot again itself whenever the player is near, and keeps it while it fits).
## Nothing happens without that mod.

const MOD := "pinkie_copter"
const HOME_SCRIPT := "res://mods/pinkie_copter/copter_home.gd"
const ITEM := "food:pinkie-copter"
const SPOT := Vector2(-4.0, -127.0)
## South-east: the copter's nose (its -Z, as the mod faces it) toward +x +z.
const FACING := Vector3(1.0, 0.0, 1.0)
const CHECK_EVERY := 2.0
## A kept spot this near SPOT is already ours.
const SAME := 0.75
const STORE := preload("res://world/inventory/inventory_store.gd")
const CHEST_HOME := "town_hall_chest"

var _wait := 1.0
var _home: Node
var _done := false


static func attach(town: Node) -> void:
	if town.get_node_or_null("CopterSpot") != null: return
	var node: Node = (load("res://world/towns/ponyville/copter_spot.gd") as GDScript).new()
	node.name = "CopterSpot"
	town.add_child(node)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0 or _done: return
	_wait = CHECK_EVERY
	var mods: Node = get_node_or_null("/root/Mods")
	if mods == null or not mods.has_method("state"): _done = true; return
	if not is_instance_valid(_home): _home = _find_home()
	if not is_instance_valid(_home): return
	var game: Node = mods.get("game") if "game" in mods else null
	if not is_instance_valid(game) or game.get("title_active") == true: return
	var state: Dictionary = mods.call("state", MOD)
	var old: Variant = _decode(state.get("home"))
	if old is Transform3D and Vector2((old as Transform3D).origin.x - SPOT.x, (old as Transform3D).origin.z - SPOT.y).length() < SAME:
		_done = true; return
	var pose: Variant = _pose()
	if not pose is Transform3D: return
	var spot := pose as Transform3D
	state["home"] = {"at": [snappedf(spot.origin.x, 0.01), snappedf(spot.origin.y, 0.01), snappedf(spot.origin.z, 0.01)], "yaw": snappedf(spot.basis.get_euler().y, 0.001)}
	if mods.has_method("save_changed"): mods.call("save_changed")
	var moved := _move_waiting(game, old)
	print("[town] the Pedal Copter's spot is by Sugarcube Corner at (%.1f, %.1f)%s" % [spot.origin.x, spot.origin.z, ", and the copter parked in town moved there" if moved else ""])
	_done = true


## The pose at SPOT: the mod's own fit when the ground there is loaded, else on the terrain.
func _pose() -> Variant:
	var basis := Basis.looking_at(FACING.normalized(), Vector3.UP)
	var ground := -12.0
	if is_instance_valid(WorldTerrain.instance):
		var h: float = WorldTerrain.instance.height_at(Vector3(SPOT.x, 0.0, SPOT.y))
		if is_finite(h): ground = h
	var guess := Transform3D(basis, Vector3(SPOT.x, ground, SPOT.y))
	if _home.has_method("_fits"):
		var fit: Variant = _home.call("_fits", guess)
		if fit is Transform3D: return fit
	var half := float((_home.get_script() as Script).get_script_constant_map().get("HALF", 0.3))
	return Transform3D(basis, guess.origin + Vector3.UP * half)


## The copter set down in town (wherever it was left or parked: the play test's stood by the Town Hall) goes to the
## new spot, once, as the spot is set; not one in his hands or kept in the chest.
func _move_waiting(game: Node, _old: Variant) -> bool:
	var ui: Variant = game.get("inventory")
	var store: Variant = (ui as Object).get("inventory") if ui is Object and is_instance_valid(ui) else null
	if not store is Object: return false
	var mods: Node = get_node_or_null("/root/Mods")
	var spot: Variant = _decode((mods.call("state", MOD) as Dictionary).get("home"))
	for token: Variant in ((store as Object).get("loans") as Dictionary).keys():
		var loan: Dictionary = (store as Object).get("loans")[token]
		if str(loan.get("id", "")) != ITEM or not loan.get("world_transform") is Array or str(loan.get("furnishing_home", "")) == CHEST_HOME: continue
		var body: Variant = ((ui as Object).get("loose") as Dictionary).get(token)
		if body is Node3D and is_instance_valid(body):
			if ((ui as Object).get("held") as Dictionary).values().has(body): return false
			(body as Node3D).global_transform = spot
		(store as Object).call("update_drops", {token: spot})
		return true
	return false


## The mod's spot keeper: its entry node (/root/Mods/pinkie_copter, main.gd) holds it as `home`.
func _find_home() -> Node:
	var main: Node = get_node_or_null("/root/Mods/" + MOD)
	var home: Variant = main.get("home") if main != null else null
	return home as Node if home is Node and is_instance_valid(home) and (home as Node).get_script() != null and ((home as Node).get_script() as Script).resource_path == HOME_SCRIPT else null


static func _decode(value: Variant) -> Variant:
	if not value is Dictionary or not (value as Dictionary).get("at") is Array or ((value as Dictionary).at as Array).size() != 3: return null
	var at: Array = value.at
	return Transform3D(Basis(Vector3.UP, float(value.get("yaw", 0.0))), Vector3(float(at[0]), float(at[1]), float(at[2])))
