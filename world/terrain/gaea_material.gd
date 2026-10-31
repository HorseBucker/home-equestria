extends RefCounted
## Terrain3D owns height, clipmap LOD, normals, controls and collision. This optional
## material extension replaces only natural-surface albedo in the authored coverage.
const DATA := "res://world/terrain/gaea/"
const HELPERS := "res://world/terrain/gaea_surface.gdshaderinc"
static var _bank: Resource
static var _array: Texture2DArray
static var _field: ImageTexture
static var _field_image: Image
static var _config: Dictionary
static var _grass_region := Vector4.ZERO
static var _grass_slot := 0
static var _original_grass := false
const SAND_TO_STONE := """	{
		vec3 r_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		if (r_world.y > 160.0 + 40.0 * sin(r_world.x * .006 + sin(r_world.z * .004) * 2.0)) {
			for (int ri = 0; ri < 4; ri++) {
				if (t_id[0][ri] == 8) t_id[0][ri] = 21;
				if (t_id[1][ri] == 8) t_id[1][ri] = 21;
			}
		}
	}
"""
## Rollback switch (perf 0.1.0 GPU pass): near the camera Terrain3D blends the four control
## corners of each pixel, and each corner fetches its albedo+normal (anisotropic) for up to two
## texture ids. Neighbouring corners usually ask for the very same fetch (same id, same detile
## cell, so the same uv and gradients). The fetch is reused when its inputs are bit-identical,
## so it returns exactly what a new fetch would: the image cannot change. Measured on desktop
## Forward+ only (the Quest's mobile GPU keeps the stock shader).
const SAMPLE_REUSE := true
const FETCH_HELPER := """
// perf 0.1.0 (gaea_material.gd SAMPLE_REUSE): reuse an albedo+normal fetch whose inputs (layer,
// uv, gradients) equal one of the last two fetches of this pixel. Same inputs, same texels.
const bool TERRAIN_SAMPLE_REUSE = true;
void terrain_fetch(const vec2 uv, const int id, const vec4 dd, const int slot, out vec4 alb, out vec4 nrm, inout material mat) {
	vec3 key = vec3(uv, float(id));
	if (TERRAIN_SAMPLE_REUSE && all(equal(mat.fetch_key0, key)) && all(equal(mat.fetch_dd0, dd))) {
		alb = mat.fetch_alb0; nrm = mat.fetch_nrm0;
	} else if (TERRAIN_SAMPLE_REUSE && all(equal(mat.fetch_key1, key)) && all(equal(mat.fetch_dd1, dd))) {
		alb = mat.fetch_alb1; nrm = mat.fetch_nrm1;
	} else {
		alb = textureGrad(_texture_array_albedo, vec3(uv, float(id)), dd.xy, dd.zw);
		nrm = textureGrad(_texture_array_normal, vec3(uv, float(id)), dd.xy, dd.zw);
		if (slot == 0) { mat.fetch_key0 = key; mat.fetch_dd0 = dd; mat.fetch_alb0 = alb; mat.fetch_nrm0 = nrm; }
		else { mat.fetch_key1 = key; mat.fetch_dd1 = dd; mat.fetch_alb1 = alb; mat.fetch_nrm1 = nrm; }
	}
}
"""
const FETCH_FIELDS := """	float total_weight;
	vec3 fetch_key0; vec4 fetch_dd0; vec4 fetch_alb0; vec4 fetch_nrm0;
	vec3 fetch_key1; vec4 fetch_dd1; vec4 fetch_alb1; vec4 fetch_nrm1;
};"""
const FETCH_ORIGINAL := """		vec4 alb = textureGrad(_texture_array_albedo, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);
		vec4 nrm = textureGrad(_texture_array_normal, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);"""
const MAT_INIT := "\tmaterial mat = material(vec4(0.0), vec4(0.0), 0., 0., 0.);"
const MAT_INIT_FETCH := "\tmaterial mat = material(vec4(0.0), vec4(0.0), 0., 0., 0., vec3(-1.0), vec4(0.0), vec4(0.0), vec4(0.0), vec3(-1.0), vec4(0.0), vec4(0.0), vec4(0.0));"

## Optional perf rewrites of the generated native shader (rollback switch above).
static func _perf_edits(source: String) -> String:
	var desktop := RenderingServer.get_current_rendering_method() == "forward_plus"
	if SAMPLE_REUSE and desktop and source.count(FETCH_ORIGINAL) == 2 and source.count("\tfloat total_weight;\n};") == 1 \
			and source.count(MAT_INIT) == 1 and source.count("void accumulate_material(") == 1:
		source = source.replace("\tfloat total_weight;\n};", FETCH_FIELDS)
		source = source.replace("void accumulate_material(", FETCH_HELPER + "\nvoid accumulate_material(")
		var first := source.find(FETCH_ORIGINAL)
		source = source.substr(0, first) + "\t\tvec4 alb; vec4 nrm;\n\t\tterrain_fetch(id_uv, id, id_dd, 0, alb, nrm, mat);" + source.substr(first + FETCH_ORIGINAL.length())
		source = source.replace(FETCH_ORIGINAL, "\t\tvec4 alb; vec4 nrm;\n\t\tterrain_fetch(id_uv, id, id_dd, 1, alb, nrm, mat);")
		source = source.replace(MAT_INIT, MAT_INIT_FETCH)
	elif SAMPLE_REUSE and desktop:
		push_warning("Terrain3D shader layout changed: terrain fetch reuse not applied")
	return source

static func load_grass_palette() -> void:
	var selection: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://world/terrain/grass_palette.json"))
	var area:=WorldLayout.footprint(WorldLayout.region(selection.region))
	var center:=area.get_center();var radius:=area.size.length()*.5
	_grass_region=Vector4(center.x,center.y,radius,radius+float(selection.edge_blend_m))
	_grass_slot=int(selection.surface_slot)
	_original_grass=bool(selection.get("original_grass",false))

static func favorite_weight(point: Vector3) -> float:
	if _grass_region.w<=_grass_region.z:return 0.0
	return 1.0-smoothstep(_grass_region.z,_grass_region.w,Vector2(point.x-_grass_region.x,point.z-_grass_region.y).length())

static func apply(terrain: Node) -> void:
	if not FileAccess.file_exists(DATA+"installed.json") or "--gaea-materials-off" in preload("res://world/dev_tools.gd").user_args():return
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DATA+"manifest.json"))
	var material: Object=terrain.material
	# Terrain3D documents generating a complete native shader by enabling an empty
	# override. Preserve that exact installed version's vertex/clipmap implementation.
	material.shader_override_enabled=true
	var native: Shader=material.shader_override
	assert(native!=null,"Terrain3D did not generate its native shader")
	var source: String=native.code
	var marker: String="\tALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;"
	assert(source.count(marker)==1 and source.contains("vec3 w_normal") and source.contains("uvec4 control"),"Terrain3D shader adapter requires review for this version")
	source=source.replace("void fragment() {",FileAccess.get_file_as_string(HELPERS)+"\nvoid fragment() {")
	source=source.replace("\t// Struct to accumulate all texture data.",FileAccess.get_file_as_string("res://world/terrain/gaea_prepare.gdshaderinc")+"\n\t// Struct to accumulate all texture data.")
	source=source.replace(marker,marker+FileAccess.get_file_as_string("res://world/terrain/gaea_fragment.gdshaderinc"))
	# Sand (8) painted up the mountains reads as rusty brown (dev 2026-09-24): above ~160 m
	# (the line wanders +-40 m) it samples mountain stone (21) instead. Desert below stays sand.
	var ids_marker:="\tivec2 texture_ids[4] = ivec2[4]("
	assert(source.count(ids_marker)==1,"Terrain3D shader adapter requires review for this version")
	source=source.replace(ids_marker,SAND_TO_STONE+ids_marker)
	source=_perf_edits(source)
	var shader:=Shader.new();shader.code=source;material.shader_override=shader
	if _bank==null:
		_bank=load(DATA+"surfaces.res")
		assert(_bank.images.size()==10)
		_array=Texture2DArray.new()
		var array_error: Error = _array.create_from_images(_bank.images)
		if array_error != OK:
			push_error("Cannot build terrain texture array")
			return
		var bytes:=FileAccess.get_file_as_bytes(DATA+"materials.f32")
		assert(bytes.size()==int(config.w)*int(config.h)*16)
		var image:=Image.create_from_data(int(config.w),int(config.h),false,Image.FORMAT_RGBAF,bytes)
		image.convert(Image.FORMAT_RGBA8)
		_field_image=image;_config=config
		_field=ImageTexture.create_from_image(image)
	material.set_shader_param("surface_tex",_array)
	material.set_shader_param("surface_mean",_bank.means)
	material.set_shader_param("gaea_field",_field)
	material.set_shader_param("gaea_origin",Vector2(config.bounds[0],config.bounds[1]))
	material.set_shader_param("gaea_samples",Vector2(config.w,config.h))
	material.set_shader_param("gaea_cell",float(config.cell))
	material.set_shader_param("gaea_enabled",true)
	load_grass_palette()
	material.set_shader_param("gaea_grass_region",_grass_region)
	material.set_shader_param("gaea_grass_slot",_grass_slot)
	material.set_shader_param("gaea_original_grass",_original_grass)
	print("[terrain] accepted Gaea surface palette active; native controls/clipmap retained")

static func grass_mean(point: Vector3, old: Color, coverage: float) -> Color:
	if _field_image==null or _bank==null:return old
	var pixel: Vector2=(Vector2(point.x,point.z)-Vector2(_config.bounds[0],_config.bounds[1]))/float(_config.cell)
	if pixel.x<0 or pixel.y<0 or pixel.x>=_field_image.get_width()-1 or pixel.y>=_field_image.get_height()-1:return old
	var at:=Vector2i(pixel.floor());var f:=pixel-Vector2(at)
	var paint: Color=_field_image.get_pixelv(at).lerp(_field_image.get_pixelv(at+Vector2i.RIGHT),f.x).lerp(
		_field_image.get_pixelv(at+Vector2i.DOWN).lerp(_field_image.get_pixelv(at+Vector2i.ONE),f.x),f.y)
	var choice:=clampf(paint.g*3,0,1);var a:=int(choice)  # grass variants only, as the ground shader
	var mean: Vector3=_bank.means[a].lerp(_bank.means[mini(a+1,3)],smoothstep(0,1,choice-a))
	# Clump-footprint mean of the same linear albedo/tint used on the ground.
	var selected:Vector3=Vector3(old.r,old.g,old.b) if _original_grass else _bank.means[_grass_slot]
	mean=(mean*Vector3(.60,.82,.64)).lerp(selected,favorite_weight(point))
	return old.lerp(Color(mean.x,mean.y,mean.z),paint.a*coverage*(1-paint.r))
