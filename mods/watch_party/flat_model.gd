extends RefCounted
## The modern flatscreen, a 65-inch 16:9 panel, generated in code like the vintage set
## (tv_model.gd) and driven by the same tv_set.gd. Two variants:
## - "stand": the panel on a slim centre pedestal, on a low media console (so the picture sits at
##   a comfortable height on a house floor). Origin on the floor at the centre of the footprint.
## - "wall": the panel alone on a flat mount. Origin at the bottom middle of its back; the back
##   faces -Z, as home_furnishing.gd hangs wall goods (the framed picture) with +Z into the room.
## A near-invisible bezel (6 mm, a 14 mm chin with a small logo light), a 2.6 cm aluminium-edged
## panel with a deeper electronics box on its back. Matte anti-glare glass: no CRT effects; the
## picture is shown with a soft HDR-style highlight stretch and shoulder (SCREEN_SHADER).

const COMMON := preload("res://mods/watch_party/screen_common.gd")
const BASE := preload("res://mods/watch_party/tv_model.gd")
## 65 inches across: 1.439 x 0.809 m of picture.
const SCREEN_SIZE := Vector2(1.439, 0.809)
const BEZEL := 0.006
const CHIN := 0.014
const PANEL := Vector2(SCREEN_SIZE.x + BEZEL * 2.0, SCREEN_SIZE.y + BEZEL + CHIN)
const PANEL_DEPTH := 0.026
## The box on the back of the panel (electronics, the mount and the pedestal fix to it).
const BACK_BOX := Vector3(0.9, 0.42, 0.034)
## The console under the stand version.
const CONSOLE := Vector3(1.7, 0.4, 0.42)
const CONSOLE_LEGS := 0.07
const PEDESTAL := 0.085
const WALL_GAP := 0.034

## The picture: matte glass, near black when off; the picture as emission. Highlights above
## about 55% brightness are stretched (bright skies and lamps glow like an HDR panel's) and then
## folded back by a soft shoulder, so nothing becomes a flat white blob in the game's bloom. The
## room's own fill light (sky_controller.gd interior_light) sets the exposure: a sunny room gets a
## brighter screen, a dark one a gentler one. Like the vintage glass, no sky or sun on it.
const SCREEN_SHADER := """
shader_type spatial;
render_mode cull_back, ambient_light_disabled;
global uniform vec4 interior_light;
// COMMON (screen_common.gd: picture, previous, fade, cursor)
uniform float has_picture = 0.0;
uniform float level = 0.0;
uniform float brightness = 1.15;
uniform float highlight = 0.7;
uniform vec3 glass : source_color = vec3(0.016, 0.017, 0.02);

void fragment() {
	vec3 panel = vec3(0.0);
	if (has_picture > 0.5) {
		vec3 c = with_cursor(screen_picture(UV), UV);
		float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
		c *= 1.0 + highlight * smoothstep(0.55, 1.0, lum);
		float room = clamp(dot(interior_light.rgb, vec3(0.333)), 0.0, 1.2);
		c *= brightness * mix(0.8, 1.3, room / 1.2);
		vec3 over = max(c - 1.0, 0.0);
		c = min(c, vec3(1.0)) + over / (1.0 + over * 1.6);
		panel = c * level;
	}
	float glow = clamp(max(max(panel.r, panel.g), panel.b), 0.0, 1.0);
	ALBEDO = glass;
	ROUGHNESS = 0.38;
	SPECULAR = 0.35;
	EMISSION = panel + interior_light.rgb * glass * (1.0 - glow);
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
		DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
		vec3 half_way = normalize(VIEW + LIGHT);
		SPECULAR_LIGHT += pow(clamp(dot(NORMAL, half_way), 0.0, 1.0), 40.0) * lit * ATTENUATION * LIGHT_COLOR * 0.12;
	}
}
"""
static var _screen_shader: Shader
static var _bodies: Dictionary = {}

## Where the panel's bottom edge is in the set's frame, and its front face.
static func _panel_bottom(variant: String) -> float:
	return CONSOLE.y + 0.012 + PEDESTAL if variant == "stand" else 0.0

static func _front(variant: String) -> float:
	return 0.0 if variant == "stand" else PANEL_DEPTH + BACK_BOX.z

static func spec(variant := "stand") -> Dictionary:
	var bottom := _panel_bottom(variant)
	var centre := Vector2(0.0, bottom + CHIN + SCREEN_SIZE.y * 0.5)
	var z := _front(variant) + 0.0015
	return {"kind": "flat", "centre": centre, "size": SCREEN_SIZE, "z": z, "text_z": z + 0.004,
		"speaker": Vector3(0.0, bottom + 0.02, z), "picture": Vector2i(1280, 720), "page": Vector2i(1600, 900),
		"glow_z": z + 0.1, "power": "fade"}

static func bounds(variant := "stand") -> AABB:
	if variant == "stand":
		var top := _panel_bottom(variant) + PANEL.y
		return AABB(Vector3(-CONSOLE.x * 0.5, 0, -CONSOLE.z * 0.5), Vector3(CONSOLE.x, top, CONSOLE.z))
	# The mount plate's back is the set's back, WALL_GAP behind the box on the panel.
	return AABB(Vector3(-PANEL.x * 0.5, 0, -WALL_GAP), Vector3(PANEL.x, PANEL.y, WALL_GAP + _front(variant)))

## "Body" (one shared mesh per variant), "Screen" (its own material) and "PowerLight" (the logo
## light under the picture).
static func build(parent: Node3D, variant := "stand") -> void:
	var body := MeshInstance3D.new(); body.name = "Cabinet"
	body.mesh = _body_mesh(variant)
	parent.add_child(body)
	var spec_now := spec(variant)
	var screen := MeshInstance3D.new(); screen.name = "Screen"
	var quad := QuadMesh.new(); quad.size = SCREEN_SIZE
	screen.mesh = quad
	screen.material_override = screen_material()
	var centre: Vector2 = spec_now.centre
	screen.position = Vector3(centre.x, centre.y, float(spec_now.z))
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(screen)
	var light := MeshInstance3D.new(); light.name = "PowerLight"
	var lens := BoxMesh.new(); lens.size = Vector3(0.012, 0.002, 0.002)
	light.mesh = lens
	light.material_override = power_light_material(false)
	light.position = Vector3(0.0, _panel_bottom(variant) + CHIN * 0.5, _front(variant) + 0.001)
	light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(light)

## "screen" on the picture, "front" on the rest of the panel's front, "" elsewhere (the console,
## the back and the edges, where E picks the set up).
static func part_at(local: Vector3, variant := "stand") -> String:
	# The console's front counts as the set's front too: it never picks the set up.
	if variant == "stand" and local.z > CONSOLE.z * 0.5 - 0.03 and absf(local.x) <= CONSOLE.x * 0.5 + 0.01 and local.y <= CONSOLE.y + 0.02: return "front"
	var front := _front(variant)
	if local.z < front - 0.012 or local.z > front + 0.1: return ""
	var bottom := _panel_bottom(variant)
	if absf(local.x) > PANEL.x * 0.5 + 0.005 or local.y < bottom - 0.005 or local.y > bottom + PANEL.y + 0.005: return ""
	var uv := COMMON.uv_at(spec(variant), local)
	return "screen" if COMMON.on_picture(uv) else "front"

static func screen_material() -> ShaderMaterial:
	if _screen_shader == null:
		_screen_shader = Shader.new()
		_screen_shader.code = SCREEN_SHADER.replace("// COMMON", COMMON.SHADER + "\n// ")
	var material := ShaderMaterial.new()
	material.shader = _screen_shader
	material.set_shader_parameter("aspect", SCREEN_SIZE.x / SCREEN_SIZE.y)
	return material

## The small light under the picture: dim white while on, off otherwise.
static func power_light_material(on: bool) -> StandardMaterial3D:
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color("e8ecf2") if on else Color("1a1b1e")
	lamp.roughness = 0.4
	lamp.emission_enabled = on
	lamp.emission = Color("dfe8ff")
	lamp.emission_energy_multiplier = 0.6
	return lamp

# --- meshes -------------------------------------------------------------------------------------

## The panel (black bezel, dark aluminium edge and back) plus, for "stand", the pedestal and the
## console (walnut top and sides, matte black doors, slim black legs).
static func _body_mesh(variant: String) -> ArrayMesh:
	if _bodies.has(variant): return _bodies[variant]
	var bezel := BASE._tool(); var metal := BASE._tool(); var wood := BASE._tool(); var doors := BASE._tool()
	var bottom := _panel_bottom(variant)
	var front := _front(variant)
	var mid_y := bottom + PANEL.y * 0.5
	# The panel: the front frame (bezel) a hair proud of the aluminium shell behind it.
	BASE._rounded_box(bezel, Vector3(PANEL.x, PANEL.y, 0.006), 0.003, Transform3D(Basis.IDENTITY, Vector3(0, mid_y, front - 0.003)), 2)
	BASE._rounded_box(metal, Vector3(PANEL.x - 0.002, PANEL.y - 0.002, PANEL_DEPTH - 0.006), 0.004, Transform3D(Basis.IDENTITY, Vector3(0, mid_y, front - 0.006 - (PANEL_DEPTH - 0.006) * 0.5)), 2)
	var back_z := front - PANEL_DEPTH - BACK_BOX.z * 0.5
	BASE._rounded_box(metal, BACK_BOX, 0.01, Transform3D(Basis.IDENTITY, Vector3(0, bottom + 0.06 + BACK_BOX.y * 0.5, back_z + 0.002)), 2)
	if variant == "stand":
		var top := CONSOLE.y + 0.012
		# The pedestal: a neck from the back box down to a thin oval-ish foot plate.
		BASE._rounded_box(metal, Vector3(0.09, PEDESTAL + 0.07, 0.03), 0.008, Transform3D(Basis.IDENTITY, Vector3(0, top + (PEDESTAL + 0.07) * 0.5, back_z)), 2)
		BASE._rounded_box(metal, Vector3(0.42, 0.012, 0.26), 0.006, Transform3D(Basis.IDENTITY, Vector3(0, top + 0.006, back_z + 0.03)), 2)
		# The console.
		var body_h := CONSOLE.y - CONSOLE_LEGS
		BASE._rounded_box(wood, Vector3(CONSOLE.x, 0.03, CONSOLE.z), 0.006, Transform3D(Basis.IDENTITY, Vector3(0, CONSOLE.y - 0.015 + 0.012, 0)), 2)
		BASE._rounded_box(wood, Vector3(CONSOLE.x - 0.01, body_h - 0.02, CONSOLE.z - 0.03), 0.005, Transform3D(Basis.IDENTITY, Vector3(0, CONSOLE_LEGS + (body_h - 0.02) * 0.5, -0.01)), 2)
		for i in 3:
			var x := (float(i) - 1.0) * (CONSOLE.x - 0.04) / 3.0
			BASE._rounded_box(doors, Vector3((CONSOLE.x - 0.06) / 3.0 - 0.008, body_h - 0.05, 0.016), 0.004, Transform3D(Basis.IDENTITY, Vector3(x, CONSOLE_LEGS + 0.005 + (body_h - 0.05) * 0.5, CONSOLE.z * 0.5 - 0.02)), 2)
		for x: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				BASE._frustum(doors, 0.014, 0.01, CONSOLE_LEGS, Transform3D(Basis.IDENTITY, Vector3(x * (CONSOLE.x * 0.5 - 0.1), CONSOLE_LEGS * 0.5, z * (CONSOLE.z * 0.5 - 0.07))), 10)
	else:
		# The wall plate behind the back box.
		var mount_y := bottom + 0.06 + BACK_BOX.y * 0.5
		BASE._rounded_box(doors, Vector3(0.4, 0.3, 0.012), 0.004, Transform3D(Basis.IDENTITY, Vector3(0, mount_y, -WALL_GAP + 0.006)), 2)
		for x: float in [-0.12, 0.12]:
			BASE._rounded_box(metal, Vector3(0.035, 0.24, WALL_GAP - 0.012), 0.005, Transform3D(Basis.IDENTITY, Vector3(x, mount_y, (-WALL_GAP + 0.012) * 0.5)), 2)
	var mesh := ArrayMesh.new()
	for pair: Array in [[bezel, BASE._material(Color("0d0e10"), 0.45)], [metal, BASE._material(Color("3a3d42"), 0.42, 0.7)],
			[wood, BASE._material(Color("5b3a22"), 0.58)], [doors, BASE._material(Color("1c1c1e"), 0.7)]]:
		var tool: SurfaceTool = pair[0]
		if variant != "stand" and pair[0] == wood: continue
		tool.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	_bodies[variant] = mesh
	return mesh
