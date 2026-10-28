extends Node
## Session-only experiments owned by SkyController. No saves, geometry edits or bakes.
const ROOM_SHADERS := [preload("res://world/interiors/wallpaper_surface.gdshader"),
	preload("res://world/buildings/interior_surface.gdshader")]
const VIEW := preload("res://world/player_view.gd")
const ENV_PROPERTIES := ["sdfgi_enabled", "ssil_enabled", "ssao_enabled", "glow_enabled",
	"volumetric_fog_enabled", "ssao_radius", "ssao_intensity", "ssil_radius",
	"ssil_intensity", "glow_intensity", "glow_bloom", "volumetric_fog_length"]
var mode := "baseline"
var room: Node3D
var _original: Dictionary = {}
var _materials: Dictionary = {}
var _geometry: Dictionary = {}
var _lit_shaders: Dictionary = {}
var _rig: Node3D
var _probe: ReflectionProbe
var _fills: Array[OmniLight3D] = []
var _room_timer := 0.0

func _ready() -> void:
	set_process(false)

func select(next: String) -> void:
	if not Quality.LIGHTING_TESTS.has(next): return
	var env: Environment = get_parent().environment
	_clear_room()
	for property: String in _original: env.set(property, _original[property])
	_original.clear()
	mode = next
	if mode != "baseline":
		for property: String in ENV_PROPERTIES: _original[property] = env.get(property)
	set_process(mode != "baseline")
	_refresh_room()
	print("[lighting] ", mode)

## Only called by the sky's quality writer, never every frame. Avoid disabling and
## reallocating SDFGI each time the sun advances.
func apply_settings(env: Environment) -> void:
	if mode == "baseline": return
	var config: Dictionary = Quality.LIGHTING_TESTS[mode]
	env.sdfgi_enabled = bool(config.get("sdfgi", false))
	env.ssil_enabled = bool(config.get("ssil", false))
	env.ssao_enabled = bool(config.get("ssao", false))
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.0
	env.ssil_radius = 2.0
	env.ssil_intensity = 1.0
	if config.get("atmosphere", false):
		env.glow_enabled = true
		env.glow_intensity = 0.3
		env.glow_bloom = 0.04
		env.volumetric_fog_enabled = true
		env.volumetric_fog_length = 48.0

## SkyController has just calculated fresh time/weather values. Multipliers never
## compound, and the baseline is regenerated from current weather, not a stale snapshot.
func apply_time(env: Environment, daylight: float) -> void:
	if mode == "baseline": return
	if mode != "reflection": env.ambient_light_energy *= 0.45
	if Quality.LIGHTING_TESTS[mode].get("atmosphere", false):
		env.volumetric_fog_density = minf(env.volumetric_fog_density, 0.008)
	for light: OmniLight3D in _fills:
		light.light_color = Color(0.72, 0.80, 1.0).lerp(env.ambient_light_color, 0.55)
		light.light_energy = lerpf(0.025, 0.65, daylight) * lerpf(1.0, 0.72, float(get_parent().weather_overcast))

func _process(delta: float) -> void:
	_room_timer -= delta
	if _room_timer > 0.0: return
	_room_timer = 1.0
	_refresh_room()

func _refresh_room() -> void:
	if mode == "baseline": return
	var camera := VIEW.camera(self)
	var target: Node3D
	if camera != null:
		for home: Node3D in get_tree().get_nodes_in_group("house_interiors"):
			if not home.get_parent().is_queued_for_deletion() and home.has_method("contains") and home.contains(camera.global_position, true):
				target = home
				break
	if is_instance_valid(room) and room == target: return
	if target == null:
		_clear_room()
		return
	_clear_room()
	room = target
	if room == null: return
	_prepare_room()
	apply_time_lights()

func apply_time_lights() -> void:
	# Reuse the sky writer after room creation, including a newly streamed interior.
	get_parent().call("_apply_time")

func _prepare_room() -> void:
	var config: Dictionary = Quality.LIGHTING_TESTS[mode]
	# Both wall finishes and the older floor/ceiling pass bypass indirect light.
	# Preserve their UV/discard/texture rules; replace only lighting behavior.
	for original: Shader in ROOM_SHADERS:
		if not _lit_shaders.has(original):
			var shader := Shader.new()
			shader.code = original.code.replace(
				", ambient_light_disabled", "").replace("EMISSION = ALBEDO * interior_light.rgb;", "EMISSION = vec3(0.0);")
			_lit_shaders[original] = shader
	for mesh: MeshInstance3D in room.get_parent().find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var shell := false
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material == null: continue
			if _lit_shaders.has(material.shader):
				_materials[material] = material.shader
				material.shader = _lit_shaders[material.shader]
			if _materials.has(material): shell = true
		if config.get("sdfgi", false) and shell:
			_geometry[mesh] = mesh.gi_mode
			mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	if not config.get("fill", false) and not config.get("probe", false): return
	var floors: Array = room.get("floors")
	if floors.is_empty(): return
	var floor_rect: Rect2 = floors[0]
	var floor_height: float = room.get("floor_y")
	var scale_y := room.global_basis.y.length()
	var local_bounds := AABB(Vector3(floor_rect.position.x, floor_height, floor_rect.position.y),
		Vector3(floor_rect.size.x, 3.6 / maxf(scale_y, 0.001), floor_rect.size.y))
	var bounds: AABB = room.global_transform * local_bounds
	_rig = Node3D.new()
	_rig.name = "DebugRoomLighting"
	add_child(_rig)
	if config.get("fill", false):
		for side: float in [-1.0, 1.0]:
			var mid := floor_rect.get_center()
			var at := Vector3(mid.x + side * floor_rect.size.x * 0.3, floor_height + 1.9 / scale_y, mid.y)
			var light := OmniLight3D.new()
			_rig.add_child(light)
			light.global_position = room.to_global(at)
			light.omni_range = clampf(maxf(bounds.size.x, bounds.size.z) * 0.7, 2.0, 6.0)
			light.omni_attenuation = 1.5
			light.shadow_enabled = true
			light.light_bake_mode = Light3D.BAKE_DISABLED
			_fills.append(light)
	if config.get("probe", false):
		_probe = ReflectionProbe.new()
		_probe.size = bounds.size
		_probe.interior = true
		_probe.box_projection = true
		_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		_probe.enable_shadows = true
		_probe.update_mode = ReflectionProbe.UPDATE_ONCE
		_rig.add_child(_probe)
		_probe.global_position = bounds.get_center()

func refresh_room() -> void:
	_clear_room()
	_refresh_room()

func _clear_room() -> void:
	for material: ShaderMaterial in _materials: material.shader = _materials[material]
	_materials.clear()
	for mesh in _geometry:
		if is_instance_valid(mesh): mesh.gi_mode = _geometry[mesh]
	_geometry.clear()
	if is_instance_valid(_rig):
		_rig.visible = false
		_rig.queue_free()
	_rig = null
	_probe = null
	_fills.clear()
	room = null

func _exit_tree() -> void:
	_clear_room()
