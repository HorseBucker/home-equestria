extends Node3D
## The quill in a VR hand (docs/LETTERS_PLAN_2026_10_29.md section 7). The shop's "goods:quill"
## is the painting brush model for now (TODO: a real quill through the Blender MCP); its "Tip"
## node is the nib. Each physics tick of the hand holding it (briefcase_vr_hands.gd), the nib is
## tested against the open sheet of a letter draft in the other hand: within REACH in front of the
## writing face means dictating (letter_paper.gd dictate_tick), shown by a small ink glint at the
## nib. Pulling the quill away pauses. Attached to the held item on first use (on()), like
## world/items/photo_camera.gd.
const SHEET := preload("res://world/letters/paper/letter_sheet.gd")
## The nib this close in front of the paper (metres) is writing.
const REACH := 0.06
const EDGE := 0.015
const GLINT_PX := 32

var item: Node3D
var _tip: Node3D
var _glint: Sprite3D

static func on(held_item: Node3D) -> Node3D:
	var tool := held_item.get_node_or_null("QuillTool") as Node3D
	if tool != null: return tool
	tool = (load("res://world/letters/paper/quill_tool.gd") as GDScript).new()
	tool.name = "QuillTool"; tool.item = held_item
	held_item.add_child(tool)
	return tool

func _ready() -> void:
	_tip = item.find_child("Tip", true, false) as Node3D

## The nib in world space: the model's Tip, else the item's far end along -Z.
func tip() -> Vector3:
	if is_instance_valid(_tip): return _tip.global_position
	return item.global_transform * Vector3(0, 0, -0.17)

## Whether `point` is over the open sheet's writing face (within REACH in front of it).
static func over(sheet_root: Node3D, point: Vector3) -> bool:
	if sheet_root == null or not bool(sheet_root.get("opened")): return false
	var placed: Node3D = sheet_root.get("sheet")
	if placed == null or not placed.is_visible_in_tree(): return false
	var local := placed.global_transform.affine_inverse() * point
	# A sheet turned over shows its back (-Y) to the reader: the face to write on turns with it.
	if int(sheet_root.get("side")) == 1: local.y = -local.y
	return absf(local.x) <= SHEET.W * 0.5 + EDGE and absf(local.z) <= SHEET.H * 0.5 + EDGE and local.y >= -0.01 and local.y <= REACH

## VR, every physics tick in hand: dictating when the nib is over the open draft in the other hand.
func vr_step(inventory: Node, side: String) -> bool:
	var other := "left" if side == "right" else "right"
	var held: Dictionary = inventory.get("held")
	var letter: Variant = held.get(other)
	var writing := false
	if is_instance_valid(letter):
		var sheet_root := (letter as Node).get_node_or_null("LetterSheet") as Node3D
		var paper: Node = get_tree().get_first_node_in_group("letter_paper")
		if sheet_root != null and paper != null and over(sheet_root, tip()):
			writing = bool(paper.call("dictate_tick", str(sheet_root.call("letter_id")), letter))
	_show_glint(writing)
	return writing

func _show_glint(on_: bool) -> void:
	if not on_:
		if is_instance_valid(_glint): _glint.hide()
		return
	if not is_instance_valid(_glint):
		_glint = Sprite3D.new(); _glint.name = "InkGlint"
		var shine := GradientTexture2D.new()
		shine.width = GLINT_PX; shine.height = GLINT_PX
		shine.fill = GradientTexture2D.FILL_RADIAL
		shine.fill_from = Vector2(0.5, 0.5); shine.fill_to = Vector2(1.0, 0.5)
		var fade := Gradient.new()
		fade.set_color(0, Color(0.55, 0.75, 1.0, 1.0)); fade.set_color(1, Color(0.2, 0.3, 0.9, 0.0))
		shine.gradient = fade
		_glint.texture = shine
		_glint.pixel_size = 0.012 / GLINT_PX
		_glint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_glint.shaded = false
		_glint.no_depth_test = true
		_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_glint)
	_glint.global_position = tip()
	_glint.show()
