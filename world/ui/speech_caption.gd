extends Control
## Pony speech along the bottom of the screen on desktop, when her words are not over her head
## (world/ai/overhead_dialogue.gd fills it). Her name small over her words, written like the words
## above her head: Celestia, her coat colour, a thick black outline (2026-10-27: "the same colors of
## text as when we see the text above their heads and the same police too"). The old caption was a fixed
## 600-pixel label at 34 px that ran off the bottom of the screen and over the hotbar with a long
## line (2026-10-27). This one:
## - sits above whatever is shown along the bottom (Controls in the CLEARANCE group: the hotbar
##   and its hint, the interaction prompt, the flight hint, the chat field), sliding as they come
##   and go;
## - is as wide as her whole line needs, up to MAX_WIDTH, so it does not widen word by word, and
##   the words are laid out from the left so the ones already shown stay put;
## - shows at most `max_lines` lines: while she talks, older lines roll up and fade out at the top;
## - writes her words in the colours overhead_dialogue.gd gives it (`palette`: fill, outline,
##   shadow), outlined to read over a busy background with nothing behind them. So by default
##   there is no card; Settings → Accessibility → Caption background
##   puts one behind them, at its Background opacity (2026-10-27: "make the opaque screen not here
##   by default with a way to toggle and adjust the opacity").
## With `preview` set (the Accessibility page, world/ui/settings_page.gd), it is a row of its own:
## a sample line over a light-to-dark strip, so those settings can be judged as they change.

const STYLE := preload("res://world/ui/menu_style.gd")
## The overhead words' font (project setting dev/theme/custom_font).
const FONT := STYLE.HEADING
## Fonts drawn from their outlines (outlined()), one copy per font.
static var _outlined := {}
const CLEARANCE := "caption_clearance"
const MAX_LINES := 3
## Layout pixels at the game's 1600 x 900 window and 100% subtitle size.
const TEXT_SIZE := 26.0
const NAME_SIZE := 18.0
const MAX_WIDTH := 720.0
const PAD := Vector2(22, 11)
const NAME_GAP := 3.0
const LINE_SPACING := 3.0
## From the window's bottom edge with nothing below the card, and above whatever is.
const SCREEN_MARGIN := 26.0
const GAP := 12.0
## The highest the card's top goes, as a share of the window's height.
const TOP := 0.25
const ACCENT := 3.0
const DEFAULT_OPACITY := 65
## The outline and the shadow's drop as shares of the text size: the outline as thick as the
## overhead words' (14 at 48 px), the drop a little depth under it. The small name's is thinner:
## that much outline fills Celestia's thin capitals in.
const OUTLINE_SHARE := 0.29
const NAME_OUTLINE_SHARE := 0.18
const DROP_SHARE := 0.08
## Per second, for the card's slides, the roll of the lines and the fades.
const EASE := 14.0
const FADE := 7.0
const SAMPLE_SPEAKER := "Twilight Sparkle"
## Her overhead colours (world/characters/mane6/twilight_sparkle.tres coat_fill, light enough as is).
const SAMPLE_PALETTE := {"fill": Color(0.8, 0.611765, 0.87451), "outline": Color.BLACK, "shadow": Color.BLACK}
const SAMPLE := "Oh, there you are! I was just reading about teleportation. Would you like me to show you how it works?"
## The preview's strip: daylight on the left to night on the right, as the world can be behind it.
const PREVIEW_SKY := [Color("cfe9ff"), Color("fff0c8"), Color("f3a2cf"), Color("5b3f7a"), Color("1d1230")]
const PREVIEW_MARGIN := 18.0

var max_lines := MAX_LINES
var preview := false
var _card: Panel
var _name: Label
var _mask: TextureRect
var _gradient: Gradient
var _words: Label
var _name_font: FontVariation
var _sky: GradientTexture1D
var _speaker := ""
var _palette := {}
var _text := ""
var _full := ""
var _showing := false
var _alpha := 0.0
## The card as drawn, easing toward where it belongs; the words' offset in the card, easing
## toward the newest lines; how much the top line fades (0 while every line fits).
var _rect := Rect2()
var _roll := 0.0
var _fade_top := 0.0
var _snap := true
var _scale := 1.0
var _opacity := 0.0
var _bleed := 0.0
var _styled := ""
var _measured := ""
var _need := 0.0


func _init() -> void:
	name = "SpeechCaption"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = Panel.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	_name_font = FontVariation.new()
	_name_font.base_font = outlined(FONT)
	_name = Label.new()
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.add_theme_font_override("font", _name_font)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_card.add_child(_name)
	# The words are drawn through a mask the card's size: what rolls above it fades away.
	_gradient = Gradient.new()
	_gradient.offsets = PackedFloat32Array([0.0, 0.3])
	_gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE])
	var texture := GradientTexture2D.new()
	texture.gradient = _gradient
	texture.width = 4; texture.height = 128
	texture.fill_from = Vector2(0, 0); texture.fill_to = Vector2(0, 1)
	_mask = TextureRect.new()
	_mask.texture = texture
	_mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mask.stretch_mode = TextureRect.STRETCH_SCALE
	_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_mask)
	_words = Label.new()
	_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.add_theme_font_override("font", outlined(FONT))
	_words.add_theme_color_override("font_color", STYLE.CREAM)
	_mask.add_child(_words)
	visible = false
	modulate.a = 0.0
	set_process(false)


## `font` drawn from its outlines at each size: a copy with the distance field off. Celestia is
## imported as a multichannel distance field with an 8-pixel range, and Godot keeps such an outline
## under half the range, far thinner than this caption's or the overhead words' (overhead_dialogue.gd).
static func outlined(font: Font) -> Font:
	var file := font as FontFile
	if file == null or not file.multichannel_signed_distance_field: return font
	if not _outlined.has(file):
		var copy := file.duplicate() as FontFile
		copy.multichannel_signed_distance_field = false
		_outlined[file] = copy
	return _outlined[file]


func _ready() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_signal("changed"):
		settings.changed.connect(_settings_changed)
	_read_settings()
	if preview:
		var sky := Gradient.new()
		sky.colors = PackedColorArray(PREVIEW_SKY)
		sky.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
		_sky = GradientTexture1D.new()
		_sky.gradient = sky
		show_line(SAMPLE_SPEAKER, SAMPLE_PALETTE, SAMPLE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and preview: queue_redraw()


func _draw() -> void:
	if not preview or _sky == null: return
	var points := _rounded(Rect2(Vector2.ZERO, size), 12.0)
	var uvs := PackedVector2Array()
	for point in points: uvs.append(Vector2(point.x / maxf(size.x, 1.0), 0.5))
	draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, _sky)


static func _rounded(rect: Rect2, radius: float) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var corners := [rect.position + Vector2(r, r), Vector2(rect.end.x - r, rect.position.y + r),
		rect.end - Vector2(r, r), Vector2(rect.position.x + r, rect.end.y - r)]
	var points := PackedVector2Array()
	for c in 4:
		for i in 7:
			var angle := PI + (c + i / 6.0) * PI * 0.5
			points.append(corners[c] + Vector2(cos(angle), sin(angle)) * r)
	return points


## Her words so far (`text`) out of her whole line (`full`, which sets the width), in her
## colours (`palette`: fill, outline, shadow; overhead_dialogue.gd gives those of her overhead words).
func show_line(speaker: String, palette: Dictionary, text: String, full := "") -> void:
	if full.is_empty(): full = text
	if _showing and text == _text and speaker == _speaker and full == _full and palette == _palette: return
	# The next words of the same line roll in; anything else starts over in place.
	if not (_showing and speaker == _speaker and full == _full and text.begins_with(_text)): _snap = true
	if _alpha <= 0.01: _rect = Rect2()
	_speaker = speaker; _palette = palette; _text = text; _full = full
	_name.text = speaker.to_upper()
	_name.visible = not speaker.is_empty()
	_words.text = text
	_showing = true
	visible = true
	set_process(true)


## Fades out with the last words.
func hide_line() -> void:
	_showing = false


func _settings_changed(key: String) -> void:
	if key in ["access/subtitle_scale", "access/caption_card", "access/caption_opacity"]: _read_settings()


func _read_settings() -> void:
	var settings := get_node_or_null("/root/Settings")
	var known := settings != null and settings.has_method("get_value")
	var scale: Variant = settings.call("get_value", "access/subtitle_scale") if known else null
	var card: Variant = settings.call("get_value", "access/caption_card") if known else null
	var opacity: Variant = settings.call("get_value", "access/caption_opacity") if known else null
	_scale = clampf(float(scale) / 100.0, 0.5, 3.0) if scale != null else 1.0
	_opacity = clampf(float(opacity if opacity != null else DEFAULT_OPACITY) / 100.0, 0.0, 1.0) if card == true else 0.0
	_styled = ""


func _process(delta: float) -> void:
	if preview and not is_visible_in_tree(): return
	var still := STYLE.still()
	_alpha = move_toward(_alpha, 1.0 if _showing else 0.0, 1.0 if still else delta * FADE)
	if not _showing and _alpha <= 0.0:
		modulate.a = 0.0
		visible = false
		set_process(false)
		return
	modulate.a = _alpha
	_lay_out(delta, still)


func _lay_out(delta: float, still: bool) -> void:
	# The preview is laid out in its row, already scaled with the menu around it.
	var view := size if preview else get_viewport_rect().size
	if preview and custom_minimum_size.y > 0.0:
		# The height its row is getting, so the card is in place on the frame the row grows.
		view.y = custom_minimum_size.y
	var s := _scale if preview else STYLE.window_scale(view) * _scale
	var text_size := roundi(TEXT_SIZE * s)
	var name_size := maxi(12, roundi(NAME_SIZE * s))
	_restyle(s, text_size, name_size)
	var pad := (PAD * s).round()
	# As wide as her whole line on one line, up to the most a line should be or the window allows.
	var most := floorf(minf(MAX_WIDTH * s, view.x - 2.0 * pad.x - 48.0 * s))
	var key := "%s|%s|%d" % [_full, _speaker, text_size]
	if key != _measured:
		_measured = key
		_need = maxf(outlined(FONT).get_string_size(_full, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x,
			_name_font.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x)
	var inner := maxf(1.0, ceilf(minf(_need + 2.0, most)))
	if _words.size.x != inner: _words.size = Vector2(inner, _words.size.y)
	var spacing := float(_words.get_theme_constant("line_spacing"))
	var line := float(_words.get_line_height()) + spacing
	var lines := maxi(1, _words.get_line_count())
	var words_height := lines * line - spacing
	if _words.size.y != words_height: _words.size = Vector2(inner, words_height)
	var name_height := float(_name_font.get_height(name_size)) + NAME_GAP * s if _name.visible else 0.0
	var width := ceilf(inner + pad.x * 2.0)
	var left := (view.x - width) * 0.5
	var bottom := view.y - (PREVIEW_MARGIN if preview else SCREEN_MARGIN) * s
	if preview:
		# The row as tall as the sample needs.
		var tall := ceilf(mini(lines, max_lines) * line - spacing + name_height + pad.y * 2.0 + PREVIEW_MARGIN * s * 2.0)
		if custom_minimum_size.y != tall: custom_minimum_size = Vector2(0.0, tall)
	else:
		# Above the hotbar, the prompt and whatever else is along the bottom under the card.
		for node: Node in get_tree().get_nodes_in_group(CLEARANCE):
			var control := node as Control
			if control == null or not control.is_visible_in_tree(): continue
			if control is Label and (control as Label).text.strip_edges().is_empty(): continue
			var under := control.get_global_rect()
			if under.end.x <= left or under.position.x >= left + width: continue
			bottom = minf(bottom, under.position.y - GAP * s)
	# Never below that edge: big text in a small window shows fewer lines, the card no higher than TOP.
	var room := bottom - (0.0 if preview else view.y * TOP) - name_height - pad.y * 2.0
	var shown := clampi(floori((room + spacing) / line), 1, mini(lines, maxi(1, max_lines)))
	var area := shown * line - spacing
	var card_size := Vector2(width, ceilf(area + name_height + pad.y * 2.0))
	var target := Rect2(Vector2(left, bottom - card_size.y), card_size).abs()
	var roll_to := area - words_height
	var ease := 1.0 if still else 1.0 - exp(-EASE * delta)
	if _rect.size == Vector2.ZERO:
		# Appearing: a short rise into place.
		_rect = target
		if not still: _rect.position.y += 10.0 * s
		_snap = true
	if _snap:
		_roll = roll_to
		_snap = false
	_rect.position = _rect.position.lerp(target.position, ease)
	_rect.size = _rect.size.lerp(target.size, ease)
	if absf(_rect.size.x - target.size.x) < 0.5 and absf(_rect.size.y - target.size.y) < 0.5: _rect.size = target.size
	_roll = lerpf(_roll, roll_to, ease)
	if absf(_roll - roll_to) < 0.5: _roll = roll_to
	_card.position = _rect.position.round()
	_card.size = _rect.size.round()
	_name.position = pad
	_name.size = Vector2(_card.size.x - pad.x * 2.0, float(_name_font.get_height(name_size)))
	# The mask reaches past the words by their outline and shadow, so neither is cut off.
	var mask_height := maxf(0.0, _card.size.y - name_height - pad.y * 2.0)
	_mask.position = Vector2(pad.x - _bleed, pad.y + name_height - _bleed)
	_mask.size = Vector2(_card.size.x - pad.x * 2.0, mask_height) + Vector2.ONE * _bleed * 2.0
	_words.position = Vector2(_bleed, roundf(_roll) + _bleed)
	# The top line fades while older lines are rolled away above it.
	_fade_top = lerpf(_fade_top, 1.0 if lines > shown else 0.0, ease)
	var reach := clampf((line * 0.75 + _bleed) / maxf(_mask.size.y, 1.0), 0.02, 0.6)
	var top := Color(1, 1, 1, 1.0 - _fade_top)
	if not is_equal_approx(_gradient.get_offset(1), reach) or not _gradient.get_color(0).is_equal_approx(top):
		_gradient.set_offset(1, reach)
		_gradient.set_color(0, top)


func _restyle(s: float, text_size: int, name_size: int) -> void:
	var fill: Color = _palette.get("fill", STYLE.CREAM)
	var edge: Color = _palette.get("outline", Color.BLACK)
	var shade: Color = _palette.get("shadow", Color.BLACK)
	var key := "%.2f|%s|%s|%s|%d|%d" % [_opacity, fill.to_html(), edge.to_html(), shade.to_html(), text_size, name_size]
	if key == _styled: return
	_styled = key
	var card := StyleBoxEmpty.new() as StyleBox
	if _opacity > 0.0:
		# Her outline colour down the left edge, lifted a little to show on the dark card.
		var flat := STYLE.box(Color(STYLE.INK, _opacity), Color(edge.lerp(fill, 0.35), minf(1.0, _opacity * 2.5)), 0, roundi(12 * s), 0, 0)
		flat.border_width_left = maxi(2, roundi(ACCENT * s))
		flat.shadow_color = Color(0, 0, 0, 0.25 * _opacity)
		flat.shadow_size = roundi(12 * s)
		flat.shadow_offset = Vector2(0, roundi(3 * s))
		card = flat
	_card.add_theme_stylebox_override("panel", card)
	# As the sheet draws them: the fill, its outline, and the outlined shape again behind, dropped
	# down and right.
	var outline := 0
	var drop := 0
	for label: Label in [_words, _name]:
		var size := float(text_size if label == _words else name_size)
		outline = maxi(2, roundi(size * (OUTLINE_SHARE if label == _words else NAME_OUTLINE_SHARE)))
		drop = maxi(1, roundi(size * DROP_SHARE))
		label.add_theme_color_override("font_color", fill)
		label.add_theme_constant_override("outline_size", outline)
		label.add_theme_color_override("font_outline_color", edge)
		label.add_theme_constant_override("shadow_outline_size", outline)
		label.add_theme_constant_override("shadow_offset_x", drop)
		label.add_theme_constant_override("shadow_offset_y", drop)
		label.add_theme_color_override("font_shadow_color", shade)
		if label == _words: _bleed = float(outline + drop + 1)
	_words.add_theme_font_size_override("font_size", text_size)
	_words.add_theme_constant_override("line_spacing", roundi(LINE_SPACING * s))
	_name_font.spacing_glyph = maxi(1, roundi(1.2 * s))
	_name.add_theme_font_size_override("font_size", name_size)
	_measured = ""
