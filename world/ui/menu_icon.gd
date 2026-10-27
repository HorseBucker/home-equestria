extends Control
## A small drawn icon for the menus (world/ui/menu_style.gd): strokes on a 24-unit grid, scaled to
## the control, so it stays crisp on a headset panel and on any screen. `kind` picks the picture;
## the folder pictures (apple, cloud, cupcake…) also mark the player's worlds in the saves browser.
const KINDS := ["sparkle", "star", "star_filled", "heart", "gear", "chat", "quill", "note", "sun", "keyboard", "map",
	"headset", "music", "globe", "access", "book", "folder", "tag", "trash", "archive", "play", "save", "pencil",
	"plus", "close", "back", "forward", "check", "lifebuoy", "home", "moon", "search", "clock", "info", "refresh",
	"cloud", "apple", "flower", "gem", "butterfly", "cupcake", "horseshoe", "tree", "palette", "dots", "pony", "image", "sort"]
## Pictures a world folder can wear (the saves browser's folder picker).
const FOLDER_KINDS := ["heart", "star_filled", "apple", "cloud", "moon", "sun", "flower", "gem", "butterfly", "cupcake", "horseshoe", "tree"]

@export var kind := "sparkle":
	set(value): kind = value; queue_redraw()
@export var color := Color.WHITE:
	set(value): color = value; queue_redraw()
## Stroke width on the 24-unit grid.
@export var stroke := 2.0:
	set(value): stroke = value; queue_redraw()


static func make(icon_kind: String, icon_size := 24.0, icon_color := Color.WHITE) -> Control:
	var node: Control = (load("res://world/ui/menu_icon.gd") as GDScript).new()
	node.kind = icon_kind; node.color = icon_color
	node.custom_minimum_size = Vector2(icon_size, icon_size)
	node.size = node.custom_minimum_size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Draws `kind` into `rect` of a canvas item: a control's own (draw) or a texture's (button icons).
static func paint(item: RID, rect: Rect2, kind: String, color: Color, stroke := 2.0) -> void:
	var pen := Pen.new(item, rect, color, stroke)
	match kind:
		"sparkle":
			pen.fill(pen.star4(Vector2(11, 13), 8.5, 2.3))
			pen.fill(pen.star4(Vector2(19.5, 4.5), 3.4, 1.0))
		"star", "star_filled":
			var points := pen.star5(Vector2(12, 12.6), 9.6, 4.2)
			if kind == "star_filled": pen.fill(points)
			else: pen.line(points, true)
		"heart":
			var heart := PackedVector2Array()
			for i in 48:
				var t := TAU * i / 48.0
				heart.append(Vector2(12, 12.4) + Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * 0.55)
			pen.fill(heart)
		"gear":
			pen.ring(Vector2(12, 12), 6.2)
			pen.ring(Vector2(12, 12), 2.4)
			for i in 8:
				var a := TAU * i / 8.0
				pen.seg(Vector2(12, 12) + Vector2.from_angle(a) * 6.6, Vector2(12, 12) + Vector2.from_angle(a) * 9.6, pen.stroke * 1.35)
		"chat":
			pen.line(pen.round_rect(Rect2(3, 4, 18, 12.5), 4.0), true)
			pen.line(PackedVector2Array([Vector2(8, 16.5), Vector2(6.5, 21), Vector2(12.5, 16.5)]))
			pen.fill(pen.star4(Vector2(12, 10.2), 3.6, 1.0))
		"quill":
			pen.line(PackedVector2Array([Vector2(20.5, 3), Vector2(14, 4.5), Vector2(9, 9), Vector2(6.5, 14.5), Vector2(6, 18),
				Vector2(9.5, 17.5), Vector2(14, 14.5), Vector2(18, 9.5), Vector2(20.5, 3)]), true)
			pen.seg(Vector2(3.5, 21), Vector2(13, 11))
		"note":
			pen.line(PackedVector2Array([Vector2(5, 3), Vector2(15, 3), Vector2(19, 7), Vector2(19, 21), Vector2(5, 21)]), true)
			pen.line(PackedVector2Array([Vector2(15, 3), Vector2(15, 7), Vector2(19, 7)]))
			for y in [11.0, 14.5, 18.0]: pen.seg(Vector2(8.5, y), Vector2(15.5, y))
		"sun":
			pen.ring(Vector2(12, 12), 4.2)
			for i in 8:
				var a := TAU * i / 8.0
				pen.seg(Vector2(12, 12) + Vector2.from_angle(a) * 7.2, Vector2(12, 12) + Vector2.from_angle(a) * 9.8)
		"keyboard":
			pen.line(pen.round_rect(Rect2(2, 6, 20, 12), 3.0), true)
			for p: Vector2 in [Vector2(6, 10), Vector2(10, 10), Vector2(14, 10), Vector2(18, 10), Vector2(6, 14), Vector2(18, 14)]: pen.dot(p, 1.05)
			pen.seg(Vector2(9.5, 14), Vector2(14.5, 14))
		"map":
			pen.line(PackedVector2Array([Vector2(3, 6), Vector2(9, 3.5), Vector2(15, 6), Vector2(21, 3.5), Vector2(21, 18), Vector2(15, 20.5), Vector2(9, 18), Vector2(3, 20.5)]), true)
			pen.seg(Vector2(9, 3.5), Vector2(9, 18)); pen.seg(Vector2(15, 6), Vector2(15, 20.5))
		"headset":
			pen.line(PackedVector2Array([Vector2(3, 8), Vector2(21, 8), Vector2(21, 16.5), Vector2(15.5, 16.5), Vector2(13.5, 13.5),
				Vector2(10.5, 13.5), Vector2(8.5, 16.5), Vector2(3, 16.5)]), true)
			pen.seg(Vector2(3, 11), Vector2(1, 11)); pen.seg(Vector2(21, 11), Vector2(23, 11))
		"music":
			pen.seg(Vector2(9, 18), Vector2(9, 5.5)); pen.seg(Vector2(19, 16), Vector2(19, 3.5))
			pen.seg(Vector2(9, 5.5), Vector2(19, 3.5), pen.stroke * 1.4)
			pen.dot(Vector2(6.6, 18), 2.7); pen.dot(Vector2(16.6, 16), 2.7)
		"globe":
			pen.ring(Vector2(12, 12), 9.2)
			pen.line(pen.ellipse(Vector2(12, 12), Vector2(4.2, 9.2)), true)
			pen.seg(Vector2(3, 12), Vector2(21, 12))
		"access":
			pen.dot(Vector2(12, 4.6), 2.2)
			pen.seg(Vector2(4.5, 8.6), Vector2(19.5, 8.6)); pen.seg(Vector2(12, 8.6), Vector2(12, 14.5))
			pen.seg(Vector2(12, 14.5), Vector2(8, 21)); pen.seg(Vector2(12, 14.5), Vector2(16, 21))
		"book":
			pen.line(PackedVector2Array([Vector2(12, 6.5), Vector2(8, 4.6), Vector2(2.5, 4.6), Vector2(2.5, 18.5), Vector2(8, 18.5), Vector2(12, 20.5)]))
			pen.line(PackedVector2Array([Vector2(12, 6.5), Vector2(16, 4.6), Vector2(21.5, 4.6), Vector2(21.5, 18.5), Vector2(16, 18.5), Vector2(12, 20.5)]))
			pen.seg(Vector2(12, 6.5), Vector2(12, 20.5))
		"folder":
			pen.line(PackedVector2Array([Vector2(2.5, 5.5), Vector2(9, 5.5), Vector2(11, 8), Vector2(21.5, 8), Vector2(21.5, 19.5), Vector2(2.5, 19.5)]), true)
		"tag":
			pen.line(PackedVector2Array([Vector2(3, 3.5), Vector2(11.5, 3.5), Vector2(20.5, 12.5), Vector2(12.5, 20.5), Vector2(3, 11)]), true)
			pen.dot(Vector2(7.6, 8.1), 1.6)
		"trash":
			pen.seg(Vector2(3.5, 6), Vector2(20.5, 6))
			pen.line(PackedVector2Array([Vector2(9, 6), Vector2(9, 3.2), Vector2(15, 3.2), Vector2(15, 6)]))
			pen.line(PackedVector2Array([Vector2(5.5, 6), Vector2(7, 21), Vector2(17, 21), Vector2(18.5, 6)]))
			pen.seg(Vector2(10, 10), Vector2(10, 17)); pen.seg(Vector2(14, 10), Vector2(14, 17))
		"archive":
			pen.line(pen.round_rect(Rect2(2.5, 3.5, 19, 5), 1.5), true)
			pen.line(PackedVector2Array([Vector2(4.5, 8.5), Vector2(4.5, 20.5), Vector2(19.5, 20.5), Vector2(19.5, 8.5)]))
			pen.seg(Vector2(10, 12.5), Vector2(14, 12.5))
		"play":
			pen.fill(PackedVector2Array([Vector2(7, 4.5), Vector2(19.5, 12), Vector2(7, 19.5)]))
		"save":
			pen.line(PackedVector2Array([Vector2(4, 3.5), Vector2(16, 3.5), Vector2(20.5, 8), Vector2(20.5, 20.5), Vector2(4, 20.5)]), true)
			pen.line(PackedVector2Array([Vector2(8, 3.5), Vector2(8, 8.5), Vector2(15, 8.5), Vector2(15, 3.5)]))
			pen.line(PackedVector2Array([Vector2(7.5, 20.5), Vector2(7.5, 13.5), Vector2(17, 13.5), Vector2(17, 20.5)]))
		"pencil":
			pen.line(PackedVector2Array([Vector2(15.5, 3.5), Vector2(20.5, 8.5), Vector2(9, 20), Vector2(3.5, 20.5), Vector2(4, 15)]), true)
			pen.seg(Vector2(13, 6), Vector2(18, 11))
		"plus":
			pen.seg(Vector2(12, 4.5), Vector2(12, 19.5)); pen.seg(Vector2(4.5, 12), Vector2(19.5, 12))
		"close":
			pen.seg(Vector2(6, 6), Vector2(18, 18)); pen.seg(Vector2(18, 6), Vector2(6, 18))
		"back":
			pen.line(PackedVector2Array([Vector2(15, 4.5), Vector2(7.5, 12), Vector2(15, 19.5)]))
		"forward":
			pen.line(PackedVector2Array([Vector2(9, 4.5), Vector2(16.5, 12), Vector2(9, 19.5)]))
		"check":
			pen.line(PackedVector2Array([Vector2(4.5, 12.5), Vector2(9.5, 17.5), Vector2(19.5, 6.5)]))
		"lifebuoy":
			pen.ring(Vector2(12, 12), 9.2); pen.ring(Vector2(12, 12), 4.0)
			for i in 4:
				var a := TAU * (i + 0.5) / 4.0
				pen.seg(Vector2(12, 12) + Vector2.from_angle(a) * 4.0, Vector2(12, 12) + Vector2.from_angle(a) * 9.2)
		"home":
			pen.line(PackedVector2Array([Vector2(2.5, 11.5), Vector2(12, 3.5), Vector2(21.5, 11.5)]))
			pen.line(PackedVector2Array([Vector2(5, 9.5), Vector2(5, 20.5), Vector2(19, 20.5), Vector2(19, 9.5)]))
			pen.line(PackedVector2Array([Vector2(10, 20.5), Vector2(10, 14.5), Vector2(14, 14.5), Vector2(14, 20.5)]))
		"moon":
			var crescent := PackedVector2Array()
			for i in 25:
				crescent.append(Vector2(12, 12) + Vector2.from_angle(deg_to_rad(-60.0 - 240.0 * i / 24.0)) * 9.0)
			var tip_a := crescent[0]
			var tip_b := crescent[crescent.size() - 1]
			for i in range(1, 12):
				var t := i / 12.0
				var control := Vector2(9.5, 11.0)
				crescent.append(tip_b.lerp(control, t).lerp(control.lerp(tip_a, t), t))
			pen.fill(crescent)
			pen.fill(pen.star4(Vector2(18.5, 15.5), 2.6, 0.8))
		"search":
			pen.ring(Vector2(10.5, 10.5), 6.5); pen.seg(Vector2(15.3, 15.3), Vector2(20.5, 20.5), pen.stroke * 1.2)
		"clock":
			pen.ring(Vector2(12, 12), 9.2)
			pen.line(PackedVector2Array([Vector2(12, 6.5), Vector2(12, 12), Vector2(15.8, 14.2)]))
		"info":
			pen.ring(Vector2(12, 12), 9.2); pen.dot(Vector2(12, 7.6), 1.3); pen.seg(Vector2(12, 11), Vector2(12, 17))
		"refresh":
			var arc := PackedVector2Array()
			for i in 20: arc.append(Vector2(12, 12) + Vector2.from_angle(deg_to_rad(-50.0 + 280.0 * i / 19.0)) * 7.5)
			pen.line(arc)
			var end := Vector2(12, 12) + Vector2.from_angle(deg_to_rad(-50.0)) * 7.5
			pen.line(PackedVector2Array([end + Vector2(-4.5, -1.0), end, end + Vector2(0.5, -4.6)]))
		"cloud":
			pen.dot(Vector2(8, 14.5), 4.5); pen.dot(Vector2(13.5, 11), 5.6); pen.dot(Vector2(18, 15), 3.6)
			pen.fill(pen.round_rect(Rect2(4, 14.5, 17.5, 5), 2.4))
		"apple":
			pen.dot(Vector2(9.4, 14.2), 5.6); pen.dot(Vector2(14.6, 14.2), 5.6)
			pen.fill(pen.round_rect(Rect2(6.5, 13, 11, 7.5), 3.5))
			pen.seg(Vector2(12, 9), Vector2(12.6, 4.8))
			pen.fill(PackedVector2Array([Vector2(13, 6.2), Vector2(16.5, 3.4), Vector2(19, 4.2), Vector2(15.6, 7)]))
		"flower":
			for i in 5:
				pen.dot(Vector2(12, 11.5) + Vector2.from_angle(TAU * i / 5.0 - PI / 2.0) * 5.0, 3.4)
			pen.seg(Vector2(12, 15), Vector2(12, 22))
			pen.dot(Vector2(12, 11.5), 2.2, Color(pen.color.darkened(0.45), pen.color.a))
		"gem":
			pen.line(PackedVector2Array([Vector2(4.5, 9), Vector2(8, 4.5), Vector2(16, 4.5), Vector2(19.5, 9), Vector2(12, 20.5)]), true)
			pen.seg(Vector2(4.5, 9), Vector2(19.5, 9))
			pen.line(PackedVector2Array([Vector2(9.5, 9), Vector2(12, 20.5), Vector2(14.5, 9)]))
		"butterfly":
			pen.dot(Vector2(7.5, 8.8), 4.2); pen.dot(Vector2(16.5, 8.8), 4.2)
			pen.dot(Vector2(8.5, 15.8), 3.1); pen.dot(Vector2(15.5, 15.8), 3.1)
			pen.seg(Vector2(12, 6), Vector2(12, 19), pen.stroke * 1.5, Color(pen.color.darkened(0.5), pen.color.a))
			pen.seg(Vector2(12, 6), Vector2(10, 2.5), pen.stroke * 0.7); pen.seg(Vector2(12, 6), Vector2(14, 2.5), pen.stroke * 0.7)
		"cupcake":
			pen.fill(PackedVector2Array([Vector2(5.5, 13.5), Vector2(18.5, 13.5), Vector2(16.5, 21), Vector2(7.5, 21)]))
			pen.dot(Vector2(7.6, 12), 3.2); pen.dot(Vector2(12, 10), 4.2); pen.dot(Vector2(16.4, 12), 3.2)
			pen.dot(Vector2(12, 4.6), 1.8)
		"horseshoe":
			var shoe := PackedVector2Array()
			for i in 21: shoe.append(Vector2(12, 11) + Vector2.from_angle(deg_to_rad(150.0 + 240.0 * i / 20.0)) * 7.4)
			pen.line(shoe, false, pen.stroke * 1.9)
			for a: float in [190.0, 230.0, 310.0, 350.0]:
				pen.dot(Vector2(12, 11) + Vector2.from_angle(deg_to_rad(a)) * 7.4, 0.8, Color(pen.color.darkened(0.55), pen.color.a))
		"tree":
			pen.dot(Vector2(12, 8), 5.5); pen.dot(Vector2(7.5, 11.5), 4.2); pen.dot(Vector2(16.5, 11.5), 4.2)
			pen.fill(PackedVector2Array([Vector2(10.6, 13), Vector2(13.4, 13), Vector2(14, 21.5), Vector2(10, 21.5)]))
		"palette":
			# A painter's palette: a round board with a bite out of its edge and a thumb hole.
			var board := PackedVector2Array()
			for i in 29: board.append(Vector2(12, 12) + Vector2.from_angle(deg_to_rad(70.0 + 290.0 * i / 28.0)) * 9.4)
			board.append(Vector2(15.2, 14.6)); board.append(Vector2(15.4, 19.2))
			pen.line(board, true)
			pen.ring(Vector2(9.0, 15.6), 1.7)
			for p: Vector2 in [Vector2(8.2, 8.6), Vector2(13.0, 6.8), Vector2(17.0, 9.4)]: pen.dot(p, 1.9)
		"dots":
			# Round enough to stay three dots at a small size.
			for x in [5.0, 12.0, 19.0]: pen.dot(Vector2(x, 12), 2.5)
		"sort":
			pen.seg(Vector2(4, 7), Vector2(20, 7)); pen.seg(Vector2(4, 12), Vector2(15, 12)); pen.seg(Vector2(4, 17), Vector2(10, 17))
		"pony":
			# A pony head in profile: muzzle to the left, ear up, a little mane.
			pen.line(PackedVector2Array([Vector2(16, 21), Vector2(15, 15.5), Vector2(10, 15.5), Vector2(5.5, 14.5), Vector2(4, 12),
				Vector2(5.5, 9.5), Vector2(9.5, 7.5), Vector2(12, 4.5), Vector2(13.5, 2.5), Vector2(15, 5.5), Vector2(18, 7.5),
				Vector2(20, 12), Vector2(20, 21)]))
			pen.dot(Vector2(11.5, 10.2), 1.1)
		"image":
			pen.line(pen.round_rect(Rect2(2.5, 4.5, 19, 15), 3.0), true)
			pen.line(PackedVector2Array([Vector2(3, 17.5), Vector2(9, 11.5), Vector2(14, 16), Vector2(17, 13.5), Vector2(21, 17)]))
			pen.dot(Vector2(16.5, 8.6), 1.6)
		_:
			pen.ring(Vector2(12, 12), 8.0)




func _draw() -> void:
	paint(get_canvas_item(), Rect2(Vector2.ZERO, size), kind, color, stroke)


## The icon as a Texture2D, for Button.icon: drawn at any size and tinted by the button's icon
## colour for its state (normal, hover, pressed…).
static func texture(icon_kind: String, side := 24) -> Texture2D:
	var key := "%s:%d" % [icon_kind, side]
	if not _textures.has(key):
		var made := Drawn.new(); made.kind = icon_kind; made.side = side
		made.painter = load("res://world/ui/menu_icon.gd")
		_textures[key] = made
	return _textures[key]


static var _textures: Dictionary = {}


class Drawn extends Texture2D:
	var kind := "sparkle"
	var side := 24
	var painter: GDScript
	func _get_width() -> int: return side
	func _get_height() -> int: return side
	func _has_alpha() -> bool: return true
	func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, _transpose: bool) -> void:
		painter.paint(to_canvas_item, Rect2(pos, Vector2(side, side)), kind, modulate)
	func _draw_rect(to_canvas_item: RID, rect: Rect2, _tile: bool, modulate: Color, _transpose: bool) -> void:
		painter.paint(to_canvas_item, rect, kind, modulate)
	func _draw_rect_region(to_canvas_item: RID, rect: Rect2, _src_rect: Rect2, modulate: Color, _transpose: bool, _clip_uv: bool) -> void:
		painter.paint(to_canvas_item, rect, kind, modulate)


## Strokes and fills on the 24-unit grid, scaled into a rect of a canvas item.
class Pen extends RefCounted:
	var item: RID
	var s := 1.0
	var o := Vector2.ZERO
	var color := Color.WHITE
	var stroke := 2.0

	func _init(canvas_item: RID, rect: Rect2, tint: Color, width: float) -> void:
		item = canvas_item; color = tint; stroke = width
		var side := minf(rect.size.x, rect.size.y)
		s = side / 24.0
		o = rect.position + (rect.size - Vector2(side, side)) * 0.5

	func p(point: Vector2) -> Vector2:
		return o + point * s

	func width(units := -1.0) -> float:
		return maxf(1.0, (stroke if units < 0.0 else units) * s)

	func line(points: PackedVector2Array, closed := false, units := -1.0) -> void:
		var out := PackedVector2Array()
		for point in points: out.append(p(point))
		if closed and out.size() > 1: out.append(out[0])
		RenderingServer.canvas_item_add_polyline(item, out, PackedColorArray([color]), width(units), true)
		# Round joins and caps: a dot at every corner hides the polyline's mitred ends.
		for point in out: _disc(point, width(units) * 0.5, color)

	func seg(a: Vector2, b: Vector2, units := -1.0, tint := Color(0, 0, 0, 0)) -> void:
		var used := color if tint.a == 0.0 else tint
		RenderingServer.canvas_item_add_line(item, p(a), p(b), used, width(units), true)
		_disc(p(a), width(units) * 0.5, used)
		_disc(p(b), width(units) * 0.5, used)

	func ring(centre: Vector2, radius: float) -> void:
		var out := PackedVector2Array()
		var steps := clampi(int(radius * s * 1.2), 16, 64)
		for i in steps + 1: out.append(p(centre) + Vector2.from_angle(TAU * i / steps) * radius * s)
		RenderingServer.canvas_item_add_polyline(item, out, PackedColorArray([color]), width(), true)

	func dot(centre: Vector2, radius: float, tint := Color(0, 0, 0, 0)) -> void:
		_disc(p(centre), radius * s, color if tint.a == 0.0 else tint)

	func fill(points: PackedVector2Array) -> void:
		var out := PackedVector2Array()
		for point in points: out.append(p(point))
		if Geometry2D.triangulate_polygon(out).is_empty(): return
		RenderingServer.canvas_item_add_polygon(item, out, PackedColorArray([color]))
		# A hairline in the same colour smooths the polygon's edge.
		var edge := out.duplicate(); edge.append(out[0])
		RenderingServer.canvas_item_add_polyline(item, edge, PackedColorArray([color]), 1.0, true)

	## A filled, antialiased circle: a polygon with a hairline rim.
	func _disc(centre: Vector2, radius: float, tint: Color) -> void:
		var steps := clampi(int(radius * 2.5), 10, 48)
		var out := PackedVector2Array()
		for i in steps: out.append(centre + Vector2.from_angle(TAU * i / steps) * radius)
		RenderingServer.canvas_item_add_polygon(item, out, PackedColorArray([tint]))
		out.append(out[0])
		RenderingServer.canvas_item_add_polyline(item, out, PackedColorArray([tint]), 1.0, true)

	func star4(centre: Vector2, outer: float, inner: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for i in 8:
			var a := -PI / 2.0 + PI * i / 4.0
			points.append(centre + Vector2.from_angle(a) * (outer if i % 2 == 0 else inner))
		return points

	func star5(centre: Vector2, outer: float, inner: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + PI * i / 5.0
			points.append(centre + Vector2.from_angle(a) * (outer if i % 2 == 0 else inner))
		return points

	func round_rect(rect: Rect2, radius: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		var corners := [[rect.position + Vector2(rect.size.x - radius, radius), -PI / 2.0], [rect.end - Vector2(radius, radius), 0.0],
			[rect.position + Vector2(radius, rect.size.y - radius), PI / 2.0], [rect.position + Vector2(radius, radius), PI]]
		for corner: Array in corners:
			for i in 5:
				points.append(corner[0] + Vector2.from_angle(float(corner[1]) + PI / 2.0 * i / 4.0) * radius)
		return points

	func ellipse(centre: Vector2, radii: Vector2) -> PackedVector2Array:
		var points := PackedVector2Array()
		for i in 32: points.append(centre + Vector2(cos(TAU * i / 32.0) * radii.x, sin(TAU * i / 32.0) * radii.y))
		return points
