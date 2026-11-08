extends Node3D
## The floating VR keyboard (screen_input.gd opens it in front of the player when a text box on a
## page takes the focus, or on B/Y). Keys face local +Z; the laser finds them with ray() and the
## trigger presses them. Shift is one-shot (the next letter is a capital); ⌫ deletes, ↵ is Enter,
## ✕ hides the keyboard.

signal typed(character: String, keycode: int)

const KEY := 0.052
const GAP := 0.006
const ROWS := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "⌫"],
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "↵"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l", "'", "@"],
	["⇧", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/"],
	["✕", "-", "_", ":", "space", "?", "!", "←", "→"],
]
## Width in keys of the wider keys.
const WIDE := {"space": 4.0, "⇧": 1.0}
const SPECIAL := {"⌫": KEY_BACKSPACE, "↵": KEY_ENTER, "✕": KEY_ESCAPE, "←": KEY_LEFT, "→": KEY_RIGHT}

var _keys: Array = []       # [label, Rect2 (local x, y), MeshInstance3D]
var _shift := false
var _hovered := -1
var _plain: StandardMaterial3D
var _lit: StandardMaterial3D
var _size := Vector2.ZERO

func _ready() -> void:
	_plain = _material(Color(0.12, 0.13, 0.16, 0.92))
	_lit = _material(Color(0.32, 0.5, 0.75, 0.95))
	var widest := 0.0
	for row: Array in ROWS:
		var width := 0.0
		for label: String in row: width += float(WIDE.get(label, 1.0)) * (KEY + GAP)
		widest = maxf(widest, width)
	_size = Vector2(widest + GAP, ROWS.size() * (KEY + GAP) + GAP)
	var back := MeshInstance3D.new(); back.name = "Board"
	var board := QuadMesh.new(); board.size = _size + Vector2(0.02, 0.02)
	board.material = _material(Color(0.04, 0.04, 0.06, 0.8))
	back.mesh = board
	back.position = Vector3(0, 0, -0.002)
	add_child(back)
	for r in ROWS.size():
		var row: Array = ROWS[r]
		var width := 0.0
		for label: String in row: width += float(WIDE.get(label, 1.0)) * (KEY + GAP)
		var x := -width * 0.5 + GAP * 0.5
		var y := _size.y * 0.5 - GAP - KEY * 0.5 - r * (KEY + GAP)
		for label: String in row:
			var w := float(WIDE.get(label, 1.0)) * (KEY + GAP) - GAP
			var cap := MeshInstance3D.new()
			var quad := QuadMesh.new(); quad.size = Vector2(w, KEY)
			cap.mesh = quad
			cap.material_override = _plain
			cap.position = Vector3(x + w * 0.5, y, 0)
			add_child(cap)
			var text := Label3D.new()
			text.text = "" if label == "space" else label
			text.font_size = 40; text.pixel_size = 0.0006
			text.position = Vector3(x + w * 0.5, y, 0.002)
			text.no_depth_test = false
			add_child(text)
			_keys.append([label, Rect2(Vector2(x, y - KEY * 0.5), Vector2(w, KEY)), cap, text])
			x += w + GAP

static func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

## Where a ray meets the board: {point, uv (local x, y)} or {} when it misses.
func ray(from: Vector3, direction: Vector3) -> Dictionary:
	var plane := Plane(global_basis.z.normalized(), global_position)
	var hit: Variant = plane.intersects_ray(from, direction)
	if hit == null: return {}
	var point: Vector3 = hit
	var local := to_local(point)
	if absf(local.x) > _size.x * 0.5 + 0.01 or absf(local.y) > _size.y * 0.5 + 0.01: return {}
	return {"point": point, "uv": Vector2(local.x, local.y)}

func _key_at(at: Vector2) -> int:
	for i in _keys.size():
		var rect: Rect2 = _keys[i][1]
		if rect.grow(GAP * 0.5).has_point(at): return i
	return -1

func hover(at: Vector2) -> void:
	var index := _key_at(at) if at.x > -1.0 or at.y > -1.0 else -1
	if index == _hovered: return
	if _hovered >= 0: (_keys[_hovered][2] as MeshInstance3D).material_override = _plain
	_hovered = index
	if _hovered >= 0: (_keys[_hovered][2] as MeshInstance3D).material_override = _lit

func press(at: Vector2) -> void:
	var index := _key_at(at)
	if index < 0: return
	var label: String = _keys[index][0]
	if label == "⇧":
		_shift = not _shift
		_relabel()
		return
	if SPECIAL.has(label):
		typed.emit("", int(SPECIAL[label]))
		return
	var character := " " if label == "space" else label
	if _shift:
		character = character.to_upper()
		_shift = false
		_relabel()
	typed.emit(character, KEY_NONE)

func _relabel() -> void:
	for row: Array in _keys:
		var label: String = row[0]
		if label.length() == 1 and label.to_upper() != label:
			(row[3] as Label3D).text = label.to_upper() if _shift else label
