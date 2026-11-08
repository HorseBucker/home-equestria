extends RefCounted
## The first picture of a set Celestia woke (dev 2026-11-07): a sunrise. It starts as night, a
## few stars over dark rolling hills, then the sky warms from purple through rose to gold as the
## sun climbs over the hills, and settles into a soft morning blue. images() makes the frames in
## order (on a worker thread: tv_set.gd prepare_wake); tv_set.gd shows them across SUNRISE_RISE
## seconds, through the screen like any picture, so the CRT look applies, and the set's light
## warms the room with it.

const FRAMES := 30
const STARS := 90

static func images(size: Vector2i, seed_value := 11) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var stars: Array = []
	for i in STARS: stars.append([Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, int(size.y * 0.6))), rng.randf_range(0.3, 1.0)])
	var ridge := PackedFloat32Array()
	ridge.resize(size.x)
	for x in size.x:
		var u := float(x) / size.x
		ridge[x] = size.y * (0.74 + 0.05 * sin(u * 7.0 + 1.3) + 0.03 * sin(u * 17.0 + 0.4))
	var out: Array = []
	for frame in FRAMES:
		var p := float(frame) / float(FRAMES - 1)
		out.append(_frame(size, p, stars, ridge))
	return out

static func _frame(size: Vector2i, p: float, stars: Array, ridge: PackedFloat32Array) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	# The sky: from night (p 0) through dawn colours to a soft morning (p 1).
	var top := _over(p, [Color(0.02, 0.02, 0.08), Color(0.12, 0.06, 0.25), Color(0.25, 0.35, 0.65), Color(0.35, 0.55, 0.9)])
	var low := _over(p, [Color(0.08, 0.04, 0.15), Color(0.75, 0.3, 0.35), Color(1.0, 0.7, 0.35), Color(0.85, 0.9, 1.0)])
	for row in size.y:
		var t := pow(float(row) / (size.y * 0.75), 1.4)
		image.fill_rect(Rect2i(0, row, size.x, 1), top.lerp(low, clampf(t, 0.0, 1.0)))
	# Stars, fading out as the sky lightens.
	var star_light := clampf(1.0 - p / 0.35, 0.0, 1.0)
	if star_light > 0.0:
		for star: Array in stars:
			var at: Vector2i = star[0]
			var here := image.get_pixel(at.x, at.y)
			image.set_pixel(at.x, at.y, here.lerp(Color(0.9, 0.9, 1.0), float(star[1]) * star_light))
	# The sun, rising from behind the hills, red-orange low down, warm white higher up.
	var horizon := size.y * 0.76
	var radius := size.y * 0.1
	var centre := Vector2(size.x * 0.42, lerpf(horizon + radius * 1.2, size.y * 0.3, smoothstep(0.1, 1.0, p)))
	var colour := Color(1.0, 0.45, 0.2).lerp(Color(1.0, 0.96, 0.8), smoothstep(0.2, 0.9, p))
	var glow_reach := radius * lerpf(2.0, 4.0, p)
	var glow_strength := lerpf(0.35, 0.6, p)
	for y in range(maxi(0, int(centre.y - glow_reach)), mini(size.y, int(centre.y + glow_reach) + 1)):
		for x in range(maxi(0, int(centre.x - glow_reach)), mini(size.x, int(centre.x + glow_reach) + 1)):
			var d := Vector2(x, y).distance_to(centre)
			var here := image.get_pixel(x, y)
			if d <= radius: image.set_pixel(x, y, colour.lerp(here, clampf(d - radius + 1.0, 0.0, 1.0)))
			else:
				var glow := pow(clampf(1.0 - (d - radius) / (glow_reach - radius), 0.0, 1.0), 2.0) * glow_strength
				image.set_pixel(x, y, here.lerp(colour, glow))
	# The hills in front, dark, catching a little light as the morning comes.
	var hill := Color(0.03, 0.02, 0.06).lerp(Color(0.16, 0.22, 0.14), smoothstep(0.3, 1.0, p))
	for x in size.x:
		var from := int(ridge[x])
		if from < size.y: image.fill_rect(Rect2i(x, from, 1, size.y - from), hill)
	return image

## A colour along `stops` (evenly spaced) at `p`.
static func _over(p: float, stops: Array) -> Color:
	var span := p * (stops.size() - 1)
	var index := mini(int(span), stops.size() - 2)
	return (stops[index] as Color).lerp(stops[index + 1] as Color, span - index)
