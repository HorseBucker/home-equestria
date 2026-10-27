extends Control
## The card every menu page stands on (world/ui/menu_style.gd): a twilight-plum rounded panel with
## a pink-lilac-sky rim that drifts slowly round it, a soft glow outside and a few faint stars
## that breathe inside. One shader, no textures. `inset` keeps room for the glow, so the card itself is
## the control's rect shrunk by it. Reduced motion stills the drift and the twinkling.
##
## A SubViewport panel only shows the motion while it redraws (world/ui/spatial_menu_panel.gd
## `tick`); a CanvasLayer card moves on its own.
const SHADER := """
shader_type canvas_item;
uniform vec2 size_px = vec2(900.0, 840.0);
uniform float radius = 34.0;
uniform float inset = 16.0;
uniform vec4 top_color : source_color = vec4(0.196, 0.125, 0.302, 0.985);
uniform vec4 bottom_color : source_color = vec4(0.110, 0.067, 0.184, 0.985);
uniform vec4 rim_a : source_color = vec4(0.965, 0.651, 0.851, 1.0);
uniform vec4 rim_b : source_color = vec4(0.753, 0.435, 0.859, 1.0);
uniform vec4 rim_c : source_color = vec4(0.549, 0.796, 0.949, 1.0);
uniform float rim_width = 2.5;
uniform float glow = 0.4;
uniform float stars = 1.0;
uniform float motion = 1.0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	// The node's modulate (a page or cover fading in or out) arrives in COLOR.
	vec4 tint = COLOR;
	vec2 px = UV * size_px;
	vec2 centre = size_px * 0.5;
	float d = sd_round_box(px - centre, centre - vec2(inset), radius);
	float t = TIME * motion;
	float body = clamp(0.5 - d, 0.0, 1.0);
	float v = clamp((px.y - inset) / max(1.0, size_px.y - 2.0 * inset), 0.0, 1.0);
	vec4 col = mix(top_color, bottom_color, v);
	// Two soft lights drifting in the dusk.
	vec2 a1 = vec2(0.2 + 0.05 * sin(t * 0.13), 0.1 + 0.03 * cos(t * 0.11)) * size_px;
	vec2 a2 = vec2(0.86 + 0.04 * cos(t * 0.09), 0.32 + 0.05 * sin(t * 0.12)) * size_px;
	float b1 = exp(-pow(length(px - a1) / (0.5 * size_px.x), 2.0));
	float b2 = exp(-pow(length(px - a2) / (0.42 * size_px.x), 2.0));
	col.rgb += rim_a.rgb * 0.09 * b1 + rim_c.rgb * 0.06 * b2;
	// A faint sheen along the top.
	col.rgb += vec3(1.0) * 0.045 * (1.0 - smoothstep(0.0, 70.0, px.y - inset));
	// Stars, few and faint, mostly up high: one in about a dozen cells of a grid, each breathing
	// slowly at its own pace, a rare one with a soft glint (dev 2026-10-27: the twinkling was
	// "a bit too distracting").
	vec2 cell = floor(px / 56.0);
	float h = hash(cell);
	if (h > 0.91 && stars > 0.0) {
		vec2 sp = (cell + vec2(0.2) + 0.6 * vec2(hash(cell + 3.1), hash(cell + 7.7))) * 56.0;
		vec2 dd = abs(px - sp);
		float tw = 0.62 + 0.38 * sin(t * (0.22 + h * 0.45) + h * 40.0);
		float star = exp(-dot(dd, dd) / 1.1) + 0.12 * exp(-length(dd) / 2.5);
		if (h > 0.988) star += 0.22 * (exp(-dd.x * 1.4) * exp(-dd.y / 4.0) + exp(-dd.y * 1.4) * exp(-dd.x / 4.0));
		col.rgb += vec3(1.0, 0.94, 0.98) * star * tw * 0.28 * stars * (1.0 - 0.75 * v);
	}
	float ang = atan(px.y - centre.y, px.x - centre.x);
	float k = 0.5 + 0.5 * sin(ang + t * 0.35);
	float k2 = 0.5 + 0.5 * sin(ang * 2.0 - t * 0.21 + 1.3);
	vec3 rim = mix(mix(rim_a.rgb, rim_b.rgb, k), rim_c.rgb, k2 * 0.4);
	float band = clamp(rim_width - abs(d + rim_width * 0.5) + 0.5, 0.0, 1.0);
	float inner = exp(-max(-d, 0.0) / 16.0) * body * 0.16;
	col.rgb = mix(col.rgb + rim * inner, rim, band);
	vec4 inside = vec4(col.rgb, max(col.a, band));
	vec4 outside = vec4(rim, glow * exp(-max(d, 0.0) / 10.0) * step(0.0, d));
	COLOR = mix(outside, inside, max(body, band)) * tint;
}
"""
static var _shader: Shader

@export var radius := 34.0:
	set(value): radius = value; _sync()
@export var inset := 16.0:
	set(value): inset = value; _sync()
@export var stars := true:
	set(value): stars = value; _sync()
## A lighter card (title subpages over the bright world keep the same family).
@export var glow := 0.4:
	set(value): glow = value; _sync()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shader == null:
		_shader = Shader.new(); _shader.code = SHADER
	var mat := ShaderMaterial.new(); mat.shader = _shader
	material = mat


func _ready() -> void:
	resized.connect(_sync)
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.has_signal("changed"): settings.changed.connect(_on_setting)
	_sync()


func _on_setting(key: String) -> void:
	if key == "access/reduced_motion": _sync()


func _sync() -> void:
	var mat := material as ShaderMaterial
	if mat == null: return
	mat.set_shader_parameter("size_px", size)
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("inset", inset)
	mat.set_shader_parameter("glow", glow)
	mat.set_shader_parameter("stars", 1.0 if stars else 0.0)
	mat.set_shader_parameter("motion", 0.0 if is_inside_tree() and preload("res://world/ui/menu_style.gd").still() else 1.0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


## The card's inner rect (inside the glow margin), for laying pages onto it.
func inner_rect() -> Rect2:
	return Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
