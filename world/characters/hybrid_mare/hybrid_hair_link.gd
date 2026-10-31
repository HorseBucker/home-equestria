extends Node
## The devkit mane uses mHead/mChest, its tail mTail1..6. Copy the linked
## OpenPony head and native pelvis *inside* skeleton_updated, before skinning.
var body: Skeleton3D
var head: Skeleton3D
var hair: Skeleton3D
var body_hips := -1
var hair_pelvis := -1
var pelvis_offset := Transform3D.IDENTITY
var head_pairs: Array[Vector2i] = []
var head_offsets: Array[Vector3] = []
## Off while the far render LOD shows a merged mesh on the body skeleton alone.
var enabled := true
var skull_frame := Transform3D.IDENTITY
var _head_rest_inverse := Transform3D.IDENTITY
## 0..1, set by pony_carry.gd while she is bridal carried: her head tips far back against her neck
## there, and the back of the mane (on mChest/mNeck) would fold into her throat. Those bones then
## ride along with the skull instead, chest less than neck.
var follow_head := 0.0
const FOLLOW_SHARE := [0.6, 1.0] # mChest, mNeck.
const PROFILE := preload("res://tools/crowd_cpu_profile.gd")
## Unchanged links are not rewritten (0.1.0 perf pass): a pose write makes the hair rig re-skin, and
## a still body and head handed it the same four bones every tick. A bone is written again once its
## target leaves Transform3D.is_equal_approx of the last written one (a hundredth of a millimetre),
## so the hair never trails by more than that. The mane chain is written whole when any of it, or
## the pelvis below it, changed. Rollback: SKIP_UNCHANGED = false.
const SKIP_UNCHANGED := true
var _pelvis_written := Transform3D()
var _head_written: Array[Transform3D] = [Transform3D(), Transform3D(), Transform3D()]
var _pelvis_valid := false
var _head_valid := false
## The pelvis moved since the mane chain was last written: its locals must be rewritten.
var _pelvis_moved := true

func bind(body_sk: Skeleton3D, head_sk: Skeleton3D, hair_sk: Skeleton3D,
		tail_offset_world := Vector3.ZERO, mane_offset_world := Vector3.ZERO) -> void:
	body = body_sk
	head = head_sk
	hair = hair_sk
	_head_rest_inverse = head.get_bone_global_rest(head.find_bone("mHead")).affine_inverse()
	body_hips = body.find_bone("pony_hips")
	hair_pelvis = hair.find_bone("mPelvis")
	var body_rest := body.global_transform * body.get_bone_global_rest(body_hips)
	var hair_rest := hair.global_transform * hair.get_bone_global_rest(hair_pelvis)
	hair_rest.origin += tail_offset_world
	pelvis_offset = body_rest.affine_inverse() * hair_rest
	for name in ["mChest","mNeck","mHead"]:
		var pair := Vector2i(head.find_bone(name),hair.find_bone(name))
		head_pairs.append(pair)
		# The mane offset is fixed in each bone's own frame, so it nods with the head.
		var rest := head.global_transform * head.get_bone_global_rest(pair.x)
		head_offsets.append(rest.basis.inverse() * mane_offset_world)
	body.skeleton_updated.connect(_body_updated)
	head.skeleton_updated.connect(_head_updated)

func _body_updated() -> void:
	if not enabled or not is_instance_valid(hair) or not hair.is_inside_tree():
		_pelvis_valid = false; _head_valid = false
		return
	var started := Time.get_ticks_usec() if PROFILE.enabled else 0
	var world := body.global_transform * body.get_bone_global_pose(body_hips) * pelvis_offset
	var target := hair.global_transform.affine_inverse()*world
	if not (SKIP_UNCHANGED and _pelvis_valid and target.is_equal_approx(_pelvis_written)):
		hair.set_bone_global_pose(hair_pelvis,target)
		_pelvis_written = target
		_pelvis_valid = true
		_pelvis_moved = true
	if PROFILE.enabled: PROFILE.record("hair_link", started)

func _head_updated() -> void:
	if not enabled or not is_instance_valid(hair) or not hair.is_inside_tree():
		_pelvis_valid = false; _head_valid = false
		return
	var started := Time.get_ticks_usec() if PROFILE.enabled else 0
	var targets: Array[Transform3D] = []
	var changed := not SKIP_UNCHANGED or not _head_valid or _pelvis_moved \
		or head_pairs.size() != _head_written.size()
	var into_hair := hair.global_transform.affine_inverse()
	for i in head_pairs.size():
		var pair := head_pairs[i]
		var posed := head.get_bone_global_pose(pair.x)
		if i < 2 and follow_head > 0.0:
			var skull := head.get_bone_global_pose(head_pairs[2].x) * _head_rest_inverse
			posed = posed.interpolate_with(skull * head.get_bone_global_rest(pair.x), follow_head * FOLLOW_SHARE[i])
		if i == 2:
			var motion := posed * _head_rest_inverse
			posed = motion * skull_frame * motion.affine_inverse() * posed
		var world := head.global_transform * posed * Transform3D(Basis.IDENTITY, head_offsets[i])
		var target := into_hair*world
		targets.append(target)
		if not changed and not target.is_equal_approx(_head_written[i]): changed = true
	if changed:
		# Parent first (mChest, mNeck, mHead): each local pose reads its freshly written parent.
		for i in head_pairs.size(): hair.set_bone_global_pose(head_pairs[i].y, targets[i])
		_head_written = targets
		_head_valid = true
		_pelvis_moved = false
	if PROFILE.enabled: PROFILE.record("hair_link", started)
