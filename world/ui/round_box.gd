extends StyleBox
## A StyleBoxFlat drawn with its corner radii capped at half its drawn size less a pixel. Godot
## clamps larger radii (pills and circles ask for 99) until the corners meet exactly, and there the
## border and its anti-aliasing fold over: bright points at the ends of a pill or a badge, even a
## line across a circle (2026-10-27). One pixel under half still looks perfectly round. Made by
## MenuStyle.rounded() (world/ui/menu_style.gd), for the menus' theme and their round overrides.

var flat: StyleBoxFlat
var _radii := PackedInt32Array()


func _init(source: StyleBoxFlat = null) -> void:
	flat = source if source != null else StyleBoxFlat.new()
	_radii = PackedInt32Array([flat.corner_radius_top_left, flat.corner_radius_top_right,
		flat.corner_radius_bottom_right, flat.corner_radius_bottom_left])
	# Its margins as the flat box resolves them (an unset one is the border's width).
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: set_content_margin(side, flat.get_margin(side))


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var room := _get_draw_rect(rect).size
	var most := maxi(0, floori(minf(room.x, room.y) * 0.5) - 1)
	for corner: Corner in [CORNER_TOP_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_RIGHT, CORNER_BOTTOM_LEFT]:
		flat.set_corner_radius(corner, mini(_radii[corner], most))
	flat.draw(to_canvas_item, rect)


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.grow_individual(flat.expand_margin_left, flat.expand_margin_top, flat.expand_margin_right, flat.expand_margin_bottom)
