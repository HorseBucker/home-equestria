extends Control
## A little painted scene for the New game cards (world/ui/title_screen.gd): the Everfree forest
## at dusk, or Golden Oak Library on a bright morning. Drawn from the menu icons
## (world/ui/menu_icon.gd) over a rounded sky, so it needs no image files.
const ICON := preload("res://world/ui/menu_icon.gd")
const STYLE := preload("res://world/ui/menu_style.gd")

@export var scene := "everfree":
	set(value): scene = value; queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var night := scene == "everfree"
	var top := Color("1d2c45") if night else Color("8fd0f5")
	var bottom := Color("3a2556") if night else Color("ffe3f3")
	# The sky: a rounded rect whose corners carry the gradient's colours (linear in height, so the
	# triangles blend it exactly).
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var radius := minf(16.0, size.y * 0.2)
	for corner: Array in [[Vector2(size.x - radius, radius), -PI / 2.0], [size - Vector2(radius, radius), 0.0],
			[Vector2(radius, size.y - radius), PI / 2.0], [Vector2(radius, radius), PI]]:
		for i in 7:
			var point: Vector2 = corner[0] + Vector2.from_angle(float(corner[1]) + PI / 2.0 * i / 6.0) * radius
			points.append(point); colors.append(top.lerp(bottom, point.y / size.y))
	draw_polygon(points, colors)
	var u := size.x / 100.0
	if night:
		ICON.paint(get_canvas_item(), Rect2(Vector2(70, 6) * u, Vector2(22, 22) * u), "moon", STYLE.BUTTER)
		for p: Vector2 in [Vector2(14, 10), Vector2(36, 6), Vector2(52, 16), Vector2(28, 22), Vector2(86, 30)]:
			ICON.paint(get_canvas_item(), Rect2(p * u, Vector2(6, 6) * u), "sparkle", Color(1, 0.95, 1, 0.85))
		for tree: Array in [[Vector2(-4, 24), 40.0, Color("24564c")], [Vector2(60, 20), 44.0, Color("2a6658")],
				[Vector2(22, 30), 36.0, Color("33806b")], [Vector2(78, 34), 30.0, Color("3c8a6f")]]:
			ICON.paint(get_canvas_item(), Rect2(tree[0] * u, Vector2(tree[1], tree[1]) * u), "tree", tree[2])
		for p: Vector2 in [Vector2(20, 48), Vector2(48, 52), Vector2(70, 46), Vector2(40, 40)]:
			draw_circle(p * u, 0.9 * u, Color(STYLE.BUTTER, 0.9), true, -1.0, true)
			draw_circle(p * u, 2.4 * u, Color(STYLE.BUTTER, 0.18), true, -1.0, true)
	else:
		ICON.paint(get_canvas_item(), Rect2(Vector2(6, 5) * u, Vector2(20, 20) * u), "sun", STYLE.BUTTER)
		ICON.paint(get_canvas_item(), Rect2(Vector2(66, 4) * u, Vector2(22, 22) * u), "cloud", Color(1, 1, 1, 0.92))
		ICON.paint(get_canvas_item(), Rect2(Vector2(24, 10) * u, Vector2(52, 52) * u), "tree", Color("74c46d"))
		# Golden Oak's door and round window in the trunk-house.
		var door := StyleBoxFlat.new(); door.bg_color = Color("b0434c"); door.set_corner_radius_all(int(2 * u))
		door.corner_radius_bottom_left = 0; door.corner_radius_bottom_right = 0
		draw_style_box(door, Rect2(Vector2(46.6, 50) * u, Vector2(6.8, 10) * u))
		draw_circle(Vector2(50, 33) * u, 3.2 * u, Color("6fc2f0"), true, -1.0, true)
		draw_circle(Vector2(50, 33) * u, 3.2 * u, Color("8b5a3c"), false, 1.2 * u, true)
		ICON.paint(get_canvas_item(), Rect2(Vector2(74, 44) * u, Vector2(16, 16) * u), "book", STYLE.LILAC, 2.4)
		for p: Vector2 in [Vector2(14, 52), Vector2(84, 30), Vector2(20, 30)]:
			ICON.paint(get_canvas_item(), Rect2(p * u, Vector2(5, 5) * u), "sparkle", Color(1, 1, 1, 0.9))
