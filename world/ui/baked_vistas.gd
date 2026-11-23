extends Node3D
## Offline world captures. No gameplay scene or live scenery is loaded by this node.
## (Ponyville overhaul 2026-11-19: the town square's picture is not remade yet, so it is left out; Settings still
## lists it, and choosing it rolls one of these.)
const VIEWS: Array[String] = ["above_ponyville", "golden_oak", "fluttershy_cottage", "zecora_hut", "sweet_apple_acres"]
const DIRECTORY := "res://world/ui/baked_vistas/"
var view_name := ""
var environment: Environment

var _camera_ref: Camera3D
var _picture: MeshInstance3D
var _picture_aspect := 1.0

func setup(_camera: Camera3D, view: String = "") -> void:
	_camera_ref = _camera
	if view.is_empty():
		var settings := get_node_or_null("/root/Settings")
		view = str(settings.get_value("title/view")) if settings != null else "random"
	view_name = view if view in VIEWS else VIEWS[randi() % VIEWS.size()]
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("263a47")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var path := DIRECTORY.path_join(view_name + ".res")
	if ResourceLoader.exists(path):
		var cubemap := load(path) as Cubemap
		if cubemap != null:
			var shader := Shader.new()
			shader.code = "shader_type sky; uniform samplerCube panorama : source_color, filter_linear_mipmap; void sky() { COLOR = texture(panorama, EYEDIR).rgb; }"
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("panorama", cubemap)
			var sky := Sky.new()
			sky.radiance_size = Sky.RADIANCE_SIZE_32
			sky.process_mode = Sky.PROCESS_MODE_QUALITY
			sky.sky_material = material
			environment.sky = sky
			environment.background_mode = Environment.BG_SKY
	else:
		push_warning("Opening capture missing: " + path)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	_flat_picture()


## On a flat screen, the view's own picture (tools/town_planner/build/qc/capture_vistas.gd, Ponyville overhaul
## 2026-11-19): 3440x1440, shot at the desktop camera's field of view, drawn on a quad far out in front of the title
## camera, behind the menu's own 3D panel (a canvas layer would cover the panel), sized every frame to fill the
## window at any shape (cropped at its sides on narrower screens, top and bottom on wider ones). In a headset the
## cubemap sky stays (it surrounds the player).
const PICTURE_DISTANCE := 6000.0
func _flat_picture() -> void:
	var path := DIRECTORY.path_join(view_name + ".picture")   # JPEG bytes (not imported: read as they are)
	if not is_instance_valid(_camera_ref) or _camera_ref is XRCamera3D or (get_viewport() != null and get_viewport().use_xr) or not FileAccess.file_exists(path): return
	var image := Image.new()
	if image.load_jpg_from_buffer(FileAccess.get_file_as_bytes(path)) != OK: return
	_picture_aspect = float(image.get_width()) / float(image.get_height())
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.disable_fog = true
	material.disable_receive_shadows = true
	_picture = MeshInstance3D.new()
	_picture.name = "FlatPicture"
	_picture.mesh = QuadMesh.new()
	_picture.material_override = material
	_picture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_camera_ref.add_child(_picture)
	_picture.position = Vector3(0, 0, -PICTURE_DISTANCE)
	_fit_picture()


func _process(_delta: float) -> void:
	if is_instance_valid(_picture): _fit_picture()


## Cover the camera's view: its height at that distance, the picture's own shape, widened if the window is wider.
func _fit_picture() -> void:
	var view := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(16, 9)
	var aspect := view.x / maxf(view.y, 1.0)
	var tall := 2.0 * PICTURE_DISTANCE * tan(deg_to_rad(_camera_ref.fov) * 0.5)
	if aspect > _picture_aspect: tall = tall * aspect / _picture_aspect
	(_picture.mesh as QuadMesh).size = Vector2(tall * _picture_aspect, tall)
