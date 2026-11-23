extends Node3D
## The storage chest in the Town Hall (2026-11-18): a place to keep what the briefcase need not carry, and where a
## world from before the overhaul finds the belongings of the home it left (overhaul_migration.gd). Look at it and
## press E, or touch it and pull the VR trigger: its lid swings open and the chest's page shows what it holds
## (chest_menu.gd); leaving the page shuts the lid. What it holds: chest_store.gd.
##
## The look follows the show's chest (HorseBucker's reference, 2026-11-18): a golden box with darker sides and a zigzag
## along its foot, a grey iron band with rivets round its top, a round grey lock plate with a keyhole hanging from
## the band, and a tall rounded lid hinged at the back. Built here from simple shapes; no model file.

const SFX := preload("res://world/audio/interaction_sounds.gd")
const MENU := preload("res://world/props/town_chest/chest_menu.gd")
const STORE := preload("res://world/props/town_chest/chest_store.gd")
const DESK_REACH := 2.4
const TOUCH_REACH := 0.06
const WIDTH := 1.0
const DEPTH := 0.62
const HEIGHT := 0.5
const OPEN_ANGLE := deg_to_rad(-108.0)
## Where it stands in the hall, in the hall's own metres (hall_interior.gd: to_local(at) * 26), against the west
## wall, just in front of the raised ledge that runs round it (the ledge has no collision in places, so the ray map
## lab_hall.gd showed floor under it), out of the way of both doors, its front to the room.
const HALL_SPOT := Vector3(-4.65, 0.805, -0.6)


const GOLD := Color("d6860a")
const GOLD_DARK := Color("9e540c")
const GOLD_ZIG := Color("ad6606")
const GOLD_RIM := Color("e6a52a")
const INSIDE := Color("4a2a10")
const IRON := Color("6f8b74")
const IRON_DARK := Color("3f4a45")

var game: Node
var lid: Node3D
var body: StaticBody3D
var menu: Node3D
var _open := false
var _tween: Tween
var _trigger := {"left": true, "right": true}
var _touch := SphereShape3D.new()


## Puts the chest in the Town Hall of `town` (town_density.gd fill, once the town is in the tree).
static func attach(town: Node3D) -> Node3D:
	var hall := town.get_node_or_null("town_hall/HouseInterior") as Node3D
	if hall == null:
		for node: Node in town.find_children("HouseInterior", "", true, false):
			if str(node.get("home_kind")) == "town_hall": hall = node as Node3D; break
	if hall == null or town.get_node_or_null("TownHallChest") != null: return null
	var chest: Node3D = (load("res://world/props/town_chest/town_chest.gd") as GDScript).new()
	chest.name = "TownHallChest"
	town.add_child(chest)
	# its front (+Z) to the middle of the room, whatever the hall's own turn and scale
	var at := hall.to_global(HALL_SPOT / 26.0)
	var middle := hall.to_global(Vector3(0.0, HALL_SPOT.y, -0.5) / 26.0)
	var yaw := atan2(middle.x - at.x, middle.z - at.z)
	chest.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	print("[chest] in the Town Hall at %s, facing %s" % [at, middle])
	return chest


func _ready() -> void:
	add_to_group("interaction_hint_sources")
	add_to_group("town_chests")   # (chest_store.gd: where a mod item kept in it is set out)
	_touch.radius = TOUCH_REACH
	_build()
	_rescue_later()


## Once the world is up and the briefcase can be written, things set out in houses this density does not have go
## into the chest (chest_store.gd rescue_homeless).
func _rescue_later() -> void:
	for i in 180:
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree(): return
		var ui := _ui()
		var store: Variant = ui.get("inventory") if ui != null else null
		if store is Object and bool((store as Object).get("writable")) and game.get("title_active") != true:
			await get_tree().create_timer(3.0).timeout
			STORE.rescue_homeless(game)
			return


# ---- the model ----

## Flat, show-like paint that reads in a dim room (the Town Hall has no lamps): lit as usual, and a share of its own
## colour on top, so it never goes black.
const GLOW := 0.12
static var _shader: Shader

func _material(vertex_colors: bool, colour := Color.WHITE) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool use_vertex = false;
uniform float glow = 0.4;
void fragment() {
	vec3 c = use_vertex ? COLOR.rgb : tint.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.85;
	EMISSION = c * glow;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("tint", colour)
	m.set_shader_parameter("use_vertex", vertex_colors)
	m.set_shader_parameter("glow", GLOW)
	return m


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_color(colour)
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_normal(n); st.add_vertex(v)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_color(colour)
	for v: Vector3 in [a, b, c]:
		st.set_normal(n); st.add_vertex(v)


func _build() -> void:
	var w := WIDTH * 0.5; var d := DEPTH * 0.5; var h := HEIGHT
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the box: golden front and back, darker sides, its floor and walls brown inside
	_quad(st, Vector3(-w, 0, d), Vector3(w, 0, d), Vector3(w, h, d), Vector3(-w, h, d), GOLD)
	_quad(st, Vector3(w, 0, -d), Vector3(-w, 0, -d), Vector3(-w, h, -d), Vector3(w, h, -d), GOLD)
	_quad(st, Vector3(w, 0, d), Vector3(w, 0, -d), Vector3(w, h, -d), Vector3(w, h, d), GOLD_DARK)
	_quad(st, Vector3(-w, 0, -d), Vector3(-w, 0, d), Vector3(-w, h, d), Vector3(-w, h, -d), GOLD_DARK)
	_quad(st, Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(w, 0, d), Vector3(-w, 0, d), GOLD_DARK)
	var t := 0.035      # the walls' thickness, seen from above when open
	_quad(st, Vector3(-w + t, 0.04, d - t), Vector3(w - t, 0.04, d - t), Vector3(w - t, 0.04, -d + t), Vector3(-w + t, 0.04, -d + t), INSIDE)
	_quad(st, Vector3(-w + t, 0.04, d - t), Vector3(-w + t, h, d - t), Vector3(w - t, h, d - t), Vector3(w - t, 0.04, d - t), INSIDE)
	_quad(st, Vector3(w - t, 0.04, -d + t), Vector3(w - t, h, -d + t), Vector3(-w + t, h, -d + t), Vector3(-w + t, 0.04, -d + t), INSIDE)
	_quad(st, Vector3(w - t, 0.04, d - t), Vector3(w - t, h, d - t), Vector3(w - t, h, -d + t), Vector3(w - t, 0.04, -d + t), INSIDE)
	_quad(st, Vector3(-w + t, 0.04, -d + t), Vector3(-w + t, h, -d + t), Vector3(-w + t, h, d - t), Vector3(-w + t, 0.04, d - t), INSIDE)
	# the zigzag along the foot, front and sides
	var teeth := 6; var tall := 0.13; var lift := 0.003
	for i in teeth:
		var x0 := -w + WIDTH * i / teeth; var x1 := -w + WIDTH * (i + 1) / teeth
		_tri(st, Vector3(x0, 0.0, d + lift), Vector3(x1, 0.0, d + lift), Vector3((x0 + x1) * 0.5, tall, d + lift), GOLD_ZIG)
	for side: float in [-1.0, 1.0]:
		for i in 4:
			var z0 := -d + DEPTH * i / 4.0; var z1 := -d + DEPTH * (i + 1) / 4.0
			var x := side * (w + lift)
			_tri(st, Vector3(x, 0.0, z0), Vector3(x, 0.0, z1), Vector3(x, tall, (z0 + z1) * 0.5), GOLD_DARK.darkened(0.12))
	var box := MeshInstance3D.new(); box.name = "Box"; box.mesh = st.commit(); box.material_override = _material(true)
	add_child(box)
	# the iron band round the top of the box, its rivets and the lock
	# (a ring of four strips, so the box stays open inside)
	var iron := _material(false, IRON)
	for strip: Array in [[Vector3(WIDTH + 0.03, 0.085, 0.03), Vector3(0, 0, d)], [Vector3(WIDTH + 0.03, 0.085, 0.03), Vector3(0, 0, -d)],
			[Vector3(0.03, 0.085, DEPTH + 0.03), Vector3(w, 0, 0)], [Vector3(0.03, 0.085, DEPTH + 0.03), Vector3(-w, 0, 0)]]:
		var band := MeshInstance3D.new(); band.name = "Band"
		var band_mesh := BoxMesh.new(); band_mesh.size = strip[0]
		band.mesh = band_mesh; band.position = Vector3(0, h - 0.045, 0) + Vector3(strip[1]); band.material_override = iron
		add_child(band)
	var rivet_mesh := CylinderMesh.new(); rivet_mesh.top_radius = 0.016; rivet_mesh.bottom_radius = 0.016; rivet_mesh.height = 0.012
	var dark := _material(false, IRON_DARK)
	for i in 7:
		if i == 3: continue
		var rivet := MeshInstance3D.new(); rivet.mesh = rivet_mesh; rivet.material_override = dark
		rivet.rotation.x = PI * 0.5; rivet.position = Vector3(-w + 0.07 + (WIDTH - 0.14) * i / 6.0, h - 0.045, d + 0.018)
		add_child(rivet)
	for side: float in [-1.0, 1.0]:
		for i in 3:
			var rivet := MeshInstance3D.new(); rivet.mesh = rivet_mesh; rivet.material_override = dark
			rivet.rotation.z = PI * 0.5; rivet.position = Vector3(side * (w + 0.018), h - 0.045, -d + 0.12 + (DEPTH - 0.24) * i / 2.0)
			add_child(rivet)
	var hasp := MeshInstance3D.new(); var hasp_mesh := BoxMesh.new(); hasp_mesh.size = Vector3(0.05, 0.11, 0.014)
	hasp.mesh = hasp_mesh; hasp.position = Vector3(0, h - 0.13, d + 0.012); hasp.material_override = _material(false, IRON)
	add_child(hasp)
	var plate := MeshInstance3D.new(); var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = 0.075; plate_mesh.bottom_radius = 0.075; plate_mesh.height = 0.016
	plate.mesh = plate_mesh; plate.rotation.x = PI * 0.5; plate.position = Vector3(0, h - 0.24, d + 0.014)
	plate.material_override = _material(false, IRON)
	add_child(plate)
	var hole := MeshInstance3D.new(); var hole_mesh := CylinderMesh.new()
	hole_mesh.top_radius = 0.018; hole_mesh.bottom_radius = 0.018; hole_mesh.height = 0.006
	hole.mesh = hole_mesh; hole.rotation.x = PI * 0.5; hole.position = Vector3(0, h - 0.225, d + 0.024); hole.material_override = dark
	add_child(hole)
	var slot := MeshInstance3D.new(); var slot_mesh := BoxMesh.new(); slot_mesh.size = Vector3(0.018, 0.05, 0.006)
	slot.mesh = slot_mesh; slot.position = Vector3(0, h - 0.255, d + 0.024); slot.material_override = dark
	add_child(slot)
	# the lid: hinged at the back of the top, a tall rounded profile run across the chest's width
	lid = Node3D.new(); lid.name = "Lid"; lid.position = Vector3(0, h, -d)
	add_child(lid)
	var profile := [Vector2(0.0, 0.0), Vector2(DEPTH, 0.0), Vector2(DEPTH, 0.07), Vector2(DEPTH - 0.06, 0.15), Vector2(DEPTH - 0.19, 0.215),
		Vector2(DEPTH - 0.34, 0.235), Vector2(0.11, 0.205), Vector2(0.0, 0.14)]
	var ls := SurfaceTool.new(); ls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lw := w + 0.012
	for i in profile.size():
		var a: Vector2 = profile[i]; var b: Vector2 = profile[(i + 1) % profile.size()]
		var colour := INSIDE if i == 0 else (GOLD if b.y > 0.02 or a.y > 0.02 else GOLD_RIM)
		_quad(ls, Vector3(-lw, b.y, b.x), Vector3(lw, b.y, b.x), Vector3(lw, a.y, a.x), Vector3(-lw, a.y, a.x), colour)
	for side: float in [-1.0, 1.0]:
		for i in range(1, profile.size() - 1):
			var p0: Vector2 = profile[0]; var p1: Vector2 = profile[i]; var p2: Vector2 = profile[i + 1]
			_tri(ls, Vector3(side * lw, p0.y, p0.x), Vector3(side * lw, p1.y, p1.x), Vector3(side * lw, p2.y, p2.x), GOLD_DARK)
		# the lid's own zigzag along its lower edge, like the box's
		for i in 3:
			var z0 := DEPTH * i / 3.0; var z1 := DEPTH * (i + 1) / 3.0
			_tri(ls, Vector3(side * (lw + 0.003), 0.0, z0), Vector3(side * (lw + 0.003), 0.0, z1), Vector3(side * (lw + 0.003), 0.08, (z0 + z1) * 0.5), GOLD_DARK.darkened(0.12))
	var lid_mesh := MeshInstance3D.new(); lid_mesh.name = "LidMesh"; lid_mesh.mesh = ls.commit(); lid_mesh.material_override = _material(true)
	lid.add_child(lid_mesh)
	# collision: the box and the lid shut, on the world layer (the aim ray and walls); the chest marked for the ray
	body = StaticBody3D.new(); body.name = "Body"; body.collision_layer = 1; body.collision_mask = 0
	body.set_meta("town_chest", self)
	var shape := CollisionShape3D.new(); var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(WIDTH + 0.04, h + 0.24, DEPTH + 0.04)
	shape.shape = box_shape; shape.position = Vector3(0, (h + 0.24) * 0.5, 0)
	body.add_child(shape); add_child(body)


# ---- opening and shutting ----

func set_open(on: bool) -> void:
	if on == _open: return
	_open = on
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_BACK if on else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT if on else Tween.EASE_IN)
	_tween.tween_property(lid, "rotation:x", OPEN_ANGLE if on else 0.0, 0.5 if on else 0.35)
	SFX.play_at(self, "prop_furniture" if on else "prop_place")


func is_open() -> bool:
	return _open


func _ui() -> Node:
	if not is_instance_valid(game):
		var scene := get_tree().current_scene if is_inside_tree() else null
		game = scene if scene != null and "player" in scene else null
	var ui: Variant = game.get("inventory") if is_instance_valid(game) else null
	return ui as Node if ui is Node and is_instance_valid(ui) else null


func access() -> void:
	var ui := _ui()
	if ui == null: return
	if not is_instance_valid(menu):
		menu = MENU.new(); menu.name = "ChestMenu"
		game.add_child(menu)
		menu.setup(game, ui, self)
	if menu.opened: return
	if menu.open(): set_open(true)


func _unhandled_input(event: InputEvent) -> void:
	var ui := _ui()
	if ui == null or not ui._desktop: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if not _aimed(ui).is_empty():
			get_viewport().set_input_as_handled()
			access()


func _physics_process(_delta: float) -> void:
	var ui := _ui()
	if ui == null: return
	if ui._desktop: return
	if is_instance_valid(menu) and menu.opened: return
	for side: String in ["left", "right"]:
		var sample: Dictionary = ui.hand_sample(side)
		var pulled: bool = bool(sample.get("active", false)) and float(sample.get("trigger", 0.0)) > (0.45 if _trigger[side] else 0.75)
		if pulled and not _trigger[side] and not _hand_target(ui, side, sample).is_empty():
			ui._haptic(side); access()
		_trigger[side] = pulled


func _aimed(ui: Node) -> Dictionary:
	var camera: Camera3D = ui.camera
	if not is_instance_valid(camera): return {}
	var from := camera.global_position
	if from.distance_to(global_position) > DESK_REACH + 1.5: return {}
	var skip: Array[RID] = []
	if ui.player_body is CollisionObject3D: skip.append((ui.player_body as CollisionObject3D).get_rid())
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * DESK_REACH, 1 | (1 << 17), skip))
	if hit.is_empty() or hit.collider != body: return {}
	return {"target": self, "collider": body, "point": hit.position}


func _hand_target(ui: Node, side: String, sample: Dictionary) -> Dictionary:
	if not bool(sample.get("active", false)): return {}
	var hand: Node = ui.hands.get(side)
	if is_instance_valid(hand) and (hand.get_meta("inventory_busy", false) or hand.get("held_object") != null): return {}
	if is_instance_valid(ui.held.get(side)): return {}
	var tip: Vector3 = sample.get("tip", Vector3.INF)
	if not tip.is_finite() or tip.distance_to(global_position) > 1.6: return {}
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = _touch; query.transform.origin = tip; query.collision_mask = 1
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 8):
		if hit.collider == body: return {"target": self, "collider": body, "point": tip}
	return {}


func interaction_hint() -> Dictionary:
	var ui := _ui()
	if ui == null or (is_instance_valid(menu) and menu.opened): return {}
	var target: Dictionary = {}
	var control := "[E] "
	if ui._desktop:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return {}
		target = _aimed(ui)
	else:
		control = "Trigger · "
		for side: String in ["right", "left"]:
			var sample: Dictionary = ui.hand_sample(side)
			target = _hand_target(ui, side, sample)
			if not target.is_empty(): break
	if target.is_empty(): return {}
	target.text = control + "Open the chest"
	return target
