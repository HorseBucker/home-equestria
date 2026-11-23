extends Node
## What each category of the town actually costs the renderer: from fixed viewpoints, the frame's objects, primitives
## (LODs, culling, occlusion and every shadow pass included) and draw calls, then again with each category hidden;
## the difference is its share. Also the sun's shadow passes (shadows off) and the whole town (zone hidden).
## Read-only (everything is shown again). Prints ATTRIB lines.
const VIEWS := {"street_eye": [Vector3(20, -10.3, -175), Vector3(120, -11, -190)], "square_eye": [Vector3(100, -10.3, -175), Vector3(140, -11, -200)],
	"market_eye": [Vector3(110, -10.3, -300), Vector3(130, -11, -270)], "rooftop": [Vector3(60, 12, -150), Vector3(150, -12, -260)],
	"overview": [Vector3(80, 90, -60), Vector3(80, -12, -220)]}

func _ready() -> void:
	_go.call_deferred()

func _category(node: Node, zone: Node) -> String:
	var up: Node = node
	var src := ""
	while up != null and up != zone:
		if src.is_empty() and not up.scene_file_path.is_empty(): src = up.scene_file_path.get_file()
		var n := str(up.name)
		if n in ["HouseInterior", "RestaurantInterior", "Interior", "Furniture", "PonyBed"] or n.begins_with("HouseInterior"): return "interiors (furniture, linings, curtains, lamps)"
		up = up.get_parent()
	var path := str(zone.get_path_to(node))
	if path.begins_with("MergedShadows"): return "merged shadow casters"
	if path.begins_with("MergedTreeShadows") or src == "town_trees.scn" or path.contains("TownTrees"): return "town trees (+ their shadows)"
	if src.ends_with("_bg.scn"): return "background houses"
	if src.contains("lining") or src in ["curtains.glb", "pony_bed.scn", "bedside-table.glb", "dresser.glb", "clock.glb", "wall_sconce.glb", "wall_lantern.glb", "table_lamp.glb", "cone_lamp.glb", "sofa.glb", "pantry.glb", "kitchen-island.glb", "compact-kitchen.scn", "cooking_tools.scn", "cottage-crockery-rack.scn"]: return "interiors (furniture, linings, curtains, lamps)"
	if src.begins_with("house_") : return "real house exteriors"
	if path.begins_with("PonyvilleKit") or path.begins_with("BatchedProps"): return "kit props and gardens"
	if path.begins_with("SweetAppleAcresDressing"): return "Sweet Apple Acres dressing"
	if src == "streetlamp.scn" or src.begins_with("outdoor_props"): return "street props"
	if src == "prefab.scn" or path.begins_with("RNLScenery"): return "landmark buildings and scenery"
	return "other"

func _measure() -> Array:
	await get_tree().process_frame; await get_tree().process_frame; await get_tree().process_frame
	var o := 0; var p := 0; var d := 0
	for i in 12:
		await get_tree().process_frame
		o += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		p += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		d += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	return [o / 12, p / 12, d / 12]

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	game.get("player").global_position = Vector3(120, -10, -200)
	await get_tree().create_timer(60.0).timeout
	var zone: Node3D = get_tree().root.find_child("PonyvilleTown", true, false)
	print("ATTRIB density\t%s" % preload("res://world/towns/ponyville/town_density.gd").current())
	var cats := {}
	for node: Node in zone.find_children("*", "GeometryInstance3D", true, false):
		if not (node as GeometryInstance3D).visible: continue
		var c := _category(node, zone)
		if not cats.has(c): cats[c] = []
		cats[c].append(node)
	var suns: Array = []
	for l: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		if (l as DirectionalLight3D).shadow_enabled and (l as DirectionalLight3D).visible: suns.append(l)
	var cam := Camera3D.new(); get_tree().current_scene.add_child(cam); cam.far = 1500.0
	for view: String in VIEWS:
		cam.global_position = VIEWS[view][0]; cam.look_at(VIEWS[view][1], Vector3.UP); cam.make_current()
		game.get("player").global_position = VIEWS[view][0] + Vector3(0, -1, 0)
		await get_tree().create_timer(8.0).timeout
		var base: Array = await _measure()
		print("ATTRIB %s\tALL\tobjects %d\tprims %d\tdraws %d" % [view, base[0], base[1], base[2]])
		base = await _measure()
		for l: DirectionalLight3D in suns: l.shadow_enabled = false
		var ns: Array = await _measure()
		for l: DirectionalLight3D in suns: l.shadow_enabled = true
		print("ATTRIB %s\tsun shadow passes\tobjects %d\tprims %d\tdraws %d" % [view, base[0] - ns[0], base[1] - ns[1], base[2] - ns[2]])
		for c: String in cats:
			base = await _measure()
			for n: GeometryInstance3D in cats[c]: n.visible = false
			var m: Array = await _measure()
			for n: GeometryInstance3D in cats[c]: n.visible = true
			print("ATTRIB %s\t%s\tobjects %d\tprims %d\tdraws %d" % [view, c, base[0] - m[0], base[1] - m[1], base[2] - m[2]])
		base = await _measure()
		zone.visible = false
		var z: Array = await _measure()
		zone.visible = true
		print("ATTRIB %s\twhole town zone\tobjects %d\tprims %d\tdraws %d" % [view, base[0] - z[0], base[1] - z[1], base[2] - z[2]])
	get_tree().quit()
