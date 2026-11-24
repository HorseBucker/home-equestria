extends Node
## Other authors' mods that put things at the old town's fixed spots, set right in the remade town (2026-11-23 player
## report and play test). Their files stay as they are: this moves what they have placed, once each time they place
## it. Nothing happens without them.
## - Flower Gifts (flower_gifts): its wild flower patches stand at fixed points measured in the old town, beside its
##   flowerbeds and gardens, and set themselves on whatever is under them ("Flowers are spawning on roofs and
##   underwater"; play test: "Make sure they don't spawn on town or dirt roads either ... have them spread out across
##   town, or however that mod was originally meant to work"). As the mod meant, the town's all-year and summer
##   flowers grow beside the town's gardens: each such patch in the old town is given a garden flower row of the
##   remade town (the kit's rose beds and flower clumps by the houses, at this density), chosen so they spread over the
##   whole town (each next one the farthest from those chosen), and grows on open lawn beside it. The snapdragons
##   by the windmill and the moonflowers by Fluttershy's cottage move with those. Open lawn: the terrain itself under
##   it (no roof, floor or prop), no water over it, and no street, path, dirt road or river bed paint within
##   CLEAR m (street_rest.gd texture_at).
## - Anon's Mailbox (mailbox): it stands 2.6 m out from the player's door step and 1.5 m aside, which in the remade
##   town, where houses stand close to their street, is in the street. Every real home has its own garden mailbox
##   (the kit's red one, set beside the house off the street by plan_props.py): the mod's mailbox takes its place
##   (play test: "I'd like to have the green mailbox take the place of the red mailbox there"), and the red one is
##   hidden while it stands there. A house without one (a home kept from another density): beside its front wall.
## - Watch Party (watch_party) before 1.2.1, the version players have (1.2.0, and 1.0.0 in the game's bundle): its
##   television stand and the remote's counter stand at a fixed point by the old market, which in the remade town is
##   on a stream's bank, and the vintage set lies at a fixed point in the Everfree measured from the old cottage
##   (2026-11-24 play test: "the TVs are not in the market tent after 3 days, they are where the market used to be on
##   the old map"). The stand and counter move into the market's white tent (tent_friagram_lightbrown_01), as 1.2.1
##   and later set them (spots.json "market": its offset and facing in the tent's frame), and the vintage set to the
##   Everfree's edge behind Fluttershy's cottage (spots.json "overhaul" "forest"): the spot the mod keeps for it in
##   the world's save is set there before it is laid out, and a set laid out at the old spot is moved. From 1.2.1 the
##   mod knows the town itself (it has spots.json) and nothing here acts.

const OLD_TOWN := Vector4(-340.0, -630.0, 540.0, 230.0)   # the old town's edge (density/old_town.json) and 40 m
const TOWN_FLOWERS := ["food:daisies", "food:roses", "food:lavender", "food:tulips", "food:sunflowers", "food:marigolds"]
const GARDEN_KINDS := ["rose_bed", "lupin_clump", "daisy_clump", "sunflower_clump"]
const TOWN_HALL := Vector2(135.5, -175.9)
## Landmarks the mod's flowers were measured by: old spot -> new spot (rnl_scenery.json, before and after).
const MOVED_WITH := {
	"food:snapdragons": [Vector2(-190.0, -335.0), Vector2(310.0, -200.8)],    # the windmill
	"food:moonflowers": [Vector2(151.0, -10.0), Vector2(407.9, 1.1)],         # Fluttershy's cottage
}
const STREETS := [22, 1, 4, 5, 18, 23]   # sage street, dirt trail, town dirt, rail gravel, river bed, stream bed
const CLEAR := 1.0
const APART := 3.0
const SEARCH := 14.0
const STEP := 0.75
const WATER := preload("res://world/water/water_contact.gd")
const STREET := preload("res://world/characters/navigation/street_rest.gd")
const KIT_SPOTS := preload("res://world/props/ponyville_kit/kit_spots.gd")
const KIT_MAILBOX_SCENE := "res://world/props/ponyville_kit/mailbox.scn"
const OWN_MAILBOX := 12.0      # a house's own garden mailbox is this near its door
const CHECK_EVERY := 1.0
const WP_SPOTS := "res://mods/watch_party/spots.json"
const WP_MARKET := "RNLScenery/Town/Market/"
const WP_PINK_TENT := "tent_friagram_pinkish_01"       # the mod's displays are its children
const WP_WHITE_TENT := "tent_friagram_lightbrown_01"
const WP_OLD_STAND := Vector2(206.27, -217.76)         # ext/shop_world.gd WATCH_PARTY_AT
const WP_OLD_FACING := 351.0
const WP_OLD_REMOTE := Vector3(2.705, 0.0, 0.15)       # its _watch_party_remote_at(): the remote's counter, in the stand's frame
const WP_STAND_OFFSET := Vector2(0.27, 0.24)           # 1.2.1's spots.json "market", in the white tent's frame
const WP_STAND_FACING := 351.0
const WP_VINTAGE := "goods:watch-tv-vintage"
const WP_OLD_FOREST := Vector2(136.26, 104.24)         # finds.gd FOREST (forest_finds.gd moves it up to 13 m off)
const WP_FOREST := [415.0, -3.62, 73.0, 275.0]         # spots.json "overhaul" "forest", facing in degrees

var _wait := 2.0
## Garden rows given to the mod's patches: patch index -> Vector2 (worked out once per world and density).
var _targets: Dictionary = {}
var _targets_for: Node
var _placed: Array[Vector2] = []
## The mod's child count when every patch was placed (-1: not yet).
var _settled := -1
## The garden mailbox hidden under the mod's: [MultiMesh, instance, its transform].
var _hidden: Array = []


static func attach(town: Node) -> void:
	if town.get_node_or_null("ModSpots") != null: return
	var node: Node = (load("res://world/towns/ponyville/mod_spots.gd") as GDScript).new()
	node.name = "ModSpots"
	town.add_child(node)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0: return
	_wait = CHECK_EVERY
	var mods := get_node_or_null("/root/Mods")
	if mods == null: set_process(false); return
	var flowers := mods.get_node_or_null("flower_gifts")
	if flowers != null: _flowers(flowers)
	_mailbox(mods.get_node_or_null("mailbox"))
	if mods.get_node_or_null("watch_party") != null and not FileAccess.file_exists(WP_SPOTS): _watch_party(mods)


# ---- Flower Gifts ----

func _flowers(mod: Node) -> void:
	var world := get_viewport().get_world_3d() if get_viewport() != null else null
	if world == null or not is_instance_valid(WorldTerrain.instance): return
	if _targets_for != mod: _plan_flowers(mod); _settled = -1
	# once every patch the mod has built is placed, nothing is looked at again until it builds more
	if mod.get_child_count() == _settled: return
	var waiting := false
	var space := world.direct_space_state
	for child: Node in mod.get_children():
		if not child is Node3D or not str(child.name).begins_with("FlowerPatch") or child.has_meta("overhaul_checked"): continue
		var patch := child as Node3D
		var at := patch.global_position
		if at.x < OLD_TOWN.x or at.x > OLD_TOWN.z or at.z < OLD_TOWN.y or at.z > OLD_TOWN.w:
			patch.set_meta("overhaul_checked", true); continue
		var index := str(child.name).substr(11).to_int()
		var aim := at
		if _targets.has(index): aim = Vector3((_targets[index] as Vector2).x, at.y, (_targets[index] as Vector2).y)
		if not is_finite(WorldTerrain.instance.height_at(aim)): waiting = true; continue   # its ground is not loaded yet
		var spot: Variant = _nearest_lawn(space, aim)
		if not spot is Vector3: waiting = true; continue
		patch.set_meta("overhaul_checked", true)
		_placed.append(Vector2((spot as Vector3).x, (spot as Vector3).z))
		var shift := (spot as Vector3) - at
		if shift.length() < 0.05: continue
		patch.global_position = spot
		if patch.has_meta("point") and patch.get_meta("point") is Vector3: patch.set_meta("point", (patch.get_meta("point") as Vector3) + shift)
		print("[town] Flower Gifts' %s (%s) grows at (%.1f, %.1f)" % [patch.name, str(patch.get_meta("flower_id", "")), (spot as Vector3).x, (spot as Vector3).z])
	if not waiting: _settled = mod.get_child_count()


## Which garden row each of the mod's town patches grows by, and where the ones measured by a landmark go.
func _plan_flowers(mod: Node) -> void:
	_targets_for = mod
	_targets.clear(); _placed.clear()
	var script := mod.get_script() as Script
	var rows: Variant = script.get_script_constant_map().get("PATCHES") if script != null else null
	if not rows is Array: return
	var town: Array[int] = []
	for index in (rows as Array).size():
		var row: Array = rows[index]
		var id := str(row[0]); var p: Vector3 = row[1]
		if p.x < OLD_TOWN.x or p.x > OLD_TOWN.z or p.z < OLD_TOWN.y or p.z > OLD_TOWN.w: continue
		if MOVED_WITH.has(id):
			var pair: Array = MOVED_WITH[id]
			_targets[index] = Vector2(p.x, p.z) - (pair[0] as Vector2) + (pair[1] as Vector2)
		elif id in TOWN_FLOWERS:
			town.append(index)
	# the town's garden flower rows, spread: each next one the farthest from all chosen so far
	KIT_SPOTS._index()
	var gardens: Array[Vector2] = []
	for kind: String in GARDEN_KINDS:
		for id: String in KIT_SPOTS._by_kind.get(kind, []):
			var r: Dictionary = KIT_SPOTS._by_id[id]
			if str(r.get("group", "")).begins_with("house:"): gardens.append(Vector2(float(r.x), float(r.z)))
	if gardens.is_empty(): return
	var chosen: Array[Vector2] = []
	var gap: Array[float] = []
	for g: Vector2 in gardens: gap.append(g.distance_to(TOWN_HALL) * 0.001)   # first: the one nearest the Town Hall
	for n in mini(town.size(), gardens.size()):
		var best := 0
		for i in gardens.size():
			if n == 0: best = i if gap[i] < gap[best] else best
			elif gap[i] > gap[best]: best = i
		chosen.append(gardens[best])
		for i in gardens.size(): gap[i] = gardens[i].distance_to(gardens[best]) if n == 0 else minf(gap[i], gardens[i].distance_to(gardens[best]))
		gap[best] = -1.0
	for n in chosen.size(): _targets[town[n]] = chosen[n]


## The open lawn nearest `from` (rings of STEP m out to SEARCH m) with room round it and no other patch within APART m.
func _nearest_lawn(space: PhysicsDirectSpaceState3D, from: Vector3) -> Variant:
	var radius := 0.0
	while radius <= SEARCH:
		var steps := 1 if radius == 0.0 else maxi(8, int(TAU * radius / STEP))
		for i in steps:
			var a := TAU * float(i) / float(steps)
			var x := from.x + cos(a) * radius; var z := from.z + sin(a) * radius
			if _placed.any(func(p: Vector2) -> bool: return p.distance_to(Vector2(x, z)) < APART): continue
			var spot: Variant = _lawn(space, x, z)
			if spot == null: continue
			var roomy := true
			for d: Vector2 in [Vector2(CLEAR, 0), Vector2(-CLEAR, 0), Vector2(0, CLEAR), Vector2(0, -CLEAR)]:
				if _lawn(space, x + d.x, z + d.y) == null: roomy = false; break
			if roomy: return spot
		radius += STEP
	return null


## The terrain at (x, z) when it is lawn: nothing else on it, no water over it, no street paint. Else null.
static func _lawn(space: PhysicsDirectSpaceState3D, x: float, z: float) -> Variant:
	var ground: float = WorldTerrain.instance.height_at(Vector3(x, 0.0, z))
	if not is_finite(ground): return null
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, ground + 40.0, z), Vector3(x, ground - 2.0, z), 1)
	var hit := space.intersect_ray(query)
	if not hit.is_empty() and float(hit.position.y) > ground + 0.2: return null
	if WATER.surface_above(space, Vector3(x, ground, z)) > ground - 0.3: return null
	if STREET.texture_at(Vector3(x, ground, z)) in STREETS: return null
	return Vector3(x, ground, z)


# ---- Watch Party (before 1.2.1) ----

func _watch_party(mods: Node) -> void:
	var town := get_parent()
	_wp_pads(town)
	var pink := town.get_node_or_null(WP_MARKET + WP_PINK_TENT) as Node3D
	var white := town.get_node_or_null(WP_MARKET + WP_WHITE_TENT) as Node3D
	if pink != null and white != null and white.is_inside_tree():
		for child: Node in pink.get_children():
			var name_ := str(child.name)
			if child is Node3D and name_.contains("ShopDisplay_") and (name_.contains("televisions") or name_.contains("tv_remote")) and not child.has_meta("overhaul_spot"):
				_wp_stand(child as Node3D, white)
	_wp_vintage(mods)


## The mod builds the stand and the counter only where a ray down at their old spots meets the ground, and the
## ground has collision only near Anon: away from the stream bank where the old market stood, they were never built.
## Two small pads, 2 cm under the ground there, give its rays something to stand on wherever Anon is.
func _wp_pads(town: Node) -> void:
	if town.get_node_or_null("WatchPartyOldMarket") != null or not is_instance_valid(WorldTerrain.instance): return
	var facing := Basis(Vector3.UP, deg_to_rad(WP_OLD_FACING))
	var stand := Vector3(WP_OLD_STAND.x, 0.0, WP_OLD_STAND.y)
	var points: Array[Vector3] = [stand, stand + facing * WP_OLD_REMOTE]
	var body := StaticBody3D.new()
	body.name = "WatchPartyOldMarket"
	for p: Vector3 in points:
		var ground: float = WorldTerrain.instance.height_at(p)
		if not is_finite(ground): body.free(); return   # the heightmap is not loaded yet
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new(); box.size = Vector3(1.2, 0.1, 1.2)
		shape.shape = box
		shape.position = Vector3(p.x, ground - 0.07, p.z)
		body.add_child(shape)
	town.add_child(body)


## The stand (or the remote's counter, which stands beside it) from the old market into the white tent.
func _wp_stand(display: Node3D, white: Node3D) -> void:
	var at := display.global_position
	if Vector2(at.x, at.z).distance_to(WP_OLD_STAND) > 6.0:
		display.set_meta("overhaul_spot", true); return
	var old := Transform3D(Basis(Vector3.UP, deg_to_rad(WP_OLD_FACING)), Vector3(WP_OLD_STAND.x, at.y, WP_OLD_STAND.y))
	var turn := Basis(Vector3.UP, white.global_basis.get_euler().y)
	var stand := Transform3D(turn * Basis(Vector3.UP, deg_to_rad(WP_STAND_FACING)), white.global_position + turn * Vector3(WP_STAND_OFFSET.x, 0.0, WP_STAND_OFFSET.y))
	var target := stand * (old.affine_inverse() * display.global_transform)
	var skip: Array[RID] = []
	for node: Node in display.find_children("*", "CollisionObject3D", true, false): skip.append((node as CollisionObject3D).get_rid())
	var hit := display.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(target.origin + Vector3.UP * 2.0, target.origin + Vector3.DOWN * 4.0, 1, skip))
	# the tent's ground, else (no collision there while Anon is away) the heightmap's
	var ground: float = float(hit.position.y) if not hit.is_empty() else (WorldTerrain.instance.height_at(target.origin) if is_instance_valid(WorldTerrain.instance) else NAN)
	if not is_finite(ground): return
	target.origin.y = ground
	_wp_shift(display, target)
	print("[town] Watch Party's %s stands in the market's white tent at (%.1f, %.1f)" % ["remote counter" if str(display.name).contains("remote") else "television stand", target.origin.x, target.origin.z])


## The vintage set's spot in this world's save (the mod lays it out there), and the set itself if already laid out.
func _wp_vintage(mods: Node) -> void:
	var game: Variant = mods.get("game")
	if not is_instance_valid(game) or not mods.has_method("state"): return
	var data: Variant = mods.call("state", "watch_party")
	if not data is Dictionary or not (data as Dictionary).has("first_day"): return
	if not (data as Dictionary).get("spots") is Dictionary: data["spots"] = {}
	var spots: Dictionary = data.spots
	var row: Variant = spots.get(WP_VINTAGE)
	if row == null or (row is Array and (row as Array).size() >= 3 and Vector2(float(row[0]), float(row[2])).distance_to(WP_OLD_FOREST) < 15.0):
		spots[WP_VINTAGE] = [WP_FOREST[0], WP_FOREST[1], WP_FOREST[2], deg_to_rad(WP_FOREST[3])]
		if mods.has_method("save_changed"): mods.call("save_changed")
		print("[town] Watch Party's vintage set lies at the Everfree's edge behind Fluttershy's cottage")
	var find := (game as Node).get_node_or_null("WatchPartyFind_" + WP_VINTAGE.get_slice(":", 1)) as Node3D
	if find == null or find.has_meta("overhaul_spot"): return
	find.set_meta("overhaul_spot", true)
	if Vector2(find.global_position.x, find.global_position.z).distance_to(WP_OLD_FOREST) >= 15.0: return
	_wp_shift(find, Transform3D(Basis(Vector3.UP, deg_to_rad(WP_FOREST[3])), Vector3(WP_FOREST[0], WP_FOREST[1], WP_FOREST[2])))


## `display` to `target` with all it shows: its goods and cards stand on their own (top_level), so each moves too.
static func _wp_shift(display: Node3D, target: Transform3D) -> void:
	var shift := target * display.global_transform.affine_inverse()
	var loose: Array[Node3D] = []
	for node: Node in display.find_children("*", "Node3D", true, false):
		if (node as Node3D).top_level: loose.append(node as Node3D)
	var moved: Array[Transform3D] = []
	for node: Node3D in loose: moved.append(shift * node.global_transform)
	display.global_transform = target
	display.set_meta("overhaul_spot", true)
	for i in loose.size(): loose[i].global_transform = moved[i]


# ---- Anon's Mailbox ----

func _mailbox(mod: Node) -> void:
	var box: Node3D = mod.get("_root") as Node3D if mod != null else null
	if not is_instance_valid(box) or not box.is_inside_tree():
		_unhide(); return
	if box.has_meta("overhaul_spot"): return
	var home: Node3D = mod.get("_home") as Node3D
	if not is_instance_valid(home) or not home.has_method("outside") or not is_instance_valid(WorldTerrain.instance): return
	var door: Vector3 = home.call("outside")
	var middle: Vector3 = home.call("center") if home.has_method("center") else home.global_position
	var out := Vector3(door.x - middle.x, 0.0, door.z - middle.z)
	if out.length_squared() < 0.01: return
	out = out.normalized()
	_unhide()
	var at := Vector3.INF
	var own := _garden_mailbox(home, door)
	if own.is_finite():
		at = own
		_hide_garden_mailbox(at)
	else:
		# against the front wall, to the door's right: where a ray from the door step back to the middle meets the wall
		var right := out.cross(Vector3.UP).normalized()
		var wall := door
		var hit := box.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(door + Vector3.UP, middle + Vector3.UP, 1))
		if not hit.is_empty(): wall = Vector3(hit.position.x, door.y, hit.position.z)
		at = wall + out * 0.7 + right * 2.2
	var ground: float = WorldTerrain.instance.height_at(at)
	if not is_finite(ground): return
	at.y = ground
	box.global_position = at
	box.set_meta("overhaul_spot", true)
	print("[town] Anon's Mailbox stands at (%.1f, %.1f), %s" % [at.x, at.z, "in place of its house's own mailbox" if own.is_finite() else "beside the front wall"])


## The house's own garden mailbox (the kit's mailbox row of its garden group "house:<plot name>"), else the garden
## mailbox nearest its door within OWN_MAILBOX m; INF when neither.
static func _garden_mailbox(home: Node3D, door: Vector3) -> Vector3:
	KIT_SPOTS._index()
	var names: Array[String] = []
	var up: Node = home
	while up != null:
		if str(up.name).begins_with("plot_"): names.append(str(up.name))
		up = up.get_parent()
	var best := Vector3.INF
	var gap := OWN_MAILBOX
	for id: String in KIT_SPOTS._by_kind.get("mailbox", []):
		var row: Dictionary = KIT_SPOTS._by_id[id]
		var p := Vector3(float(row.x), 0.0, float(row.z))
		var d := Vector2(p.x - door.x, p.z - door.z).length()
		if d > OWN_MAILBOX: continue
		if str(row.get("group", "")).trim_prefix("house:") in names: return p
		if d < gap: gap = d; best = p
	return best


## The garden mailbox's drawn instances at `at` (the kit's MultiMeshes of mailbox.scn's meshes) are set to nothing.
func _hide_garden_mailbox(at: Vector3) -> void:
	var meshes: Array[Mesh] = []
	if ResourceLoader.exists(KIT_MAILBOX_SCENE):
		var scene := (load(KIT_MAILBOX_SCENE) as PackedScene).instantiate()
		for node: Node in scene.find_children("*", "MeshInstance3D", true, false): meshes.append((node as MeshInstance3D).mesh)
		scene.free()
	if meshes.is_empty(): return
	for node: Node in get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null or not mm.mesh in meshes: continue
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			var world := mmi.global_transform * t.origin
			if Vector2(world.x - at.x, world.z - at.z).length() > 0.8: continue
			_hidden.append([mm, i, t])
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), t.origin + Vector3.DOWN * 50.0))


func _unhide() -> void:
	for row: Array in _hidden:
		var mm := row[0] as MultiMesh
		if is_instance_valid(mm) and int(row[1]) < mm.instance_count: mm.set_instance_transform(int(row[1]), row[2])
	_hidden.clear()


func _exit_tree() -> void:
	_unhide()
