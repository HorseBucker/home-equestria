extends RefCounted
## Agreed meetings go into a day card (docs/LETTERS_PLAN_2026_10_29.md section 9): one fixed step
## per meeting that day, starting 45 game minutes before the hour (an hour for a place over 300 m
## from her home; later for a pony who is late by nature, actions/appointment.gd LATE) and lasting
## until she stops waiting. Rolled steps that overlap it are dropped; the card stays ordered by
## start. Running the merge again is harmless: earlier appointment steps are replaced.

const HANDLER := preload("res://world/life/day/actions/appointment.gd")
const EARLY := 0.75
const FAR_EXTRA := 0.25
const FAR_M := 300.0
const WAIT := 1.0

static func merge(id: String, day: int, steps: Array, appointments: Node) -> Array:
	var rows: Array = appointments.rows_for_day(id, day) if is_instance_valid(appointments) and appointments.has_method("rows_for_day") else []
	var fixed: Array = []
	for row: Dictionary in rows: fixed.append(step_for(id, row, appointments))
	var out: Array = []
	for step: Dictionary in steps:
		if step.has("appointment_id"): continue
		var clash := false
		for f: Dictionary in fixed:
			if float(step.start) < float(f.until) and float(step.until) > float(f.start): clash = true; break
		if not clash: out.append(step)
	out.append_array(fixed)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.start) < float(b.start))
	return out

static func step_for(id: String, row: Dictionary, appointments: Node) -> Dictionary:
	var hour := float(row.hour)
	var far: bool = appointments.has_method("home_distance") and float(appointments.home_distance(id, str(row.place))) > FAR_M
	var start := hour - EARLY - (FAR_EXTRA if far else 0.0) + float(HANDLER.LATE.get(id, 0.0))
	var until := hour + WAIT
	# "minutes" spans the whole wait, so an unloaded pony's essence also stays until she gives up.
	return {"action": "appointment", "handler": "appointment", "target": str(row.place), "item": "",
		"reason": "as agreed", "posture": "stand", "minutes": (until - start) * 60.0,
		"start": start, "until": until, "night": false, "phrase": "meet Anon at {target}",
		"fixed": true, "appointment_id": str(row.id), "hour": hour}
