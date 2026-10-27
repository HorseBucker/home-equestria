extends Node3D
## World Panel: the map's flat SubViewport → Sprite3D presentation, with actual GUI input.
## Rays intersect the panel mathematically; no extra 3D camera or physics body.
const PIXELS := Vector2i(900, 840)
const PIXEL_SIZE := 0.0014
var viewport: SubViewport
var display: Sprite3D
var content: Control
var _last_pixel := Vector2(-1, -1)
var _pressed := false
## Seconds between redraws while the page moves on its own (the menu card's drift and twinkle,
## world/ui/menu_card.gd); 0 redraws only on change. Hosts turn it on while a card shows;
## Reduced motion keeps it off.
var tick := 0.0
var _tick_left := 0.0
## The page in layout pixels (PIXELS unless a host reshapes it, resize()) and rendered pixels per
## layout pixel. Pixels handed to and from the panel (ray_to_pixel, point_at) are rendered ones.
var pixels := PIXELS
var resolution := 1.0

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = PIXELS
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	content = Control.new()
	content.size = PIXELS
	viewport.add_child(content)
	display = Sprite3D.new()
	display.texture = viewport.get_texture()
	display.pixel_size = PIXEL_SIZE
	display.shaded = false
	display.double_sided = false
	display.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(display)

## Reshapes the page to `layout` pixels at the same metres per pixel, drawn `sharpness` times finer
## (the title's desktop pages widen to the window and fill a big one without going soft).
func resize(layout: Vector2i, sharpness := 1.0) -> void:
	pixels = layout; resolution = sharpness
	viewport.size = Vector2i((Vector2(layout) * sharpness).round())
	preload("res://world/ui/menu_style.gd").sharpen(viewport, sharpness)
	content.scale = Vector2.ONE * sharpness
	content.size = layout
	display.pixel_size = PIXEL_SIZE * float(layout.x) / float(viewport.size.x)
	refresh()

func refresh() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _process(delta: float) -> void:
	if tick <= 0.0 or not visible: return
	_tick_left -= delta
	if _tick_left > 0.0: return
	_tick_left = tick
	if not preload("res://world/ui/menu_style.gd").still(): refresh()

func ray_to_pixel(origin: Vector3, direction: Vector3) -> Vector2:
	var local_origin := to_local(origin)
	var local_direction := global_basis.inverse() * direction
	if local_direction.z >= -0.00001: return Vector2(-1, -1)
	var distance := -local_origin.z / local_direction.z
	if distance < 0.0: return Vector2(-1, -1)
	var point := local_origin + local_direction * distance
	var pixel := Vector2(point.x, -point.y) / display.pixel_size + Vector2(viewport.size) * 0.5
	return pixel if Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(pixel) else Vector2(-1, -1)

func pixel_to_world(pixel: Vector2) -> Vector3:
	var local := (pixel - Vector2(viewport.size) * 0.5) * display.pixel_size
	return to_global(Vector3(local.x, -local.y, 0.005))

func point_at(pixel: Vector2) -> void:
	if pixel.is_equal_approx(_last_pixel): return
	var event := InputEventMouseMotion.new()
	event.position = pixel
	event.global_position = pixel
	event.relative = pixel - _last_pixel
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
	_last_pixel = pixel
	viewport.push_input(event, true)
	refresh()

func press(value: bool) -> void:
	if value and _last_pixel.x < 0: return
	if _pressed == value: return
	_pressed = value
	var event := InputEventMouseButton.new()
	event.position = _last_pixel
	event.global_position = _last_pixel
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = value
	viewport.push_input(event, true)
	refresh()

func send_key(event: InputEventKey) -> void:
	viewport.push_input(event, true)
	refresh()
