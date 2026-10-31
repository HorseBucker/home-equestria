extends Control
## Small flourishes over one menu (world/ui/menu_style.gd): a button lifts a hair under the
## pointer, and pressing one shakes loose a few sparkles. Kept small on purpose (dev 2026-10-27:
## "without it being forced or too much") and skipped entirely with Reduced motion.
##
## Add it as the last child of the menu's root; it finds the buttons under that root (again every
## half second while the menu shows, for pages built later). `redraw` is the host SubViewport
## panel's refresh() (a CanvasLayer needs none).
const STYLE := preload("res://world/ui/menu_style.gd")
const LIFT := 1.025
## A wide button lifts no more than this many pixels across (a full-width row would otherwise
## grow over its neighbours).
const LIFT_PIXELS := 6.0
const LIFE := 0.6
const COLORS := [STYLE.PINK, STYLE.BUTTER, STYLE.SKY, STYLE.MINT, Color.WHITE, STYLE.LILAC]
var redraw := Callable()
var _root: Control
## {"at": Vector2, "velocity": Vector2, "age": float, "size": float, "color": Color, "spin": float}
var _sparks: Array[Dictionary] = []
var _lifted: Dictionary = {}   # Button -> Tween
var _scan_left := 0.0


func attach(menu_root: Control, redraw_callable := Callable()) -> void:
	_root = menu_root; redraw = redraw_callable
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 50
	scan()


## Hooks buttons that appeared since the last look.
func scan() -> void:
	if not is_instance_valid(_root): return
	for node in _root.find_children("*", "BaseButton", true, false): _hook(node)


func _hook(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.has_meta("menu_fx"): return
	button.set_meta("menu_fx", true)
	button.mouse_entered.connect(_lift.bind(button, true))
	button.mouse_exited.connect(_lift.bind(button, false))
	button.pressed.connect(_burst.bind(button))


func _lift(button: BaseButton, up: bool) -> void:
	if not is_instance_valid(button) or button.has_meta("no_lift"): return
	if STYLE.still() or button.disabled and up:
		button.scale = Vector2.ONE; return
	var running: Tween = _lifted.get(button)
	if running != null and running.is_valid(): running.kill()
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween().set_trans(Tween.TRANS_BACK if up else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var lift := minf(LIFT, 1.0 + LIFT_PIXELS / maxf(1.0, button.size.x))
	tween.tween_property(button, "scale", Vector2.ONE * (lift if up else 1.0), 0.16 if up else 0.12)
	tween.parallel().tween_method(func(_v: float) -> void: _redraw(), 0.0, 1.0, 0.16)
	_lifted[button] = tween


## A few sparkles where the pointer pressed (the button's middle for keys and sticks).
func burst_at(at: Vector2, count := 7) -> void:
	if STYLE.still(): return
	set_process(true)
	for i in count:
		var angle := randf() * TAU
		_sparks.append({"at": at, "velocity": Vector2.from_angle(angle) * randf_range(70.0, 170.0) + Vector2(0, -30),
			"age": 0.0, "size": randf_range(4.0, 8.0), "color": COLORS[randi() % COLORS.size()], "spin": randf_range(-4.0, 4.0)})


func _burst(button: BaseButton) -> void:
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.has_meta("no_sparkle"): return
	var rect := Rect2(button.get_global_transform_with_canvas().origin - get_global_transform_with_canvas().origin, button.size * button.scale)
	var mouse := get_local_mouse_position()
	burst_at(mouse if rect.grow(4).has_point(mouse) else rect.get_center(), 6 if button.size.x < 80 else 8)


## Perf 0.1.0: processing follows the menu's visibility (this node is the last child of its root,
## so it shares it) and any sparkles still flying; a hidden menu costs nothing per frame.
func _notification(what: int) -> void:
	if what == NOTIFICATION_READY or what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(is_visible_in_tree() or not _sparks.is_empty())


func _process(delta: float) -> void:
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = 0.5
		if is_instance_valid(_root) and _root.is_visible_in_tree(): scan()
	if _sparks.is_empty():
		if not is_visible_in_tree(): set_process(false)
		return
	for spark in _sparks:
		spark.age += delta
		spark.at += spark.velocity * delta
		spark.velocity *= pow(0.04, delta)
		spark.velocity.y += 60.0 * delta
	_sparks = _sparks.filter(func(spark: Dictionary) -> bool: return spark.age < LIFE)
	queue_redraw(); _redraw()


func _draw() -> void:
	for spark in _sparks:
		var life: float = spark.age / LIFE
		var radius: float = spark.size * (1.0 - life * 0.6)
		var color: Color = spark.color
		color.a = 1.0 - life * life
		var points := PackedVector2Array()
		for i in 8:
			var a: float = -PI / 2.0 + PI * i / 4.0 + spark.spin * spark.age
			points.append(spark.at + Vector2.from_angle(a) * (radius if i % 2 == 0 else radius * 0.3))
		draw_colored_polygon(points, color)


func _redraw() -> void:
	if redraw.is_valid(): redraw.call()
