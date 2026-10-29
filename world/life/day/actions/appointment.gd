extends "res://world/life/day/day_action.gd"
## Go to an agreed meeting with Anon and wait there (world/life/appointments/appointments.gd,
## docs/LETTERS_PLAN_2026_10_29.md section 9). She travels like go_to.gd, trotting when far; a
## house means outside its front door. On arrival she tells Appointments she is waiting and stands
## facing the way she came, turning to Anon when he is close. The step ends when the meeting is
## over (met, stood up, lapsed, cancelled), or fails when she cannot get there.

## Hours late by nature, added to the step's start (appointment_steps.gd); everypony else is early.
const LATE := {"rainbow_dash": 0.2, "pinkie_pie": 0.1}
const TRAVEL_LIMIT_S := 600.0
var _point := Vector3.INF
var _from := Vector3.INF
var _phase := "travel"
var _tries := 0

func start(ctx: Dictionary) -> bool:
	var appointments := _appointments(ctx)
	var row: Dictionary = appointments.row(str(ctx.step.get("appointment_id", ""))) if appointments != null else {}
	if row.is_empty() or str(row.get("status", "")) not in ["planned", "waiting"] or _moved(ctx, row): return false
	_point = appointments.place_point(str(ctx.step.target))
	if not _point.is_finite(): return false
	_from = ctx.actor.global_position
	claim(ctx)
	var far: bool = ctx.actor.global_position.distance_to(_point) > 40.0
	ctx.nav.go_to(_point, ctx.nav.Gait.TROT if far else ctx.nav.Gait.WALK)
	return true

func tick(ctx: Dictionary, delta: float) -> String:
	seconds += delta
	var appointments := _appointments(ctx)
	var id := str(ctx.step.get("appointment_id", ""))
	var row: Dictionary = appointments.row(id) if appointments != null else {}
	if row.is_empty() or str(row.get("status", "")) not in ["planned", "waiting"]: return "done"
	# Moved while she was on her way: this step ends; the refreshed card holds the new one.
	if _moved(ctx, row): return "done"
	var nav: Node = ctx.nav
	match _phase:
		"travel":
			if arrived(ctx, _point, 3.0) or nav.state == nav.State.ARRIVED:
				_phase = "stay"; seconds = 0.0
				nav.stay()
				appointments.mark_waiting(id)
				var back: Vector3 = _from - ctx.actor.global_position
				if Vector2(back.x, back.z).length() > 1.0: nav.face_point = ctx.actor.global_position + back.normalized() * 5.0
				return "running"
			if nav.state in [nav.State.UNREACHABLE, nav.State.BLOCKED]:
				_tries += 1
				if _tries > 2: return "failed"
				nav.go_to(_point, nav.Gait.WALK)
			elif not nav._has_target and seconds > 3.0:
				nav.go_to(_point, nav.Gait.WALK)
			if seconds > TRAVEL_LIMIT_S: return "failed"
		"stay":
			var player := _player(ctx)
			if player.is_finite() and ctx.actor.global_position.distance_to(player) < 12.0: nav.face_point = player
	return "running"

func _moved(ctx: Dictionary, row: Dictionary) -> bool:
	if str(row.get("place", "")) != str(ctx.step.target): return true
	if ctx.step.has("hour") and not is_equal_approx(float(row.get("hour", -1.0)), float(ctx.step.hour)): return true
	return ctx.has("day") and int(row.get("day", -1)) != int(ctx.day)

func _appointments(ctx: Dictionary) -> Node:
	return (ctx.tree as SceneTree).get_first_node_in_group("appointments") if ctx.get("tree") is SceneTree else null

func _player(ctx: Dictionary) -> Vector3:
	var camera: Camera3D = ctx.actor.get_viewport().get_camera_3d() if ctx.actor.is_inside_tree() else null
	return camera.global_position if camera != null else Vector3.INF
