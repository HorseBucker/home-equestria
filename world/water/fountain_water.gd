extends Node3D
## Still water in the Town Square fountain (play test 2026-11-16: "Fill the fountain in town square
## with water"). The fountain is baked scenery (fountain_01 in world/props/ponyville/rnl_scenery.scn,
## which a town build regenerates and may move), so this node is made at run time as a child of the
## fountain (world/game_town_adapters.gd attach) and everything here is in the fountain's own space.
##
## - The water: a disc a little below the basin's rim, in the toon water shader the rivers and lakes
##   use, with no flow map (still water, only the slow surface pattern). No collision and not in the
##   `navigation_water` group: the basin is inside the fountain's solid box already, so the walk grid
##   and swimming are unchanged.
## - Seasons: still-water ice (ice_kind 1). The skim and the whole sheet follow season ice x climate
##   at the fountain the way ice_slabs.gd decides it for the lakes, but no walkable slab (nopony can
##   stand in the basin). The material joins WorldWater.water_materials, so rain rings and the ice
##   look's quality setting reach it like every other water.
## - Drinking spots for ponies (world/life/day/actions/drink_at_fountain.gd): drink_spots().
## - The soundscape's fountain sound sits at sound_point() (world/audio/soundscape.gd).

const GROUP := "town_fountains"
const SELF := "res://world/water/fountain_water.gd"
const TOON_WATER := "res://addons/godotshaders/toon_water.gdshader"
const WORLD_WATER := preload("res://world/water/world_water.gd")
## Only the model these numbers were measured on gets water.
const PREFAB := "rnl_ponyville_fountain/prefab.scn"
## The basin, in the fountain's own space (measured 2026-11-16 with tools/town_planner/build/qc/
## lab_agent_b_probe.gd, rings of the mesh's vertices around its axis): floor y 0.48-0.51 out to
## r 2.5, the inner wall rising to the flat rim top (y 0.97, r 2.6-3.0), the outer wall down to the
## plinth at r 3.1-3.19; the statue column stands inside r 1.4. The disc's edge tucks into the inner
## wall (it leans out from r 2.5 at the floor to 2.6 at the rim), so no gap shows at the stone.
## Nearly brim-full (3 cm under the rim top): a pony is small beside this basin (the rim is at her
## chin), and her muzzle only reaches the water just inside the lip.
const WATER_Y := 0.94
const WATER_R := 2.63
const OUTER_R := 3.19
const SEGMENTS := 64
## Ponies drink standing at STAND_R, OUTER_R + the walk grid's pony radius (0.45 m) + a little, so
## the grid keeps them clear of the basin wall. The model's own collision is one 5.43 m box (half 2.71)
## whose corners stood out past the round rim (2026-11-18 play test: "4 random small invisible walls
## around the fountain"); attach() puts a round one the rim's size in its place, so the spots go all
## the way round (SPOTS of them).
const STAND_R := 3.68
const SPOTS := 10
## Where the muzzle is asked to go: just inside the lip, at the surface. NOTE (2026-11-16): a standing
## pony cannot get there. The rim top is 0.97 m above her feet, her mouth reaches at most ~0.89 m up
## and ~0.44 m ahead of her centre (lab_agent_b_reach.gd); she stretches toward it and stops short.
const SIP_R := 2.55
## Ice like ice_slabs.gd: frozen above FREEZE_AT, open again below THAW_BELOW.
const FREEZE_AT := 0.6
const THAW_BELOW := 0.5
const TICK := 2.0

var material: ShaderMaterial
var surface: MeshInstance3D
## Season ice x climate here (0 open .. 1), and whether the sheet is whole.
var ice := 0.0
var frozen := false
var _timer := 0.0
var _taken: Dictionary = {}     # spot index -> [pony id, WeakRef to the holder]


## Water in the town's fountain(s); null when the town has none of the measured model. Idempotent.
static func attach(town: Node) -> Node3D:
	var scenery: Node = town.get_node_or_null("RNLScenery") if town != null else null
	if scenery == null: return null
	var fountain := scenery.find_child("fountain_01", true, false) as Node3D
	if fountain == null or not fountain.scene_file_path.ends_with(PREFAB): return null
	var existing := fountain.get_node_or_null("FountainWater") as Node3D
	if existing != null: return existing
	_round_collision(fountain)
	var water: Node3D = (load(SELF) as GDScript).new()
	water.name = "FountainWater"
	fountain.add_child(water)
	return water


## The model's square box collision becomes a round one, OUTER_R wide, as tall as the box: nothing
## invisible stands out past the basin's stone.
static func _round_collision(fountain: Node3D) -> void:
	for holder: Node in fountain.find_children("*", "CollisionShape3D", true, false):
		var shape := (holder as CollisionShape3D).shape as BoxShape3D
		if shape == null: continue
		var round := CylinderShape3D.new()
		round.radius = OUTER_R
		round.height = shape.size.y
		(holder as CollisionShape3D).shape = round


func _ready() -> void:
	add_to_group(GROUP)
	material = ShaderMaterial.new()
	material.shader = load(TOON_WATER)
	# The fountain never freezes (play test 2026-11-16: "The water in the fountain should not be frozen in
	# Winter"): ice_kind 0 is the shader's "no ice here", whatever the season says.
	material.set_shader_parameter("ice_kind", 0)
	# Still: no vertex swell, a slow pattern a few metres across (the lakes' 18 tiles span hundreds
	# of metres; over a 5 m basin that would be one flat colour). The basin is only 0.4 m deep, so the
	# depth factor is higher than the rivers' or the stone floor shows through as if dry.
	material.set_shader_parameter("wave_amplitude", 0.0)
	material.set_shader_parameter("tile", Vector2(5.0, 5.0))
	material.set_shader_parameter("distortion_speed", 0.45)
	material.set_shader_parameter("water_transparency", 0.8)
	material.set_shader_parameter("water_depth_factor", 2.2)
	material.set_shader_parameter("foam_width", 0.12)
	surface = MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = _disc(WATER_R)
	surface.position = Vector3(0.0, WATER_Y, 0.0)
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	_tick()


## A flat disc facing up, UV 0..1 across it.
static func _disc(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i: int in SEGMENTS:
		# Centre, then two rim points with the angle growing: clockwise seen from above (+x right,
		# +z down the screen), Godot's front face.
		var a := TAU * float(i) / SEGMENTS
		var b := TAU * float(i + 1) / SEGMENTS
		for at: Vector3 in [Vector3.ZERO, Vector3(cos(a), 0.0, sin(a)) * radius, Vector3(cos(b), 0.0, sin(b)) * radius]:
			st.set_uv(Vector2(at.x, at.z) / (2.0 * radius) + Vector2(0.5, 0.5))
			st.add_vertex(at)
	return st.commit()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = TICK
		_tick()


func _tick() -> void:
	# Rain rings and the ice look's quality come through WorldWater's material list (ice_slabs.gd).
	var water: Node = WORLD_WATER.instance
	if is_instance_valid(water) and not water.water_materials.has(material): water.water_materials.append(material)


## Iced over enough that nopony drinks here (the skim reaches well in before the sheet closes).
func iced() -> bool:
	return false      # it never freezes (see _ready); kept for the drink step, which asks


## The water's centre, a little above it (the soundscape's fountain sound).
func sound_point() -> Vector3:
	return to_global(Vector3(0.0, WATER_Y + 0.5, 0.0))


## Where ponies drink: [{"approach", "sip", "centre"}] in world space, SPOTS round the basin.
## `approach` is the standing point at ground height as the fountain sees it (the navigator snaps it
## to the walk grid), `sip` the point on the surface her muzzle is asked to go to.
func drink_spots() -> Array:
	var spots: Array = []
	var centre := to_global(Vector3(0.0, WATER_Y, 0.0))
	for i: int in SPOTS:
		var angle := TAU * float(i) / SPOTS
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var stand := to_global(out * STAND_R)
		if is_instance_valid(WorldTerrain.instance):
			var h: float = WorldTerrain.instance.height_at(stand)
			if is_finite(h): stand.y = h
		spots.append({"approach": stand, "sip": to_global(out * SIP_R + Vector3(0.0, WATER_Y, 0.0)), "centre": centre})
	return spots


## One pony per spot. A holder that is gone (its step ended without a release) frees the spot.
func spot_free(index: int) -> bool:
	if not _taken.has(index): return true
	var row: Array = _taken[index]
	if (row[1] as WeakRef).get_ref() == null:
		_taken.erase(index)
		return true
	return false


func take_spot(index: int, id: String, holder: Object) -> bool:
	if not spot_free(index): return false
	_taken[index] = [id, weakref(holder)]
	return true


func release_spot(index: int, holder: Object) -> void:
	if _taken.has(index) and (_taken[index] as Array)[1].get_ref() == holder: _taken.erase(index)
