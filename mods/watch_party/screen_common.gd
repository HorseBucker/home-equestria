extends RefCounted
## What every television's screen shares (tv_model.gd the vintage set, flat_model.gd the
## flatscreens): the shader code that samples the picture, crossfades from the previous one (the
## photo slideshow) and draws the pointer in TV mode, and the spec each model gives tv_set.gd.
##
## A model script (tv_model.gd, flat_model.gd) offers the same static functions, each taking the
## variant ("" for the vintage set; "stand" or "wall" for the flatscreens):
## spec(variant) -> Dictionary, build(parent, variant), bounds(variant), part_at(local, variant),
## screen_material(), power_light_material(on).
## spec keys: kind ("crt" or "flat"), centre (Vector2, screen middle on the front), size (Vector2,
## the picture in metres), z (the glass), text_z (in front of it, for captions and subtitles),
## speaker (Vector3), picture (Vector2i, pixels ffmpeg sends), page (Vector2i, browser pixels),
## glow_z (the set's light, in front of the glass), power ("crt" line and dot, or "fade").

## Pasted into each screen shader after its own uniforms.
const SHADER := """
uniform sampler2D picture : source_color, filter_linear, repeat_disable;
uniform sampler2D previous : source_color, filter_linear, repeat_disable;
uniform float fade = 1.0;
uniform vec2 cursor = vec2(-1.0, -1.0);
uniform float aspect = 1.333;

vec3 screen_picture(vec2 uv) {
	vec3 c = texture(picture, uv).rgb;
	if (fade < 0.999) c = mix(texture(previous, uv).rgb, c, clamp(fade, 0.0, 1.0));
	return c;
}

// An arrow pointer while in TV mode: the tip of its outline is at `cursor` (UV, top left 0,0),
// exactly where a click lands.
vec3 with_cursor(vec3 c, vec2 uv) {
	if (cursor.x < 0.0) return c;
	vec2 p = (uv - cursor) * vec2(aspect, 1.0) / 0.026 + vec2(-0.12, -0.2);
	bool outer = p.x >= -0.12 && p.y >= -0.2 && p.x <= 0.68 * p.y + 0.12 && p.y + 0.55 * p.x <= 1.12;
	if (!outer) return c;
	bool inner = p.x >= 0.0 && p.y >= 0.0 && p.x <= 0.62 * p.y && p.y + 0.55 * p.x <= 0.98;
	return inner ? vec3(1.0) : vec3(0.0);
}
"""

## Where a point on the front (the set's own frame) falls on the picture, as UV (top left 0,0);
## outside 0..1 when it misses.
static func uv_at(spec: Dictionary, local: Vector3) -> Vector2:
	var centre: Vector2 = spec.centre
	var size: Vector2 = spec.size
	return Vector2((local.x - centre.x) / size.x + 0.5, 0.5 - (local.y - centre.y) / size.y)

static func on_picture(uv: Vector2) -> bool:
	return uv.x >= 0.0 and uv.y >= 0.0 and uv.x <= 1.0 and uv.y <= 1.0

## The part of `tv` a ray (world `from`, `direction`) points at: {part, point (world)}. The ray is
## carried on to the screen's plane, so a set whose collision box stands proud of its screen (the
## flatscreen's console) still reads its screen and front from straight ahead; `hit` (world) is
## where the ray met the set's collision, used when the plane is missed.
static func part_on_ray(tv: Node3D, from: Vector3, direction: Vector3, hit: Vector3) -> Dictionary:
	var model: Script = tv.get("model")
	var variant: Variant = tv.get("variant")
	var spec: Dictionary = tv.get("spec")
	var inverse := tv.global_transform.affine_inverse()
	var local_from := inverse * from
	var local_direction := inverse.basis * direction
	var box: AABB = model.call("bounds", variant)
	# Only through the box's front face: from the sides and back the set is picked up as before.
	if local_direction.z < -0.0001 and (inverse * hit).z >= box.end.z - 0.02:
		var along := (float(spec.z) - local_from.z) / local_direction.z
		if along > 0.0:
			var on_plane := local_from + local_direction * along
			var part := str(model.call("part_at", on_plane, variant))
			if not part.is_empty(): return {"part": part, "point": tv.global_transform * on_plane}
	return {"part": str(model.call("part_at", inverse * hit, variant)), "point": hit}
