extends Node
## A television blowing up (dev 2026-11-06): Trixie's spell went wrong (magic_quest.gd), and when
## the set is switched on it goes off with a flash, a fireball, a cloud of smoke, bits of it flying
## and a bang. The set is gone (finds.gd destroyed; another is for sale at the market from the next
## 06:00 restock, finds.gd tidy_lost). It leaves a scorch mark on the ground that stays a day and fades over the next
## (kept in the world save: finds.gd state scorches). Anon close by is knocked down as if bucked
## (his body's receive_buck, desktop and VR alike); ponies close by are thrown back and land on
## their hooves (the game's own hop, world/characters/locomotion/pony_throw.gd), and every pony
## near enough remembers it (finds.gd witness). Also the thin smoke a doomed set gives off (wisp).
## Effects are the Trixie show's (world/events/trixie_show/show_fx.gd); the bang is made here.

const FINDS := preload("res://mods/watch_party/finds.gd")
const FX := "res://world/events/trixie_show/show_fx.gd"
const THROW := "res://world/characters/locomotion/pony_throw.gd"
## Anon or a pony this close (metres, flat) is thrown; the push weakens with distance.
const REACH := 6.5
const ANON_PUSH := Vector2(10.0, 4.0)
const ANON_LIFT := 3.5
## Ponies this close saw it (and remember it).
const SEEN_REACH := 15.0
## Hops back this far at most (nearest first), the arc clear of everything.
const HOPS := [3.2, 2.2, 1.4]
const DEBRIS := 12
const DEBRIS_SECONDS := 7.0
## The scorch mark: this wide, full for SCORCH_FULL hours of game time, gone by SCORCH_GONE.
const SCORCH_SIZE := 2.8
const SCORCH_FULL := 24.0
const SCORCH_GONE := 48.0
const SCORCH_CHECK := 5.0
const BOOM_RATE := 22050

var hub: Node
## The marks in the world now: [{node, made}].
var _marks: Array = []
var _check := 0.0
## Seconds before the marks are laid out after a world opens (the ground loads first).
var _lay_in := -1.0
static var _boom: AudioStreamWAV
static var _scorch_texture: ImageTexture

func world(_game: Node) -> void:
	for mark: Dictionary in _marks:
		if is_instance_valid(mark.node): (mark.node as Node).queue_free()
	_marks = []
	_lay_in = 4.0

func _exit_tree() -> void:
	for mark: Dictionary in _marks:
		if is_instance_valid(mark.node): (mark.node as Node).queue_free()

func _process(delta: float) -> void:
	if _lay_in > 0.0:
		_lay_in -= delta
		if _lay_in <= 0.0: _lay_out()
		return
	_check -= delta
	if _check > 0.0: return
	_check = SCORCH_CHECK
	_fade()

# --- smoke -------------------------------------------------------------------------------------

## A thin dark curl of smoke at `at` (a doomed set's back, tv_set.gd smoke).
static func wisp(parent: Node, at: Vector3) -> void:
	var fx: Script = load(FX)
	if fx != null and is_instance_valid(parent) and parent.is_inside_tree(): fx.call("puff", parent, at, Color(0.24, 0.23, 0.22), 0.3)

# --- the blast ---------------------------------------------------------------------------------

## Blows up `tv` (a tv_set.gd node), woken by `by`'s spell. Returns {anon: thrown, ponies: [ids
## thrown], seen: [ids who saw it]}.
func blast(tv: Node3D, by: String) -> Dictionary:
	var out := {"anon": false, "ponies": [], "seen": []}
	if not is_instance_valid(tv): return out
	var id := str(tv.call("item_id"))
	var spec: Variant = tv.get("spec")
	var centre: Vector2 = (spec as Dictionary).get("centre", Vector2(0, 0.5)) if spec is Dictionary else Vector2(0, 0.5)
	var at := tv.to_global(Vector3(centre.x, centre.y, 0.0))
	var body: Variant = tv.get("body")
	var game: Node = Mods.game
	var parent: Node = game if is_instance_valid(game) else get_tree().root
	_effects(parent, at, str((spec as Dictionary).get("kind", "crt")) if spec is Dictionary else "crt")
	_scorch_at(at, body as CollisionObject3D if body is CollisionObject3D else null)
	_remove(body as Node3D if body is Node3D else null)
	FINDS.mark_destroyed(id)
	out.anon = _throw_anon(at)
	var director := get_tree().get_first_node_in_group("conversation_director")
	var characters: Variant = director.get("characters") if director != null else null
	if characters is Dictionary:
		for pony: Variant in (characters as Dictionary).keys():
			var node: Variant = (characters as Dictionary)[pony].get("node")
			if not is_instance_valid(node) or not node is Node3D or not (node as Node3D).is_inside_tree(): continue
			var distance := _flat((node as Node3D).global_position, at)
			if distance > SEEN_REACH: continue
			if not bool((node as Node).get("sleeping")):
				FINDS.witness(str(pony), id, by, true)
				(out.seen as Array).append(str(pony))
			if distance < REACH and _throw_pony(node as Node3D, at, distance): (out.ponies as Array).append(str(pony))
	print("[watch_party] the %s blew up (Anon %s, ponies thrown: %s)" % [FINDS.kind_name(id), "thrown" if out.anon else "clear", ", ".join(PackedStringArray(out.ponies))])
	return out

func _effects(parent: Node, at: Vector3, kind: String) -> void:
	var fx: Script = load(FX)
	if fx != null:
		fx.call("_burst", parent, at, Color(1.0, 0.55, 0.15))
		fx.call("sparks", parent, at, 0.45, Color(1.0, 0.72, 0.3))
		fx.call("puff", parent, at, Color(0.16, 0.15, 0.14), 2.6)
		get_tree().create_timer(0.25).timeout.connect(func() -> void:
			if is_instance_valid(parent): fx.call("puff", parent, at + Vector3.UP * 0.8, Color(0.32, 0.31, 0.3), 3.4))
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.35)
	flash.omni_range = 16.0
	flash.light_energy = 0.0
	flash.shadow_enabled = false
	parent.add_child(flash)
	flash.global_position = at + Vector3.UP * 0.3
	var glow := flash.create_tween()
	glow.tween_property(flash, "light_energy", 10.0, 0.04)
	glow.tween_property(flash, "light_energy", 0.0, 0.9)
	glow.tween_callback(flash.queue_free)
	_debris(parent, at, kind)
	_bang(parent, at)

## Bits of the set flying out (wood and glass for the old set, black glass for a flatscreen).
func _debris(parent: Node, at: Vector3, kind: String) -> void:
	var colours: Array = [Color("4a2f1c"), Color("6b4a2e"), Color("2b2b2e"), Color("8f9aa3")] if kind == "crt" else [Color("101114"), Color("1d1f24"), Color("3a3d44")]
	for i in DEBRIS:
		var piece := RigidBody3D.new()
		piece.collision_layer = 0
		piece.collision_mask = 1
		piece.mass = 0.3
		var size := Vector3(randf_range(0.05, 0.18), randf_range(0.02, 0.06), randf_range(0.05, 0.16))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new(); box.size = size
		shape.shape = box
		piece.add_child(shape)
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new(); cube.size = size
		var material := StandardMaterial3D.new(); material.albedo_color = colours[i % colours.size()]
		cube.material = material
		mesh.mesh = cube
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.add_child(mesh)
		parent.add_child(piece)
		piece.global_position = at + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.3), randf_range(-0.2, 0.2))
		var out := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1)).normalized()
		piece.linear_velocity = out * randf_range(4.0, 9.0)
		piece.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		get_tree().create_timer(DEBRIS_SECONDS + randf()).timeout.connect(func() -> void: if is_instance_valid(piece): piece.queue_free())

## The bang: a short roar of noise over a low thump, made once.
func _bang(parent: Node, at: Vector3) -> void:
	if _boom == null: _boom = _make_boom()
	var player := AudioStreamPlayer3D.new()
	player.stream = _boom
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	player.unit_size = 14.0
	player.max_distance = 160.0
	player.volume_db = 4.0
	parent.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()

static func _make_boom() -> AudioStreamWAV:
	var seconds := 2.2
	var count := int(BOOM_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var low := 0.0
	var lower := 0.0
	for i in count:
		var t := float(i) / BOOM_RATE
		var attack := clampf(t / 0.006, 0.0, 1.0)
		low = low * 0.82 + randf_range(-1.0, 1.0) * 0.18
		lower = lower * 0.97 + low * 0.03
		var crack := randf_range(-1.0, 1.0) * exp(-t * 28.0) * 0.55
		var roar := low * exp(-t * 2.6) * 1.8 + lower * exp(-t * 1.2) * 5.0
		var thump := sin(TAU * (55.0 - 25.0 * t) * t) * exp(-t * 5.0) * 0.9
		var sample := clampf((crack + roar + thump) * attack, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = BOOM_RATE
	stream.stereo = false
	stream.data = data
	return stream

## The set's body and its briefcase loan are gone (as food that was eaten: inventory_store.gd consume).
func _remove(body: Node3D) -> void:
	if not is_instance_valid(body): return
	var token := str(body.get_meta("token", ""))
	var inventory: Node = Mods.game.get("inventory") as Node if is_instance_valid(Mods.game) else null
	if inventory != null and not token.is_empty():
		var store: Variant = inventory.get("inventory")
		if store is Object and (store as Object).has_method("consume"): (store as Object).call("consume", token)
		var loose: Variant = inventory.get("loose")
		if loose is Dictionary: (loose as Dictionary).erase(token)
	body.queue_free()

# --- who is thrown -----------------------------------------------------------------------------

## Anon close by is knocked down, away from the blast (the buck's knockdown, player/*.gd).
func _throw_anon(at: Vector3) -> bool:
	var inventory: Node = Mods.game.get("inventory") as Node if is_instance_valid(Mods.game) else null
	var body: Variant = inventory.get("player_body") if inventory != null else null
	if not is_instance_valid(body) or not (body as Node).has_method("receive_buck"): return false
	var where := (body as Node3D).global_position
	var distance := _flat(where, at)
	if distance > REACH: return false
	var away := Vector3(where.x - at.x, 0.0, where.z - at.z)
	away = away.normalized() if away.length() > 0.05 else -(body as Node3D).global_basis.z
	var push := lerpf(ANON_PUSH.x, ANON_PUSH.y, distance / REACH)
	(body as Node).call("receive_buck", away * push + Vector3.UP * ANON_LIFT)
	return true

## A pony close by hops back away from it and lands on her hooves (the game's own recovery hop).
func _throw_pony(pony: Node3D, from: Vector3, distance: float) -> bool:
	if bool(pony.get("sleeping")) or not "thrown" in pony: return false
	if pony.has_method("is_held") and bool(pony.call("is_held")): return false
	var thrown: Variant = pony.get("thrown")
	if thrown == null:
		var script: Script = load(THROW)
		if script == null: return false
		thrown = script.new()
		(thrown as Object).call("bind", pony)
		pony.set("thrown", thrown)
	if bool((thrown as Object).call("active")): return false
	var away := Vector3(pony.global_position.x - from.x, 0.0, pony.global_position.z - from.z)
	away = away.normalized() if away.length() > 0.05 else -pony.global_basis.z
	var nav: Node = pony.get_node_or_null("Navigator")
	var strength := clampf(1.15 - distance / REACH, 0.45, 1.0)
	for reach: float in HOPS:
		var spot := pony.global_position + away * reach * strength
		if nav != null and nav.has_method("command_support"):
			var ground: Vector3 = nav.call("command_support", spot)
			if ground.is_finite(): spot = ground
		if bool((thrown as Object).call("hop", spot)): return true
	return false

# --- scorch marks ------------------------------------------------------------------------------

func _scorch_at(at: Vector3, skip: CollisionObject3D) -> void:
	var space: World3D = get_viewport().find_world_3d() if get_viewport() != null else null
	if space == null: return
	var exclude: Array[RID] = []
	if is_instance_valid(skip): exclude.append(skip.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * 4.0, 1, exclude)
	var hit := space.direct_space_state.intersect_ray(ray)
	if hit.is_empty(): return
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var made := _hours()
	var data := FINDS.state()
	if not data.get("scorches") is Array: data.scorches = []
	(data.scorches as Array).append([point.x, point.y, point.z, normal.x, normal.y, normal.z, made, randf() * TAU])
	FINDS.changed()
	_mark(point, normal, made, float((data.scorches as Array).back()[7]))

## Game time in hours since the clock's day 0 (-1 with no clock).
static func _hours() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var clock: Node = tree.root.get_node_or_null("TimeOfDay") if tree != null else null
	if clock == null: return -1.0
	return float(clock.day) * 24.0 + float(clock.hours)

func _lay_out() -> void:
	var rows: Variant = FINDS.state().get("scorches", [])
	if not rows is Array: return
	for row: Variant in rows:
		if row is Array and (row as Array).size() >= 8:
			var r: Array = row
			_mark(Vector3(r[0], r[1], r[2]), Vector3(r[3], r[4], r[5]), float(r[6]), float(r[7]))
	_fade()

func _mark(point: Vector3, normal: Vector3, made: float, turn: float) -> void:
	if not is_instance_valid(Mods.game): return
	if _scorch_texture == null: _scorch_texture = _make_scorch()
	var mesh := MeshInstance3D.new()
	mesh.name = "WatchPartyScorch"
	var plane := PlaneMesh.new()
	plane.size = Vector2(SCORCH_SIZE, SCORCH_SIZE)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _scorch_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material = material
	mesh.mesh = plane
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Mods.game.add_child(mesh)
	var up := normal.normalized() if normal.length() > 0.1 else Vector3.UP
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up)).rotated(up, turn)
	mesh.global_transform = Transform3D(basis, point + up * 0.012)
	_marks.append({"node": mesh, "made": made, "material": material})

## Marks fade over their second day and are gone after it (and from the save).
func _fade() -> void:
	var now := _hours()
	if now < 0.0: return
	var kept: Array = []
	for mark: Dictionary in _marks:
		var age := now - float(mark.made)
		if age >= SCORCH_GONE or age < -1.0:
			if is_instance_valid(mark.node): (mark.node as Node).queue_free()
			continue
		var alpha := 1.0 - clampf((age - SCORCH_FULL) / (SCORCH_GONE - SCORCH_FULL), 0.0, 1.0)
		(mark.material as StandardMaterial3D).albedo_color = Color(1, 1, 1, alpha)
		kept.append(mark)
	_marks = kept
	var data := FINDS.state()
	var rows: Variant = data.get("scorches", [])
	if rows is Array and not (rows as Array).is_empty():
		var left: Array = (rows as Array).filter(func(row: Variant) -> bool: return row is Array and (row as Array).size() >= 8 and now - float(row[6]) < SCORCH_GONE and now - float(row[6]) >= -1.0)
		if left.size() != (rows as Array).size():
			data.scorches = left
			FINDS.changed()

## A ragged black burn: dark in the middle, a sooty ring fading out, broken up by noise.
static func _make_scorch() -> ImageTexture:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.06
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5, y - size * 0.5) / (size * 0.5)
			var r := d.length() + noise.get_noise_2d(x, y) * 0.22
			var alpha := clampf(1.0 - smoothstep(0.35, 0.95, r), 0.0, 1.0) * 0.92
			var shade := lerpf(0.02, 0.12, smoothstep(0.0, 0.8, r))
			image.set_pixel(x, y, Color(shade, shade * 0.95, shade * 0.9, alpha))
	return ImageTexture.create_from_image(image)

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
