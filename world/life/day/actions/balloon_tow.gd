extends Node
## The hot-air balloon on Cherry Berry's rope (walk_balloon.gd), moved and drawn every rendered frame
## (2026-11-22 play test: "The rope lagged behind her, and the balloon kind of just teleported overhead as she walked";
## the rise and the landing "teleporting up in chunks"). The day step's tick only says what happens next; this node
## places the balloon and the rope from where she is drawn (her interpolated transform: physics interpolation is on,
## so her physics position runs ahead of and behind the picture between physics ticks).
##
## The rope: a tube along a curve from between her lips. It leaves her mouth forward along her muzzle, as bitten, and
## bends up to the basket. Sized by her body_scale, so it sits in the mouth at canon height and at JRHNBR.
## The balloon: eased (critically damped) toward TOW_HEIGHT over her and a little behind, never snapped.

const TOW_HEIGHT := 12.0         # basket bottom over her: clear of Ponyville's roofs (about 9 m), not high above them
const TRAIL := 2.5               # metres behind her
const FOLLOW := 1.6              # how fast it catches up (per second; a soft lag, like a balloon on a line)
const RADIUS := 0.016
const SIDES := 6
const STEPS := 14                # along the bend at her mouth
const BITE_IN := 0.035           # behind the upper lip, between the teeth (at body_scale 1)
const BITE_DOWN := 0.0
const CHEEK := Vector3(0.2, 0.04, 0.34)    # where the bend ends: out to her right, a little up, back along her jaw (body_scale 1)
const ASIDE := 1.4               # the balloon trails this far to her right too, so the rope leans away from her head

var actor: Node3D
var ship: Node3D
var mode := "rise"               # rise -> tow -> land -> done
var seconds := 0.0
var rise_seconds := 5.0
var land_seconds := 6.0
var land_at := Vector3.INF

var _hold := Vector3.INF
var _vel := Vector3.ZERO
var _from := Vector3.INF
var _rope: MeshInstance3D
var _mesh: ImmediateMesh
var _scale := 1.0
var _head := -1
var _lip := -1
var _skeleton: Skeleton3D


func begin(pony: Node3D, balloon: Node3D) -> void:
	actor = pony; ship = balloon
	_scale = float(pony.get("body_scale")) if pony.get("body_scale") != null else 1.0
	_from = ship.global_position; _hold = _from
	ship.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rope = MeshInstance3D.new(); _rope.name = "BalloonRope"
	_mesh = ImmediateMesh.new(); _rope.mesh = _mesh
	var material := StandardMaterial3D.new(); material.albedo_color = Color(0.74, 0.62, 0.42); material.roughness = 0.95; material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rope.material_override = material
	_rope.top_level = true
	_rope.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_rope)
	process_priority = 1000          # after her animation has posed her head this frame
	mode = "rise"; seconds = 0.0


func land(at: Vector3) -> void:
	land_at = at; _from = _hold; mode = "land"; seconds = 0.0


func risen() -> bool: return mode != "rise"
func landed() -> bool: return mode == "done"


func finish() -> void:
	if is_instance_valid(ship):
		ship.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
		ship.reset_physics_interpolation()
	queue_free()


func _process(delta: float) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(ship): return
	seconds += delta
	var drawn := actor.get_global_transform_interpolated()
	var bite := _bite(drawn)
	var forward := _muzzle(drawn)
	var behind := -Vector3(forward.x, 0.0, forward.z).normalized() if Vector2(forward.x, forward.z).length() > 0.01 else drawn.basis.z.normalized()
	var over := drawn.origin + Vector3.UP * TOW_HEIGHT + behind * TRAIL - behind.cross(Vector3.UP).normalized() * ASIDE
	match mode:
		"rise":
			var t := clampf(seconds / rise_seconds, 0.0, 1.0)
			_hold = _from.lerp(over, t * t * (3.0 - 2.0 * t))
			_vel = Vector3.ZERO
			if t >= 1.0: mode = "tow"
		"tow":
			# critically damped spring: smooth start and stop, no overshoot, no snapping
			var omega := FOLLOW * 2.0
			var x := _hold - over
			var temp := (_vel + omega * x) * delta
			var e := exp(-omega * delta)
			_vel = (_vel - omega * temp) * e
			_hold = over + (x + temp) * e
		"land":
			var t := clampf(seconds / land_seconds, 0.0, 1.0)
			_hold = _from.lerp(land_at, t * t * (3.0 - 2.0 * t))
			if t >= 1.0: mode = "done"
	ship.global_position = _hold
	if ship is CharacterBody3D: (ship as CharacterBody3D).velocity = Vector3.ZERO
	_draw_rope(bite, forward, _hold + Vector3.UP * 0.1)


## Between her lips: just in from the upper lip, a little down toward the lower one (scaled to her size).
func _bite(drawn: Transform3D) -> Vector3:
	var lip := _bone_at(drawn, true)
	if not lip.is_finite(): return drawn * (Vector3(0, 0.9, -0.6) * _scale)
	var forward := _muzzle(drawn)
	return lip - forward * BITE_IN * _scale + Vector3.DOWN * BITE_DOWN * _scale


## The way her muzzle points: head bone to upper lip.
func _muzzle(drawn: Transform3D) -> Vector3:
	var lip := _bone_at(drawn, true)
	var head := _bone_at(drawn, false)
	if lip.is_finite() and head.is_finite() and lip.distance_to(head) > 0.02: return (lip - head).normalized()
	return -drawn.basis.z.normalized()


## A head bone where it is drawn this frame (bone poses are relative to her physics transform; moved onto her drawn one).
func _bone_at(drawn: Transform3D, lip: bool) -> Vector3:
	if not is_instance_valid(_skeleton):
		var boop: Variant = actor.get("boop_node")
		var sk: Variant = (boop as Object).get("head_skeleton") if boop is Object else null
		if not sk is Skeleton3D: return Vector3.INF
		_skeleton = sk
		_lip = _skeleton.find_bone("mFaceLipUpperCenter")
		if _lip < 0: _lip = _skeleton.find_bone("mFaceNoseBase")
		_head = _skeleton.find_bone("mHead")
	var bone := _lip if lip else _head
	if bone < 0: return Vector3.INF
	var at := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin
	return drawn * (actor.global_transform.affine_inverse() * at)


## The rope: crosswise in her teeth, out of the right corner of her mouth, bent back along her cheek (a short curve),
## then straight and taut up to the basket.
func _draw_rope(bite: Vector3, forward: Vector3, top: Vector3) -> void:
	_mesh.clear_surfaces()
	if top.distance_to(bite) < 0.3: return
	var level := Vector3(forward.x, 0.0, forward.z).normalized() if Vector2(forward.x, forward.z).length() > 0.01 else forward
	var right := level.cross(Vector3.UP).normalized()
	var s := _scale
	var cheek := bite + right * CHEEK.x * s + Vector3.UP * CHEEK.y * s - level * CHEEK.z * s
	var up_line := (top - cheek).normalized()
	var p0 := bite - right * 0.03 * s                       # (its end tucked behind the far side of her teeth)
	var p1 := bite + right * 0.10 * s
	var p2 := cheek - up_line * 0.10 * s
	var points: Array[Vector3] = []
	for i in STEPS + 1:
		var t := float(i) / STEPS
		var u := 1.0 - t
		points.append(u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * cheek)
	points.append(cheek + (top - cheek) * 0.5)
	points.append(top)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in points.size():
		var along := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := along.cross(Vector3.UP if absf(along.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
		var other := along.cross(side).normalized()
		var ring: Array[Vector3] = []
		for k in SIDES:
			var a := TAU * float(k) / SIDES
			ring.append(side * cos(a) + other * sin(a))
		rings.append(ring)
	var r := RADIUS * s
	for i in points.size() - 1:
		for k in SIDES:
			var k2 := (k + 1) % SIDES
			var n_a: Vector3 = rings[i][k]; var n_b: Vector3 = rings[i][k2]; var n_c: Vector3 = rings[i + 1][k]; var n_d: Vector3 = rings[i + 1][k2]
			for pair: Array in [[n_a, points[i]], [n_c, points[i + 1]], [n_b, points[i]], [n_b, points[i]], [n_c, points[i + 1]], [n_d, points[i + 1]]]:
				_mesh.surface_set_normal(pair[0]); _mesh.surface_add_vertex(pair[1] + (pair[0] as Vector3) * r)
	_mesh.surface_end()
