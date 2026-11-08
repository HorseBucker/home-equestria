extends RefCounted
## The vintage television, generated in code (no model file): a soft-edged wooden console cabinet
## on four tapered, slightly splayed legs, a big 4:3 picture tube behind curved glass with rounded
## corners, and under it a fabric speaker grille, two round knobs (channel and volume, for looks:
## the TV remote works the set) and a small power light. Origin on the floor at the centre of the
## footprint; the front faces local +Z, as furniture placed by home_furnishing.gd turns +Z toward
## the player who places it. The remote is built here too (build_remote).
## Cheap to draw: the cabinet is one mesh with a surface per material, made once and shared by
## every set (the shop's, the one in hand and those placed). Only the screen and the power light
## have materials of their own, which each set drives.

const COMMON := preload("res://mods/watch_party/screen_common.gd")
const WIDTH := 1.12
const DEPTH := 0.6
const LEGS := 0.16
const HEIGHT := 1.1
const FRONT := DEPTH * 0.5
const ROUNDING := 0.045
## The picture: centre and size on the front face (4:3), how far the glass bulges out at its
## middle, and the radius of its corners.
const SCREEN_CENTRE := Vector2(0.0, 0.72)
const SCREEN_SIZE := Vector2(0.84, 0.63)
const SCREEN_Z := FRONT + 0.019
const BULGE := 0.03
const CORNER := 0.07
## The lower panel: grille on the left, the knobs and the power light on the right.
const GRILLE_CENTRE := Vector2(-0.12, 0.28)
const GRILLE_SIZE := Vector2(0.64, 0.12)
const KNOBS := [Vector2(0.29, 0.28), Vector2(0.41, 0.28)]
const LIGHT_POINT := Vector2(0.49, 0.28)
## The remote: how far in from its back end the hand closes (build_remote).
const REMOTE_GRIP := 0.035
## ... and how far left of the hand's centre it sits (playtest 2026-11-03: too far right).
const REMOTE_SIDE := -0.02

## The screen: lit dark glass (highlights from the room's lamps) with the picture added as
## emission, so the tube glows and the glass still reads as glass, also while the set is off.
## Houses have no reflection probes, so the engine's reflections would be the sky and its sun
## shining through the roof (playtest 2026-11-02: dark scenes were unwatchable by day). The glass
## takes no sky or ambient light (ambient_light_disabled) and its own light() skips the sun and
## moon; a faint fixed sheen stands in for the room's reflection.
## crt: scanlines and a faint RGB stripe mask; the tube darkens toward its edge. aperture and
## flash play the power-on line and the power-off dot (tv_set.gd).
const SCREEN_SHADER := """
shader_type spatial;
render_mode cull_back, ambient_light_disabled;
// The sky's reflection would show through the roof (houses have no reflection probes), so the
// glass skips sky light like the room shells (world/buildings/interior_surface.gdshader).
global uniform vec4 interior_light;
// COMMON (screen_common.gd: picture, previous, fade, cursor)
uniform float has_picture = 0.0;
uniform float crt = 1.0;
uniform float lines = 480.0;
uniform float columns = 640.0;
uniform vec2 aperture = vec2(0.5, 0.5);
uniform float flash = 0.0;
uniform float brightness = 1.3;
uniform vec3 glass : source_color = vec3(0.10, 0.135, 0.12);

void fragment() {
	vec2 uv = UV;
	vec3 tube = vec3(0.0);
	if (has_picture > 0.5) {
		vec2 off_centre = abs(uv - 0.5);
		float inside = step(off_centre.x, aperture.x) * step(off_centre.y, aperture.y);
		vec3 c = screen_picture(uv);
		if (crt > 0.5) {
			float scan = 0.7 + 0.3 * pow(sin(uv.y * lines * PI), 2.0);
			float stripe = fract(uv.x * columns);
			vec3 mask = vec3(stripe < 0.333 ? 1.0 : 0.84, (stripe >= 0.333 && stripe < 0.666) ? 1.0 : 0.84, stripe >= 0.666 ? 1.0 : 0.84);
			c *= scan * mask;
		}
		c = with_cursor(c, uv);
		float edge = clamp(1.0 - 0.4 * pow(length((uv - 0.5) * vec2(1.55, 1.65)), 3.0), 0.0, 1.0);
		tube = (c * brightness * edge + vec3(flash)) * inside;
	}
	float glow = clamp(max(max(tube.r, tube.g), tube.b), 0.0, 1.0);
	ALBEDO = glass * (1.0 - 0.85 * glow);
	ROUGHNESS = 0.07;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	// A faint sheen at grazing angles, so the glass reads as glass from the side.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	// A dim room above and behind the viewer, mirrored: lighter toward the top of the glass.
	// Lit by the game's room fill (world/sky_controller.gd), like the walls, so it dims at night.
	vec3 mirrored = reflect(-normalize(VIEW), normalize(NORMAL));
	float room = 0.25 + 0.35 * clamp(mirrored.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 fill = interior_light.rgb * (1.0 - glow);
	EMISSION = tube + fill * (ALBEDO + vec3(0.06 * room) + vec3(0.08) * fresnel);
}

// Lamps light and glint on the glass; the sun and moon never reach a set indoors.
void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
		DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
		vec3 half_way = normalize(VIEW + LIGHT);
		SPECULAR_LIGHT += pow(clamp(dot(NORMAL, half_way), 0.0, 1.0), 160.0) * lit * ATTENUATION * LIGHT_COLOR * 0.5;
	}
}
"""
static var _screen_shader: Shader
static var _cabinet: ArrayMesh
static var _screen: ArrayMesh

## What tv_set.gd needs to know of this set (screen_common.gd).
static func spec(_variant := "") -> Dictionary:
	return {"kind": "crt", "centre": SCREEN_CENTRE, "size": SCREEN_SIZE, "z": SCREEN_Z, "text_z": SCREEN_Z + BULGE + 0.008,
		"speaker": speaker_point(), "picture": Vector2i(640, 480), "page": Vector2i(1024, 768), "glow_z": SCREEN_Z + 0.12, "power": "crt"}

static func bounds(_variant := "") -> AABB:
	return AABB(Vector3(-WIDTH * 0.5, 0, -DEPTH * 0.5), Vector3(WIDTH, HEIGHT, DEPTH))

## Builds the set under `parent`: "Cabinet" (shared mesh), "Screen" (its own material, driven by
## tv_set.gd) and "PowerLight" (likewise).
static func build(parent: Node3D, _variant := "") -> void:
	var cabinet := MeshInstance3D.new(); cabinet.name = "Cabinet"
	cabinet.mesh = _cabinet_mesh()
	parent.add_child(cabinet)
	var screen := MeshInstance3D.new(); screen.name = "Screen"
	screen.mesh = _screen_mesh()
	screen.material_override = screen_material()
	screen.position = Vector3(SCREEN_CENTRE.x, SCREEN_CENTRE.y, SCREEN_Z)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(screen)
	var light := MeshInstance3D.new(); light.name = "PowerLight"
	var lens := SphereMesh.new(); lens.radius = 0.009; lens.height = 0.012; lens.radial_segments = 10; lens.rings = 5
	light.mesh = lens
	light.material_override = power_light_material(false)
	light.position = Vector3(LIGHT_POINT.x, LIGHT_POINT.y, FRONT + 0.004)
	light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(light)

## The part of the set at `local` (a point in the set's own frame): "screen", "front" (anywhere
## else on the front), or "" (the top, sides and back, where E picks the set up to move it).
static func part_at(local: Vector3, _variant := "") -> String:
	if local.z < FRONT - 0.02 or local.z > FRONT + 0.12: return ""
	if absf(local.x) > WIDTH * 0.5 + 0.01 or local.y > HEIGHT - 0.01: return ""
	var face := Vector2(local.x, local.y)
	var half := SCREEN_SIZE * 0.5
	if absf(face.x - SCREEN_CENTRE.x) <= half.x and absf(face.y - SCREEN_CENTRE.y) <= half.y: return "screen"
	return "front"

## Where the speaker sits, in the set's frame.
static func speaker_point() -> Vector3:
	return Vector3(GRILLE_CENTRE.x, GRILLE_CENTRE.y, FRONT + 0.02)

## In front of the glass, for text drawn over the picture (the bulge is deepest at the middle).
static func over_glass(height: float) -> Vector3:
	return Vector3(SCREEN_CENTRE.x, height, SCREEN_Z + BULGE + 0.008)

# --- materials ----------------------------------------------------------------------------------

## A screen's own material (one per set): dark glass until tv_set.gd hands it a picture.
static func screen_material() -> ShaderMaterial:
	if _screen_shader == null:
		_screen_shader = Shader.new()
		_screen_shader.code = SCREEN_SHADER.replace("// COMMON", COMMON.SHADER + "\n// ")
	var material := ShaderMaterial.new()
	material.shader = _screen_shader
	return material

static func power_light_material(on: bool) -> StandardMaterial3D:
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color("ff5a3c") if on else Color("4a1f18")
	lamp.roughness = 0.3
	lamp.emission_enabled = on
	lamp.emission = Color("ff4a2a")
	lamp.emission_energy_multiplier = 2.5
	return lamp

static func _material(colour: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour; material.roughness = roughness; material.metallic = metallic
	return material

## Speaker cloth: a small woven pattern, tiled.
static func _cloth() -> StandardMaterial3D:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	var base := Color("5a4632")
	for y in 16:
		for x in 16:
			var warp := 0.82 + 0.18 * float((x / 2 + y / 4) % 2)
			var weft := 0.82 + 0.18 * float((y / 2 + x / 4) % 2)
			var thread := warp if (x % 4 < 2) == (y % 4 < 2) else weft
			image.set_pixel(x, y, base * thread)
	image.generate_mipmaps()
	var cloth := _material(Color.WHITE, 1.0)
	cloth.albedo_texture = ImageTexture.create_from_image(image)
	cloth.uv1_scale = Vector3(40, 8, 1)
	return cloth

# --- meshes -------------------------------------------------------------------------------------

## The cabinet: wood (body, top, plinth, legs), dark (bezel, feet), cloth (grille) and brass
## (knobs and grille rail), one surface each.
static func _cabinet_mesh() -> ArrayMesh:
	if _cabinet != null: return _cabinet
	var wood := _tool(); var dark := _tool(); var cloth := _tool(); var brass := _tool()
	var body_height := HEIGHT - LEGS - 0.03
	_rounded_box(wood, Vector3(WIDTH, body_height, DEPTH), ROUNDING, Transform3D(Basis.IDENTITY, Vector3(0, LEGS + 0.03 + body_height * 0.5, 0)))
	_rounded_box(wood, Vector3(WIDTH + 0.03, 0.035, DEPTH + 0.03), 0.017, Transform3D(Basis.IDENTITY, Vector3(0, HEIGHT - 0.0175, 0)))
	_rounded_box(dark, Vector3(WIDTH - 0.02, 0.04, DEPTH - 0.02), 0.018, Transform3D(Basis.IDENTITY, Vector3(0, LEGS + 0.02, 0)))
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			# Splayed a little outward; the foot is a dark cap at the bottom.
			var lean := Basis(Vector3(z, 0, -x).normalized(), deg_to_rad(-7.0))
			var top := Vector3(x * (WIDTH * 0.5 - 0.09), LEGS + 0.01, z * (DEPTH * 0.5 - 0.09))
			var leg := Transform3D(lean, top) * Transform3D(Basis.IDENTITY, Vector3(0, -LEGS * 0.5, 0))
			_frustum(wood, 0.03, 0.017, LEGS, leg, 14)
			_frustum(dark, 0.02, 0.022, 0.018, leg * Transform3D(Basis.IDENTITY, Vector3(0, -LEGS * 0.5 + 0.009, 0)), 14)
	# The bezel round the screen.
	_rounded_box(dark, Vector3(SCREEN_SIZE.x + 0.08, SCREEN_SIZE.y + 0.08, 0.03), CORNER * 0.7, Transform3D(Basis.IDENTITY, Vector3(SCREEN_CENTRE.x, SCREEN_CENTRE.y, FRONT + 0.003)))
	# The lower panel: grille in a brass rail, two knobs, the power light's brass collar.
	_rounded_box(cloth, Vector3(GRILLE_SIZE.x, GRILLE_SIZE.y, 0.012), 0.012, Transform3D(Basis.IDENTITY, Vector3(GRILLE_CENTRE.x, GRILLE_CENTRE.y, FRONT + 0.001)))
	_rounded_box(brass, Vector3(GRILLE_SIZE.x + 0.025, GRILLE_SIZE.y + 0.025, 0.006), 0.016, Transform3D(Basis.IDENTITY, Vector3(GRILLE_CENTRE.x, GRILLE_CENTRE.y, FRONT - 0.001)))
	var facing := Basis(Vector3.RIGHT, PI * 0.5)
	for at: Vector2 in KNOBS:
		var knob := Transform3D(facing, Vector3(at.x, at.y, FRONT + 0.016))
		_frustum(dark, 0.04, 0.036, 0.032, knob, 20)
		_frustum(brass, 0.03, 0.026, 0.006, knob * Transform3D(Basis.IDENTITY, Vector3(0, 0.019, 0)), 20)
		# The pointer notch, at "twelve o'clock".
		_rounded_box(brass, Vector3(0.005, 0.004, 0.022), 0.0015, knob * Transform3D(Basis.IDENTITY, Vector3(0, 0.017, -0.022)))
	_frustum(brass, 0.016, 0.016, 0.006, Transform3D(facing, Vector3(LIGHT_POINT.x, LIGHT_POINT.y, FRONT + 0.002)), 16)
	var mesh := ArrayMesh.new()
	for pair: Array in [[wood, _material(Color("7a4e2d"), 0.62)], [dark, _material(Color("2a2420"), 0.55)],
			[cloth, _cloth()], [brass, _material(Color("c9a24a"), 0.32, 0.65)]]:
		var tool: SurfaceTool = pair[0]
		tool.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	_cabinet = mesh
	return mesh

## The screen glass: a grid over the picture with rounded corners, bulging out toward +Z at its
## middle (zero at the rim, so it meets the bezel). UVs are flat across the picture, so the video
## is not bent; only the glass is.
static func _screen_mesh() -> ArrayMesh:
	if _screen != null: return _screen
	var tool := _tool()
	var columns := 20
	var rows := 16
	var half := SCREEN_SIZE * 0.5
	var points: Array = []
	for j in rows + 1:
		var row: Array = []
		for i in columns + 1:
			var p := Vector2(lerpf(-half.x, half.x, float(i) / columns), lerpf(-half.y, half.y, float(j) / rows))
			# Pull the corners in onto a round.
			var inner := Vector2(clampf(p.x, -half.x + CORNER, half.x - CORNER), clampf(p.y, -half.y + CORNER, half.y - CORNER))
			var out := p - inner
			if absf(p.x) > half.x - CORNER and absf(p.y) > half.y - CORNER and out.length() > CORNER: p = inner + out.normalized() * CORNER
			row.append(p)
		points.append(row)
	for j in rows:
		for i in columns:
			var a: Vector2 = points[j][i]
			var b: Vector2 = points[j][i + 1]
			var c: Vector2 = points[j + 1][i + 1]
			var d: Vector2 = points[j + 1][i]
			# Clockwise seen from the front (+Z): Godot's front faces.
			for p: Vector2 in [a, d, c, a, c, b]: _glass_vertex(tool, p, half)
	_screen = tool.commit()
	return _screen

static func _glass_vertex(tool: SurfaceTool, p: Vector2, half: Vector2) -> void:
	var x := p.x / half.x
	var y := p.y / half.y
	var z := BULGE * (1.0 - x * x) * (1.0 - y * y)
	var dz_dx := BULGE * (-2.0 * x / half.x) * (1.0 - y * y)
	var dz_dy := BULGE * (-2.0 * y / half.y) * (1.0 - x * x)
	tool.set_normal(Vector3(-dz_dx, -dz_dy, 1.0).normalized())
	tool.set_uv(Vector2(p.x / SCREEN_SIZE.x + 0.5, 0.5 - p.y / SCREEN_SIZE.y))
	tool.add_vertex(Vector3(p.x, p.y, z))

static func _tool() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool

## A box with rounded edges and corners of `radius` (three steps to each quarter round): each
## face is a grid whose points near the edges are pushed onto the round, the usual
## clamp-to-the-inner-box trick, spaced so the steps are even round the curve.
static func _rounded_box(tool: SurfaceTool, size: Vector3, radius: float, at: Transform3D, steps := 3) -> void:
	var half := size * 0.5
	var r := minf(radius, minf(half.x, minf(half.y, half.z)) * 0.95)
	var inner := half - Vector3.ONE * r
	var marks := []
	for axis in 3:
		var h: float = inner[axis]
		var row := PackedFloat32Array()
		for k in range(steps, 0, -1): row.append(-h - r * tan(deg_to_rad(45.0 * k / steps)))
		row.append(-h); row.append(h)
		for k in range(1, steps + 1): row.append(h + r * tan(deg_to_rad(45.0 * k / steps)))
		marks.append(row)
	for axis in 3:
		for side_sign: float in [-1.0, 1.0]:
			var u: int = (axis + 1) % 3
			var v: int = (axis + 2) % 3
			var us: PackedFloat32Array = marks[u]
			var vs: PackedFloat32Array = marks[v]
			var outward := Vector3.ZERO; outward[axis] = side_sign
			for i in us.size() - 1:
				for j in vs.size() - 1:
					var corners: Array = []
					for step: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
						var p := Vector3.ZERO
						p[axis] = side_sign * (inner[axis] + r)
						p[u] = us[step.x]; p[v] = vs[step.y]
						var core := p.clamp(-inner, inner)
						var normal := (p - core).normalized() if (p - core).length() > 0.000001 else outward
						corners.append([core + normal * r, normal, Vector2((p[u] + half[u]) / size[u], (p[v] + half[v]) / size[v])])
					_quad(tool, corners, outward, at)

## Two triangles, wound clockwise seen from outside (Godot's front faces).
static func _quad(tool: SurfaceTool, corners: Array, outward: Vector3, at: Transform3D) -> void:
	var p0: Vector3 = corners[0][0]
	var p1: Vector3 = corners[1][0]
	var p2: Vector3 = corners[2][0]
	var order := [0, 1, 2, 0, 2, 3]
	if (p1 - p0).cross(p2 - p0).dot(outward) > 0.0: order = [0, 2, 1, 0, 3, 2]
	for index: int in order:
		var corner: Array = corners[index]
		tool.set_normal((at.basis * (corner[1] as Vector3)).normalized())
		tool.set_uv(corner[2])
		tool.add_vertex(at * (corner[0] as Vector3))

## A tapered cylinder along local Y, centred on its middle, with both ends capped.
static func _frustum(tool: SurfaceTool, top: float, bottom: float, height: float, at: Transform3D, sides: int) -> void:
	var half := height * 0.5
	var slope := (bottom - top) / height
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		var side := [[d0 * top + Vector3(0, half, 0), n0, Vector2(float(i) / sides, 0)], [d1 * top + Vector3(0, half, 0), n1, Vector2(float(i + 1) / sides, 0)],
			[d1 * bottom - Vector3(0, half, 0), n1, Vector2(float(i + 1) / sides, 1)], [d0 * bottom - Vector3(0, half, 0), n0, Vector2(float(i) / sides, 1)]]
		_quad(tool, side, (d0 + d1).normalized(), at)
		_triangle(tool, [Vector3(0, half, 0), d1 * top + Vector3(0, half, 0), d0 * top + Vector3(0, half, 0)], Vector3.UP, at)
		_triangle(tool, [Vector3(0, -half, 0), d0 * bottom - Vector3(0, half, 0), d1 * bottom - Vector3(0, half, 0)], Vector3.DOWN, at)

static func _triangle(tool: SurfaceTool, points: Array, normal: Vector3, at: Transform3D) -> void:
	var p0: Vector3 = points[0]
	var p1: Vector3 = points[1]
	var p2: Vector3 = points[2]
	var order := [0, 1, 2]
	if (p1 - p0).cross(p2 - p0).dot(normal) > 0.0: order = [0, 2, 1]
	for index: int in order:
		var p: Vector3 = points[index]
		tool.set_normal((at.basis * normal).normalized())
		tool.set_uv(Vector2(p.x, p.z))
		tool.add_vertex(at * p)

# --- the remote ---------------------------------------------------------------------------------

## The remote: a dark bar with a red power button and four brass buttons, lying with its buttons up
## (+Y) and its front (the end you point) toward -Z. Returns its bounds.
## The hand grips an item at its origin (world/inventory/briefcase_desktop.gd), so the origin sits
## near the back end: the fist closes round the last few centimetres and the rest points ahead,
## instead of the fingers passing through the middle of the bar. Slim enough for a closed hand.
static func build_remote(parent: Node3D) -> AABB:
	var size := Vector3(0.04, 0.019, 0.16)
	var shift := -(size.z * 0.5 - REMOTE_GRIP)
	var side := REMOTE_SIDE
	_box(parent, "RemoteBody", size, Vector3(side, size.y * 0.5, shift), _material(Color("2b2622"), 0.55))
	var red := _material(Color("b8322a"), 0.4)
	var brass := _material(Color("c9a24a"), 0.35, 0.6)
	_box(parent, "RemotePower", Vector3(0.014, 0.005, 0.014), Vector3(side, size.y + 0.0025, shift - 0.055), red)
	for at: Vector2 in [Vector2(0, -0.028), Vector2(-0.011, -0.01), Vector2(0.011, -0.01), Vector2(0, 0.008)]:
		_box(parent, "RemoteButton", Vector3(0.01, 0.005, 0.01), Vector3(side + at.x, size.y + 0.0025, shift + at.y), brass)
	return AABB(Vector3(side - size.x * 0.5, 0, shift - size.z * 0.5), size + Vector3(0, 0.005, 0))

static func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, material: Material) -> void:
	var box := MeshInstance3D.new(); box.name = node_name
	var mesh := BoxMesh.new(); mesh.size = size; mesh.material = material
	box.mesh = mesh; box.position = at
	parent.add_child(box)
