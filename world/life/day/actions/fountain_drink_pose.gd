extends SkeletonModifier3D
## The body pose for drinking at the Town Square fountain (play test 2026-11-16: "Would like the
## fountain drinking to work with ponies of all sizes. At the canon and JTRHNBR heights, they need to
## put their forelegs up on the rim of the fountain and lean their heads down to the water. At the
## taller height settings for the ponies, they just need to walk closer and lean down to drink.").
## A modifier on her body skeleton, layered after locomotion the way affection_pose.gd layers its
## supported rear (her visible head follows through hybrid_neck_link.gd). fountain_drinker.gd drives
## it: `rear`, `hooves` and `head` ease 0..1, `bob` lifts the muzzle between sips.
##
## Two plans, both fitted to HER measured body against the basin (not to the size preset's name):
## - "lean": she stands with her chest just clear of the outer wall and lowers her neck over the
##   rim to the water.
## - "rear": she stands closer, pitches her body up about her hind hips (the hind hooves stay where
##   they stood), lifts her forehooves one after the other onto the flat rim top and lowers her neck
##   between and over them to the water.
## probe() tries both on the real rig (inside joint limits, every bone restored after) and reports
## how close her muzzle and hooves get; the drinker picks lean when it reaches, else rear.
## Never stretches a bone: legs and neck are bounded rotational CCD inside pony_joint_limits.gd.

## The basin, in the fountain's own space (fountain_water.gd measured it 2026-11-16): the flat rim top
## at y 0.97 between r 2.6 and 3.0, the outer wall down to the plinth at r 3.19, the water at y 0.94.
## The fountain node may sit at any height over the ground (the town rebuild re-seated it 0.20 m
## lower): heights above HER ground are always measured at run time.
const RIM_TOP_Y := 0.97
const RIM_IN_R := 2.6
const RIM_OUT_R := 3.0
const OUTER_R := 3.19
const WATER_Y := 0.94
## Forehooves on the middle of the rim top; the muzzle 0.35 m inside the inner edge, at the surface.
const HOOF_R := 2.8
const SIP_R := 2.54            # just inside the inner edge (2.6): the water reaches the wall at 2.63; 2.25 was out of every size's reach (2026-11-17)
const MAX_PITCH := deg_to_rad(55.0)
## Forelegs on the rim: the point of her shoulder pitched up to this far (x her standing shoulder
## height) above the rim top, and her hoof this far ahead of it: forelegs reaching forward onto the
## stone, like a dog's paws on a counter. Measured 2026-11-16 (lab_agent_f.gd): at the Canon size the
## shoulder joint stands 0.46 m, only 0.22 m ahead of the hip, so even the steepest pitch leaves it
## a little under a 0.77 m rim; the pitch is then the most MAX_PITCH allows.
const SHOULDER_OVER_RIM := 0.1
const HOOF_AHEAD := 0.45
## Big enough at all: the pitched shoulder no lower than this (x shoulder height) under the rim top.
const SHOULDER_UNDER_RIM := 0.5
## Her chest's front is this far (x body scale) ahead of the point of her shoulder; it stays
## CHEST_CLEAR (x body scale) off the outer wall when she leans.
const CHEST_FRONT := 0.09
const CHEST_CLEAR := 0.03
## Lift over the rim's edge on the way up (x body scale), and the hoof's curl in the air.
const HOOF_LIFT := 0.07
const HOOF_CURL := deg_to_rad(35.0)
const FORE_CAP := deg_to_rad(80.0)
const DIP_DEGREES := 11.0
## Reared, the muzzle goes to the rim's inner lip (a sip over the edge, not a stretch down to the water):
## this far inside the inner edge and above the rim top, in the fountain's metres.
const LIP_IN := 0.04
const LIP_UP := 0.03

var pony: CharacterBody3D
## The fountain's water node (fountain_water.gd): the basin's frame.
var water: Node3D
## Pose controls, 0..1, eased here with smoothstep; `bob` in metres.
var rear := 0.0
var hooves: Array[float] = [0.0, 0.0]
var head := 0.0
var bob := 0.0
## Leaning: her front dips this far (0..1 of DIP_DEGREES) about her hind hips, her forelegs buckling at the knees
## (2026-11-18 play test: "her forelegs should buckle slightly to get lower, and her neck shouldn't stretch
## unrealistically long", the tall sizes and the princesses).
var dip := 0.0
## Coming down off the rim: the forehooves go straight back to the ground with her body, no lift in the air
## (play test: "her forelegs stuck straight up and then came down as she was exiting").
var descending := false
## The chosen plan (a probe() row plus the anchored targets).
var plan: Dictionary = {}
## The world mouth point (Affection.mouth_point()) to bind against her head, set by the drinker.
var bind_mouth := Vector3.INF
var mouth_in_head := Vector3.INF
var probe_wanted := false
## {"lean": row, "rear": row} once probed; each row: advance, pitch, mouth gap, hoof errors.
var probe: Dictionary = {}
var anchor_wanted := false
var anchored := false
## Numbers for tests (the lab prints them): world metres.
var metrics: Dictionary = {}

var _bound := false
var _head := -1
var _neck: Array[int] = []
var _root := -1
var _flanks: Array[int] = []
var _arms: Array[int] = []
## Per leg (FL, FR, RL, RR): the foot bone the leg places, its tip, the chain above it (nearest
## first, up to the shoulder/flank), and the tip's height over the sole.
var _feet: Array[int] = []
var _tips: Array[int] = []
var _chains: Array = []
var _end_heights: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Anchors in her body's (CharacterBody3D) frame: the four foot bones as they stood.
var _anchors: Array[Transform3D] = []
var _delta: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


func _bind(sk: Skeleton3D) -> bool:
	_head = sk.find_bone("pony_head")
	if _head < 0: return false
	_neck.clear()
	for name: String in ["pony_head", "pony_neck2", "pony_neck1", "pony_spine3"]:
		var bone := sk.find_bone(name)
		if bone >= 0: _neck.append(bone)
	var hips := sk.find_bone("pony_hips")
	if hips < 0: return false
	_root = hips
	while sk.get_bone_parent(_root) >= 0: _root = sk.get_bone_parent(_root)
	_flanks.clear(); _arms.clear(); _feet.clear(); _tips.clear(); _chains.clear()
	for side: String in ["L", "R"]:
		_flanks.append(sk.find_bone("pony_flank_" + side))
		_arms.append(sk.find_bone("pony_upperArm_" + side))
	for leg: Array in [["pony_finger_L", "pony_shoulder_L"], ["pony_finger_R", "pony_shoulder_R"], ["pony_hoof_L", "pony_flank_L"], ["pony_hoof_R", "pony_flank_R"]]:
		var foot := sk.find_bone(leg[0])
		var top := sk.find_bone(leg[1])
		var tip := sk.find_bone(str(leg[0]) + "_end")
		if foot < 0 or top < 0 or tip < 0: return false
		var chain: Array[int] = []
		var bone := sk.get_bone_parent(foot)
		while bone >= 0:
			chain.append(bone)
			if bone == top: break
			bone = sk.get_bone_parent(bone)
		if chain.is_empty() or chain[-1] != top: return false
		_feet.append(foot); _tips.append(tip); _chains.append(chain)
	if -1 in _flanks or -1 in _arms: return false
	var profile: Resource = pony.get("profile")
	if profile != null and profile.get("legs") != null and (profile.legs as Array).size() == 4:
		for i in 4: _end_heights[i] = float(profile.legs[i].end_height)
	_bound = true
	return true


func _process_modification_with_delta(_d: float) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(water): return
	var sk := get_skeleton()
	if sk == null or (not _bound and not _bind(sk)): return
	var idle := rear <= 0.0001 and head <= 0.0001 and hooves[0] <= 0.0001 and hooves[1] <= 0.0001
	if bind_mouth.is_finite() and idle:
		# Against this pass's head (the pose locomotion built), like affection_pose.gd: outside the
		# skeleton update the body skeleton holds its unmodified pose.
		mouth_in_head = (sk.global_transform * sk.get_bone_global_pose(_head)).affine_inverse() * bind_mouth
		bind_mouth = Vector3.INF
	if probe_wanted and mouth_in_head.is_finite() and idle:
		probe_wanted = false
		_probe(sk)
		return
	if anchor_wanted and idle and not plan.is_empty():
		anchor_wanted = false
		_anchor(sk)
	if idle or not anchored:
		metrics.clear()
		return
	var world: Array[Transform3D] = []
	for anchor: Transform3D in _anchors: world.append(pony.global_transform * anchor)
	_apply(sk, world, _delta, Vector3.ZERO, float(plan.pitch), plan.mouth + Vector3.UP * bob, rear, hooves, head, dip)
	_measure(sk)


## The basin's frame from the pony: its centre (world, at the fountain's origin), the way out to her,
## the fountain's own scale, and the rim/water heights (world y).
func basin() -> Dictionary:
	var centre := water.to_global(Vector3.ZERO)
	var out := pony.global_position - centre
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 0.0001 else Vector3.BACK
	return {"centre": centre, "out": out, "k": water.global_basis.x.length(),
		"rim_y": water.to_global(Vector3(0.0, RIM_TOP_Y, 0.0)).y, "water_y": water.to_global(Vector3(0.0, WATER_Y, 0.0)).y}


## Horizontal distance from the basin's axis.
static func _r(point: Vector3, centre: Vector3) -> float:
	return Vector2(point.x - centre.x, point.z - centre.z).length()


## Whether `actor` is big enough for this basin at all: her shoulders, pitched the most a rear
## allows, come within SHOULDER_UNDER_RIM of their height under a rim `rim_height` over her ground. Measured
## from her own rig x her size (fillies are 0.62 of the preset), before she walks over; the probe
## then fits the real pose. A foal at the Canon size cannot (lab_agent_f.gd, 2026-11-16). True for
## a rig this cannot measure (it drinks with the plain look down).
static func fits(actor: Node, rim_height: float) -> bool:
	var row := size_report(actor, rim_height)
	return row.is_empty() or bool(row.fits)


## fits()'s numbers (metres over her ground; empty for a rig it cannot measure).
static func size_report(actor: Node, rim_height: float) -> Dictionary:
	var sk: Skeleton3D = actor.get("skeleton") as Skeleton3D
	if sk == null or not (actor is Node3D): return {}
	var bones: Array[int] = [sk.find_bone("pony_flank_L"), sk.find_bone("pony_flank_R"), sk.find_bone("pony_upperArm_L"), sk.find_bone("pony_upperArm_R")]
	if -1 in bones: return {}
	# Her live skeleton in the world, against her own ground (whatever the rig's own space).
	var body := actor as Node3D
	var world := sk.global_transform
	var hinge := world * ((sk.get_bone_global_pose(bones[0]).origin + sk.get_bone_global_pose(bones[1]).origin) * 0.5) - body.global_position
	var shoulder := world * ((sk.get_bone_global_pose(bones[2]).origin + sk.get_bone_global_pose(bones[3]).origin) * 0.5) - body.global_position
	var along := Vector2(shoulder.x - hinge.x, shoulder.z - hinge.z).length()
	var up := shoulder.y - hinge.y
	var reach := hinge.y + along * sin(MAX_PITCH) + up * cos(MAX_PITCH)
	return {"hinge": hinge, "shoulder": shoulder, "reach": reach, "least": rim_height - SHOULDER_UNDER_RIM * shoulder.y, "rim": rim_height,
		"fits": reach >= rim_height - SHOULDER_UNDER_RIM * shoulder.y}


func _forward() -> Vector3:
	var forward := -pony.global_basis.z
	forward.y = 0.0
	return forward.normalized()


## Both plans for where she stands now (facing the basin), tried on the rig, every bone restored.
func _probe(sk: Skeleton3D) -> void:
	var b := basin()
	var s := float(pony.get("body_scale"))
	var root := pony.global_position
	var forward := _forward()
	var world := sk.global_transform
	var f := func(p: Vector3) -> float: return (p - root).dot(forward)
	var u := func(p: Vector3) -> float: return p.y - root.y
	var hinge: Vector3 = world * ((sk.get_bone_global_pose(_flanks[0]).origin + sk.get_bone_global_pose(_flanks[1]).origin) * 0.5)
	var shoulder: Vector3 = world * ((sk.get_bone_global_pose(_arms[0]).origin + sk.get_bone_global_pose(_arms[1]).origin) * 0.5)
	var standing := float(u.call(shoulder))
	var r0 := _r(root, b.centre)
	var mouth: Vector3 = b.centre + b.out * SIP_R * b.k
	mouth.y = b.water_y + 0.005
	# Lean: her chest's front CHEST_CLEAR off the outer wall.
	var lean_r: float = OUTER_R * b.k + (CHEST_CLEAR + CHEST_FRONT) * s + float(f.call(shoulder))
	# Rear: the pitch that lifts her shoulders SHOULDER_OVER_RIM of their height above the rim, then
	# the stand that puts her hooves HOOF_AHEAD ahead of them on the rim's middle.
	var rim_h: float = b.rim_y - root.y
	var want := rim_h + SHOULDER_OVER_RIM * standing
	var dfs: float = float(f.call(shoulder)) - float(f.call(hinge))
	var dus: float = float(u.call(shoulder)) - float(u.call(hinge))
	var lift := func(angle: float) -> float: return float(u.call(hinge)) + dfs * sin(angle) + dus * cos(angle)
	var pitch := MAX_PITCH
	if float(lift.call(0.0)) >= want: pitch = 0.0
	elif float(lift.call(MAX_PITCH)) > want:
		var low := 0.0
		var high := MAX_PITCH
		for i in 20:
			var mid := (low + high) * 0.5
			if float(lift.call(mid)) < want: low = mid
			else: high = mid
		pitch = (low + high) * 0.5
	var ahead := float(f.call(hinge)) + dfs * cos(pitch) - dus * sin(pitch)
	# Her chest stays outside the outer wall unless the pitch lifts her shoulders over the rim top
	# (at the Canon size it cannot: 0.66 m against 0.77 m); her hooves land as near the rim's middle as
	# her forelegs reach from there (lab_agent_f.gd, 2026-11-16).
	var raised: float = lift.call(pitch)
	var leg := 0.92 * standing
	var reach := sqrt(maxf(0.0, leg * leg - pow(rim_h - raised, 2.0)))
	var shoulder_r: float = HOOF_R * b.k + HOOF_AHEAD * standing
	if raised < rim_h + 0.05 * s: shoulder_r = maxf(shoulder_r, OUTER_R * b.k + (CHEST_FRONT + CHEST_CLEAR) * s)
	var hoof_r := clampf(shoulder_r - minf(shoulder_r - HOOF_R * b.k, reach * 0.95), (RIM_IN_R + 0.06) * b.k, (RIM_OUT_R - 0.07) * b.k)
	var rear_r: float = shoulder_r + ahead
	probe = {"standing_shoulder": standing, "rim_height": rim_h, "water_height": b.water_y - root.y, "r_now": r0, "scale": s}
	var saved: Array[Transform3D] = []
	for bone in sk.get_bone_count(): saved.append(sk.get_bone_pose(bone))
	for row: Array in [["lean", lean_r, 0.0], ["rear", rear_r, pitch]]:
		var advance: float = r0 - float(row[1])
		var offset := forward * advance
		var anchors: Array[Transform3D] = []
		for foot: int in _feet:
			var t := world * sk.get_bone_global_pose(foot)
			t.origin += offset
			anchors.append(t)
		var deltas := _hoof_deltas(sk, anchors, b, offset, hoof_r)
		var reared := str(row[0]) == "rear"
		var goal := _mouth_goal(b, str(row[0]))
		plan.mouth = goal
		_apply(sk, anchors, deltas, offset, float(row[2]), goal, 1.0 if reared else 0.0, [1.0, 1.0] if reared else [0.0, 0.0], 1.0, 0.0 if reared else 1.0)
		_measure(sk, b, root + offset)
		var result := metrics.duplicate()
		result.merge({"advance": advance, "stand_r": float(row[1]), "pitch": float(row[2]), "mouth": goal, "hoof_r": hoof_r})
		result.mouth_gap = (result.mouth_point as Vector3).distance_to(goal) if result.has("mouth_point") else INF
		probe[row[0]] = result
		for bone in saved.size(): sk.set_bone_pose(bone, saved[bone])
	metrics.clear()
	plan = {}


## Use a probed plan ("lean" or "rear") from here on.
func choose(kind: String) -> void:
	plan = (probe.get(kind, {}) as Dictionary).duplicate()
	plan.kind = kind
	anchored = false


## Fix the four hooves where she stands now (after the step closer) and aim the forehooves at the rim.
func _anchor(sk: Skeleton3D) -> void:
	_anchors.clear()
	var to_body := pony.global_transform.affine_inverse()
	var world: Array[Transform3D] = []
	for foot: int in _feet:
		var t := sk.global_transform * sk.get_bone_global_pose(foot)
		world.append(t)
		_anchors.append(to_body * t)
	_delta = _hoof_deltas(sk, world, basin(), Vector3.ZERO, float(plan.get("hoof_r", HOOF_R * float(basin().k))))
	var b := basin()
	plan.mouth = _mouth_goal(b, str(plan.get("kind", "lean")))
	anchored = true


## Where her muzzle goes: the water just inside the inner edge when she leans, the rim's inner lip when reared.
func _mouth_goal(b: Dictionary, kind: String) -> Vector3:
	if kind == "rear":
		var lip: Vector3 = b.centre + b.out * (RIM_IN_R - LIP_IN) * b.k
		lip.y = b.rim_y + LIP_UP * b.k
		return lip
	var water_point: Vector3 = b.centre + b.out * SIP_R * b.k
	water_point.y = b.water_y + 0.005
	return water_point


## World moves that carry each forehoof (its foot bone) from where it stands onto the rim top: its
## middle (between the foot bone and the tip) `hoof_r` (world metres) from the axis, its sole on the stone.
func _hoof_deltas(sk: Skeleton3D, anchors: Array[Transform3D], b: Dictionary, offset: Vector3, hoof_r: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var forward := _forward()
	var side := forward.cross(Vector3.UP)
	var ground := pony.global_position.y + offset.y
	for k in 2:
		var tip: Vector3 = sk.global_transform * sk.get_bone_global_pose(_tips[k]).origin + offset
		var middle: Vector3 = (anchors[k].origin + tip) * 0.5
		var across: float = (middle - b.centre).dot(side)
		var goal: Vector3 = b.centre + b.out * sqrt(maxf(0.0, hoof_r * hoof_r - across * across)) + side * across
		var move := goal - middle
		move.y = b.rim_y - ground + 0.004
		out.append(move)
	return out


## The pose: torso pitched about the hind hips, hind hooves back on their anchors, forehooves along
## their path to the rim, the muzzle eased toward `mouth`. Skeleton space throughout.
func _apply(sk: Skeleton3D, anchors: Array[Transform3D], deltas: Array[Vector3], offset: Vector3, pitch: float, mouth: Vector3,
		rear_amount: float, hoof_amounts: Array, head_amount: float, dip_amount := 0.0) -> void:
	var to_sk := sk.global_transform.affine_inverse()
	var forward := _forward()
	var side_w := forward.cross(Vector3.UP).normalized()
	var axis := (to_sk.basis * side_w).normalized()
	var s := float(pony.get("body_scale"))
	var root_pose := sk.get_bone_global_pose(_root)
	if offset != Vector3.ZERO: root_pose.origin += to_sk.basis * offset
	var angle := pitch * smoothstep(0.0, 1.0, rear_amount) - deg_to_rad(DIP_DEGREES) * smoothstep(0.0, 1.0, dip_amount)
	var turn := Basis(axis, angle)
	var moved := absf(angle) > 0.0001
	if moved:
		# The rig root is a rigid frame: turn it about the hind-hip line (affection_pose.gd _rear_pose).
		var hinge := (sk.get_bone_global_pose(_flanks[0]).origin + sk.get_bone_global_pose(_flanks[1]).origin) * 0.5
		if offset != Vector3.ZERO: hinge += to_sk.basis * offset
		root_pose.origin = hinge + turn * (root_pose.origin - hinge)
		root_pose.basis = turn * root_pose.basis
	if offset != Vector3.ZERO or moved: sk.set_bone_global_pose(_root, root_pose)
	if moved or offset != Vector3.ZERO or float(hoof_amounts[0]) > 0.0001 or float(hoof_amounts[1]) > 0.0001:
		for k in [2, 3]:
			_turn(sk, _flanks[k - 2], turn.get_rotation_quaternion().inverse())
			_place(sk, k, to_sk * anchors[k])
	# The neck before the forelegs: spine3 carries the shoulders.
	if head_amount > 0.0001 and mouth_in_head.is_finite():
		_reach_neck(sk, to_sk * mouth, head_amount, rear_amount > 0.5)
	if moved or offset != Vector3.ZERO or float(hoof_amounts[0]) > 0.0001 or float(hoof_amounts[1]) > 0.0001:
		for k in 2:
			var t := clampf(float(hoof_amounts[k]), 0.0, 1.0)
			var start := anchors[k]
			var move := deltas[k]
			var level := Vector3(move.x, 0.0, move.z)
			var lift := HOOF_LIFT * s
			var goal := start
			if descending:
				# down with her body, straight back to where it stood
				goal.origin += move * smoothstep(0.0, 1.0, t)
			else:
				goal.origin += level * smoothstep(0.3, 1.0, t) + Vector3.UP * ((move.y + lift) * smoothstep(0.0, 0.55, t) - lift * smoothstep(0.8, 1.0, t))
				# In the air the hoof folds back (toe down), flat again as it lands.
				goal.basis = Basis(side_w, -HOOF_CURL * sin(PI * t)) * start.basis
			_place(sk, k, to_sk * goal)


## Bring her muzzle toward `goal` (skeleton space, eased by `amount`): CCD over head, neck and the
## front of her back. A drink bends the neck down past the range the gait clips measured (the rig's
## limits are 30 degrees a joint, play test 2026-11-16: her muzzle stopped half a metre short), so
## each bone is held to NECK_CAPS of turn from the pose locomotion gave it instead.
## Leaning (2026-11-18 play test, the tall sizes and the princesses: the neck "stretching unrealistically long"):
## a modest bend, the rest of the reach from her front dipping (DIP_DEGREES) on buckled forelegs.
const NECK_CAPS := {"pony_head": 48.0, "pony_neck2": 30.0, "pony_neck1": 30.0, "pony_spine3": 10.0}
## Reared up with her forehooves on the rim (2026-11-18 play test: "Is it not possible to get them to get up on
## their hindlegs and put their forelegs over the rim and take a sip?"): her body is pitched up to 55 degrees, so
## the neck curls further down between the forelegs to reach the water, as a dog's does over a counter's edge.
## (play test: "It doesn't have to look like she's fully getting her head down ... a little lean down without
## stretching her neck": her muzzle goes to the rim's inner lip, LIP_IN / LIP_UP.)
const REAR_NECK_CAPS := {"pony_head": 60.0, "pony_neck2": 40.0, "pony_neck1": 40.0, "pony_spine3": 15.0}
func _reach_neck(sk: Skeleton3D, goal: Vector3, amount: float, reared := false) -> void:
	var caps: Dictionary = REAR_NECK_CAPS if reared else NECK_CAPS
	var at := sk.get_bone_global_pose(_head) * mouth_in_head
	goal = at.lerp(goal, smoothstep(0.0, 1.0, amount))
	var start: Dictionary = {}
	for bone: int in _neck: start[bone] = sk.get_bone_pose_rotation(bone)
	for pass_index in 16:
		if (sk.get_bone_global_pose(_head) * mouth_in_head).distance_to(goal) < 0.002: break
		for bone: int in _neck:
			var pivot := sk.get_bone_global_pose(bone).origin
			var from := sk.get_bone_global_pose(_head) * mouth_in_head - pivot
			var to := goal - pivot
			var cross := from.cross(to)
			if cross.length_squared() < 1e-12: continue
			var pose := sk.get_bone_global_pose(bone)
			pose.basis = Basis(Quaternion(cross.normalized(), minf(from.angle_to(to), deg_to_rad(10.0)))) * pose.basis
			sk.set_bone_global_pose(bone, pose)
			_cap_turn(sk, bone, start[bone], deg_to_rad(float(caps.get(sk.get_bone_name(bone), 30.0))))


## Hold `bone`'s local rotation within `cap` of `from`.
func _cap_turn(sk: Skeleton3D, bone: int, from: Quaternion, cap: float) -> void:
	var now := sk.get_bone_pose_rotation(bone)
	var angle := from.angle_to(now)
	if angle > cap: sk.set_bone_pose_rotation(bone, from.slerp(now, cap / angle))


## Put leg `k`'s foot bone at `goal` (skeleton space): CCD up its chain inside the joint limits, then
## the foot bone takes the goal's orientation (flat on its support) as far as its limits allow.
func _place(sk: Skeleton3D, k: int, goal: Transform3D) -> void:
	var foot: int = _feet[k]
	var chain: Array = _chains[k]
	# A foreleg reaching up onto the rim swings forward from the shoulder further than any gait does
	# (its measured limit stopped the hoof 13 cm under the rim top, 2026-11-16): shoulder and upper arm
	# turn up to FORE_CAP from their standing pose; the knee and below keep their joint limits.
	var start: Dictionary = {}
	if k < 2:
		for bone: int in chain:
			if sk.get_bone_name(bone).begins_with("pony_shoulder") or sk.get_bone_name(bone).begins_with("pony_upperArm"): start[bone] = sk.get_bone_pose_rotation(bone)
	for pass_index in 30:
		if sk.get_bone_global_pose(foot).origin.distance_to(goal.origin) < 0.001: break
		for bone: int in chain:
			var pivot := sk.get_bone_global_pose(bone).origin
			var from := sk.get_bone_global_pose(foot).origin - pivot
			var to := goal.origin - pivot
			var cross := from.cross(to)
			if cross.length_squared() < 1e-12: continue
			var turn := Quaternion(cross.normalized(), minf(from.angle_to(to), deg_to_rad(8.0)))
			if start.has(bone):
				var pose := sk.get_bone_global_pose(bone)
				pose.basis = Basis(turn) * pose.basis
				sk.set_bone_global_pose(bone, pose)
				_cap_turn(sk, bone, start[bone], FORE_CAP)
			else:
				_turn(sk, bone, turn)
	var pose := sk.get_bone_global_pose(foot)
	pose.basis = goal.basis
	sk.set_bone_global_pose(foot, pose)
	_limit(sk, foot)


## Rotate `bone` by `turn` (skeleton space, about its own origin), then keep it in its joint limits.
func _turn(sk: Skeleton3D, bone: int, turn: Quaternion) -> void:
	var pose := sk.get_bone_global_pose(bone)
	pose.basis = Basis(turn) * pose.basis
	sk.set_bone_global_pose(bone, pose)
	_limit(sk, bone)


func _limit(sk: Skeleton3D, bone: int) -> void:
	var limits: Variant = pony.get("joint_limits")
	if limits == null or not (limits.joints as Dictionary).has(bone): return
	var scale := sk.get_bone_pose_scale(bone)
	var held: Basis = limits.constrain(bone, Basis(sk.get_bone_pose_rotation(bone)))
	sk.set_bone_pose_rotation(bone, held.get_rotation_quaternion())
	sk.set_bone_pose_scale(bone, scale)


## World numbers for the posed skeleton: muzzle to its goal and to the water, each sole's height over
## the rim top (fore) or her ground (hind) and its distance from the axis, and how far the front of
## her chest and her elbows stay off the outer wall (negative: inside it below the rim top).
func _measure(sk: Skeleton3D, b: Dictionary = {}, root := Vector3.INF) -> void:
	if b.is_empty(): b = basin()
	if not root.is_finite(): root = pony.global_position
	var world := sk.global_transform
	var s := float(pony.get("body_scale"))
	metrics = {}
	if mouth_in_head.is_finite():
		var mouth := world * (sk.get_bone_global_pose(_head) * mouth_in_head)
		metrics.mouth_point = mouth
		metrics.mouth_above_water = mouth.y - float(b.water_y)
		metrics.mouth_r = _r(mouth, b.centre) / float(b.k)
		var goal: Vector3 = plan.get("mouth", Vector3.INF)
		metrics.mouth_gap = mouth.distance_to(goal) if goal.is_finite() else INF
	for k in 4:
		var sole := world * (sk.get_bone_global_pose(_tips[k]).origin - Vector3.UP * _end_heights[k])
		var name: String = ["FL", "FR", "RL", "RR"][k]
		metrics[name + "_r"] = _r(sole, b.centre) / float(b.k)
		metrics[name + "_over_rim"] = sole.y - float(b.rim_y)
		metrics[name + "_over_ground"] = sole.y - root.y
	var forward := _forward()
	var shoulder := world * ((sk.get_bone_global_pose(_arms[0]).origin + sk.get_bone_global_pose(_arms[1]).origin) * 0.5)
	var chest := shoulder + forward * CHEST_FRONT * s
	metrics.chest_r = _r(chest, b.centre) / float(b.k)
	metrics.chest_over_rim = chest.y - float(b.rim_y)
	# Off the wall: positive is clear (outside the outer wall, or above the rim top inside it).
	metrics.chest_clear = maxf(_r(chest, b.centre) - OUTER_R * float(b.k), chest.y - float(b.rim_y))
