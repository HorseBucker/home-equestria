extends RefCounted
## The first picture of a set Luna woke (dev 2026-11-07): a peaceful night sky, deep blue fading
## darker toward the top, a soft glowing moon and a field of stars, a few of them twinkling.
## frames() makes a handful of pictures differing only in which stars are bright; tv_set.gd shows
## them in turn (power_up "night"), through the screen like any picture, so the vintage set's CRT
## look applies to it too.

const FRAMES := 10
const STARS := 170
const TWINKLERS := 0.4

## `size`: the picture in pixels (the screen's shape).
static func frames(size: Vector2i, seed_value := 7) -> Array[ImageTexture]:
	var out: Array[ImageTexture] = []
	for image: Image in images(size, seed_value): out.append(ImageTexture.create_from_image(image))
	return out

## The pictures alone (safe on a worker thread: tv_set.gd prepare_wake).
static func images(size: Vector2i, seed_value := 7) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var base := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for row in size.y:
		var t := float(row) / maxf(1.0, size.y - 1.0)
		var sky := Color(0.01, 0.015, 0.06).lerp(Color(0.05, 0.08, 0.2), t * t)
		base.fill_rect(Rect2i(0, row, size.x, 1), sky)
	# A low glow over the horizon.
	for row in range(int(size.y * 0.8), size.y):
		var t := (float(row) - size.y * 0.8) / (size.y * 0.2)
		for column in size.x:
			base.set_pixel(column, row, base.get_pixel(column, row).lerp(Color(0.12, 0.13, 0.28), t * 0.5))
	var moon := Vector2(size.x * 0.72, size.y * 0.3)
	var radius := size.y * 0.11
	_moon(base, moon, radius)
	var stars: Array = []
	for i in STARS:
		var at := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, int(size.y * 0.85)))
		if Vector2(at).distance_to(moon) < radius * 2.2: continue
		stars.append([at, rng.randf_range(0.35, 1.0), rng.randf() < TWINKLERS, rng.randf() < 0.12])
	var out: Array = []
	for frame in FRAMES:
		var image := base.duplicate() as Image
		for star: Array in stars:
			var bright: float = star[1]
			if bool(star[2]): bright *= rng.randf_range(0.25, 1.0)
			_star(image, star[0], bright, bool(star[3]))
		out.append(image)
	return out

static func _moon(image: Image, centre: Vector2, radius: float) -> void:
	var reach := int(radius * 3.0)
	for y in range(int(centre.y) - reach, int(centre.y) + reach + 1):
		for x in range(int(centre.x) - reach, int(centre.x) + reach + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var d := Vector2(x, y).distance_to(centre)
			var here := image.get_pixel(x, y)
			if d <= radius:
				# The disc, with a few soft grey seas.
				var sea := 0.08 * (sin(x * 0.7) * cos(y * 0.9) + 1.0)
				image.set_pixel(x, y, Color(0.93 - sea, 0.94 - sea, 0.88 - sea * 0.5).lerp(here, clampf(d - radius + 1.0, 0.0, 1.0)))
			else:
				var glow := pow(clampf(1.0 - (d - radius) / (radius * 2.0), 0.0, 1.0), 2.0) * 0.45
				image.set_pixel(x, y, here.lerp(Color(0.6, 0.65, 0.85), glow))

static func _star(image: Image, at: Vector2i, bright: float, big: bool) -> void:
	var colour := Color(0.85, 0.88, 1.0) * bright
	_add(image, at, colour)
	if big or bright > 0.85:
		for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_add(image, at + side, colour * 0.35)

static func _add(image: Image, at: Vector2i, colour: Color) -> void:
	if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height(): return
	var here := image.get_pixel(at.x, at.y)
	image.set_pixel(at.x, at.y, Color(minf(1.0, here.r + colour.r), minf(1.0, here.g + colour.g), minf(1.0, here.b + colour.b)))
