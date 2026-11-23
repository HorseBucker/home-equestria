extends Node
## What stands, in the remade town, where community mods built on the old map put things (2026-11-23 mod audit): node
## paths they look up, and their hard-coded spots (the ground there, the nearest house or landmark, in town or not).
## Prints MODSPOT lines.
const PATHS := ["Zones/PonyvilleTown/sugarcube_corner/BakeryRoom",
	"Zones/PonyvilleTown/RNLScenery/West/Library/goldenoaklibrary_01/UsableLibrary/LibraryInterior",
	"Zones/PonyvilleTown/RNLScenery/Central/Boutique/rarityboutique_01/BoutiqueRoomFrame/UsableBoutique",
	"Zones/PonyvilleTown/RNLScenery/Central/Boutique/rarityboutique_01/BoutiqueRoomFrame/UsableBoutique/BoutiqueInterior"]
const SPOTS := {"favor-AJ wagon": Vector3(90, -4.5, -440), "favor-AJ spare wheel (old barn's back wall)": Vector3(3.95, -7.38, -443.74),
	"favor-PP grove medium": Vector3(144, -20, 30), "favor-PP grove large": Vector3(155, -20, 34), "favor-PP bag": Vector3(136.2, -20.1, 19.9),
	"favor-RD cave": Vector3(460, 0, -450), "favor-RD boutique door fallback": Vector3(49, -13.1, -177),
	"favor-TS Dash waits": Vector3(-175.5, -6.6, -331.5), "favor-TS cloudbuster": Vector3(-175, -6.6, -336)}
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	await get_tree().create_timer(25.0).timeout
	for p: String in PATHS: print("MODSPOT path %s: %s" % [p, "FOUND" if game.get_node_or_null(p) != null else "MISSING"])
	for id: String in ["appleacres_wagon_01", "trixie_cannon_01"]:
		var n := get_tree().root.find_child(id, true, false) as Node3D
		print("MODSPOT scenery %s: %s" % [id, n.global_position.snapped(Vector3.ONE * 0.1) if n != null else "MISSING"])
	var places := preload("res://world/navigation/place_directory.gd").entries(get_tree())
	var plots: Array = []
	for n: Node in get_tree().root.find_child("PonyvilleTown", true, false).get_children():
		if str(n.name).begins_with("plot_") or n.has_meta("background_house"): plots.append(n)
	for bg: Node in get_tree().root.find_children("*", "Node3D", true, false):
		if bg.has_meta("background_house"): plots.append(bg)
	for name: String in SPOTS:
		var at: Vector3 = SPOTS[name]
		var ground := WorldTerrain.instance.height_at(at)
		var near_place := ""; var best := 1e9
		for e: Dictionary in places:
			var d := Vector2(e.position.x - at.x, e.position.z - at.z).length()
			if d < best and not str(e.kind).begins_with("region"): best = d; near_place = "%s (%.0f m)" % [e.label, d]
		var near_house := 1e9
		for p: Node in plots: near_house = minf(near_house, Vector2((p as Node3D).global_position.x - at.x, (p as Node3D).global_position.z - at.z).length())
		print("MODSPOT %s at (%.0f, %.0f): ground %.1f (mod's y %.1f) | nearest place %s | nearest house %.0f m" % [name, at.x, at.z, ground, at.y, near_place, near_house])
	get_tree().quit()
