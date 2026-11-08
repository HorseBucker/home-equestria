extends Node3D
## A short notice in front of the headset view (VR): a dark card with a title and some text, kept in
## view as the game's own tutorial card is (world/life/arrival_tutorial.gd _build_panel, pinned with
## world/ui/head_locked_hud.gd). Shown for a while, then faded. Used where the desktop shows a 2D
## card: the welcome (welcome.gd) and the remote's notes (tv_controls.gd).

const FONT := preload("res://world/books/fonts/AtkinsonHyperlegible-Regular.ttf")
const HUD := "res://world/ui/head_locked_hud.gd"
const GOLD := Color("ffd75e")
const FADE_SECONDS := 1.0
## Card size in metres at DISTANCE in front of the eyes, and how far below the middle of the view.
const DISTANCE := 1.15
const WIDTH := 0.94
const DROP := 0.16

var _back: MeshInstance3D
var _material: StandardMaterial3D
var _title: Label3D
var _text: Label3D
var _left := -1.0
var _camera: Camera3D

## Under `camera`, `drop` metres below the middle of the view (a higher card for the welcome).
func setup(camera: Camera3D, drop := DROP) -> void:
	_camera = camera
	name = "WatchPartyVrNotice"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.add_child(self)
	position = Vector3(0, -drop, -DISTANCE)
	_back = MeshInstance3D.new()
	var quad := QuadMesh.new(); quad.size = Vector2(WIDTH, 0.3)
	_material = StandardMaterial3D.new(); _material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; _material.albedo_color = Color(0.08, 0.06, 0.12, 0.86)
	_material.no_depth_test = true; _material.render_priority = 41
	quad.material = _material
	_back.mesh = quad
	_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_back)
	_title = _label(40, GOLD); add_child(_title)
	_text = _label(30, Color(0.95, 0.95, 0.92)); add_child(_text)
	var hud: Script = load(HUD)
	if hud != null: hud.call("attach", camera, self)
	visible = false

func _label(size: int, colour: Color) -> Label3D:
	var label := Label3D.new(); label.pixel_size = 0.001; label.font_size = size; label.font = FONT
	label.outline_size = 2; label.modulate = colour; label.no_depth_test = true; label.render_priority = 42
	label.width = 860.0; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return label

## Shows `text` (under `title`, or none) for `seconds`, then fades it.
func show_text(title: String, text: String, seconds: float) -> void:
	_title.text = title
	_title.visible = not title.is_empty()
	_text.text = text
	# Taller for more text: about 46 characters a line at this size, 0.038 m a line.
	var lines := maxi(1, ceili(text.length() / 46.0))
	var height := 0.06 + lines * 0.038 + (0.055 if not title.is_empty() else 0.0)
	(_back.mesh as QuadMesh).size = Vector2(WIDTH, height)
	var top := height * 0.5 - 0.03
	_title.position = Vector3(-WIDTH * 0.5 + 0.03, top, 0.002)
	_text.position = Vector3(-WIDTH * 0.5 + 0.03, top - (0.055 if not title.is_empty() else 0.0), 0.002)
	_left = seconds + FADE_SECONDS
	_set_alpha(1.0)
	visible = true

func hide_now() -> void:
	_left = -1.0
	visible = false

func _process(delta: float) -> void:
	if _left < 0.0: return
	_left -= delta
	if _left <= 0.0:
		hide_now()
		return
	_set_alpha(clampf(_left / FADE_SECONDS, 0.0, 1.0))

func _set_alpha(alpha: float) -> void:
	_material.albedo_color.a = 0.86 * alpha
	_title.modulate.a = alpha
	_text.modulate.a = alpha
	_title.outline_modulate.a = alpha
	_text.outline_modulate.a = alpha

func _exit_tree() -> void:
	var hud: Script = load(HUD)
	if hud != null and is_instance_valid(_camera): hud.call("detach", _camera, self)
