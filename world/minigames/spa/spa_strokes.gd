extends RefCounted
## Spa touch detectors (docs/SPA_PLAN_2026_10_29.md section 3). Pure maths: they read positions
## and contact the input adapter (spa_hands.gd) already worked out, and say what counted. No node,
## no pony and no relationship code is touched here, so the fixture can feed them directly.
##
##   const STROKES := preload("res://world/minigames/spa/spa_strokes.gd")
##   var file := STROKES.Passes.new()        # filing: each one-way pass of the file across the hoof
##   var rub := STROKES.SlowRub.new()        # back hooves and wings: only slow, steady pressure
##   var preen := STROKES.Passes.new(0.08, 1) # preening: base -> tip strokes only
##   var pull := STROKES.FeatherPull.new()   # a stray feather resists, then pops


## One-way passes along a line (the file's blade across her hoof, a hand from wing base to tip).
## A pass counts once it travels `length` metres in one direction while touching; a reversal starts
## the next one. `only_direction` 0 counts both ways, +1 / -1 only that way.
class Passes:
	extends RefCounted
	## A tracking jump (lost controller, teleport) faster than this never counts.
	const MAX_SPEED := 2.5
	const MIN_SECONDS := 0.08
	const DEADBAND := 0.0005
	var length := 0.035
	var only_direction := 0
	var passes := 0
	var _last := INF
	var _direction := 0
	var _travel := 0.0
	var _time := 0.0
	var _counted := false

	func _init(pass_length := 0.035, direction := 0) -> void:
		length = pass_length
		only_direction = direction

	func reset() -> void:
		passes = 0
		_lose()

	func _lose() -> void:
		_last = INF; _direction = 0; _travel = 0.0; _time = 0.0; _counted = false

	## `along`: the contact's position on the line (metres). True when this sample finished a pass.
	func feed(touching: bool, along: float, delta: float) -> bool:
		if not touching or not is_finite(along) or delta <= 0.0:
			_lose()
			return false
		if not is_finite(_last):
			_last = along
			return false
		var step := along - _last
		_last = along
		_time += delta
		if absf(step) < DEADBAND: return false
		if absf(step) / delta > MAX_SPEED:
			_direction = 0; _travel = 0.0; _time = 0.0; _counted = false
			return false
		var direction := 1 if step > 0.0 else -1
		if direction != _direction:
			_direction = direction; _travel = 0.0; _time = 0.0; _counted = false
		_travel += absf(step)
		if _counted or _travel < length or _time < MIN_SECONDS: return false
		if only_direction != 0 and direction != only_direction: return false
		_counted = true
		passes += 1
		return true


## The slow hoof and wing rub (plan 3.B): hand speed 2-25 cm/s with some pressure. Faster rubbing
## pauses progress (no penalty) and raises `too_fast` once. Credit for a pass is held back until it
## has lasted MIN_PASS seconds, then paid in full and from then on as it goes (dev 2026-10-29: "the
## percentage doesnt go up smoothly"; it was 1.5 s and 12 cm/s).
class SlowRub:
	extends RefCounted
	const MIN_SPEED := 0.02
	const MAX_SPEED := 0.25
	const MIN_PASS := 0.3
	## Speed smoothing (s): reversals of a slow back-and-forth dip through zero briefly.
	const SMOOTH := 0.15
	## A hand at rest this long ends the pass.
	const STILL_GRACE := 0.6
	const MIN_PRESSURE := 0.1
	## Smoothed hand speed over the surface (m/s), for buzz and sound.
	var speed := 0.0
	## Seconds of good rubbing credited so far.
	var good := 0.0
	## Set by the sample that first went too fast; cleared on the next feed.
	var too_fast := false
	var pressure := 0.0
	var _previous := Vector3.INF
	var _pass := 0.0
	var _pending := 0.0
	var _still := 0.0
	var _fast := false

	func reset() -> void:
		good = 0.0
		_lose()

	func _lose() -> void:
		_previous = Vector3.INF; speed = 0.0; _pass = 0.0; _pending = 0.0; _still = 0.0; _fast = false; pressure = 0.0

	func in_pass() -> bool:
		return _pass > 0.0

	## Pass progress 0..1 toward MIN_PASS (for a hint or the buzz ramp).
	func pass_ratio() -> float:
		return clampf(_pass / MIN_PASS, 0.0, 1.0)

	## `point`: the hand (world). Feed the tracked hand, not a contact point on the rubbed limb: a
	## held hoof that shakes (a filly's flickers ~5 mm a frame in pony_hoof_hold.gd) would read as
	## fast rubbing. Returns seconds of good rubbing credited now.
	func feed(touching: bool, point: Vector3, hand_pressure: float, delta: float) -> float:
		too_fast = false
		if not touching or not point.is_finite() or delta <= 0.0:
			_lose()
			return 0.0
		pressure = clampf(hand_pressure, 0.0, 1.0)
		if not _previous.is_finite():
			_previous = point
			return 0.0
		var raw := point.distance_to(_previous) / delta
		_previous = point
		speed = lerpf(speed, raw, 1.0 - exp(-delta / SMOOTH))
		if speed > MAX_SPEED:
			if not _fast: too_fast = true
			_fast = true
			_pass = 0.0; _pending = 0.0; _still = 0.0
			return 0.0
		_fast = false
		if speed < MIN_SPEED or pressure < MIN_PRESSURE:
			_still += delta
			if _still >= STILL_GRACE: _pass = 0.0; _pending = 0.0
			return 0.0
		_still = 0.0
		_pass += delta
		var rate := lerpf(0.6, 1.0, pressure)
		_pending += delta * rate
		if _pass < MIN_PASS: return 0.0
		var credited := _pending
		_pending = 0.0
		good += credited
		return credited


## A stray feather between finger and thumb (plan 3.C): it bends toward the hand, resists, then pops
## free once pulled POP_DISTANCE away for at least MIN_SECONDS. A yank faster than MAX_SPEED slips
## out of the fingers instead.
class FeatherPull:
	extends RefCounted
	const POP_DISTANCE := 0.045
	const MIN_SECONDS := 0.25
	const MAX_SPEED := 1.2
	var held := 0.0
	var pull := 0.0
	var _last := INF
	var _start := INF

	func reset() -> void:
		held = 0.0; pull = 0.0; _last = INF; _start = INF

	## How far the feather bends toward the hand, 0..1.
	func bend() -> float:
		return clampf(pull / POP_DISTANCE, 0.0, 1.0)

	## `distance`: hand from the feather's root (m); the pull is measured from where the pinch
	## began. Returns "", "resist", "slip" or "pop".
	func feed(pinching: bool, distance: float, delta: float) -> String:
		if not pinching or not is_finite(distance) or delta <= 0.0:
			reset()
			return ""
		held += delta
		if is_finite(_last) and absf(distance - _last) / delta > MAX_SPEED:
			reset()
			return "slip"
		_last = distance
		if not is_finite(_start): _start = distance
		pull = maxf(0.0, distance - _start)
		if pull >= POP_DISTANCE and held >= MIN_SECONDS:
			reset()
			return "pop"
		return "resist"
