extends Node
## Quality control inside the real game: can ponies walk where they need to? (the game's `--lab` hook)
##   godot --xr-mode off --path <project> -- --new-game --skip-title --lab res://tools/town_planner/build/qc/nav_lab.gd
## (needs a window; set APPDATA to a scratch folder first). Prints NAV lines and quits:
## - every bridge: a pony's route from 5 m before one foot to 5 m past the other (the game's own approach points),
##   its length against the straight line, or why there is none;
## - every walk-in house: how far the spot before its door (where a pony stands to go in) is above or below the
##   ground, and whether a pony can walk the last 6 m up to it;
## - routes from the fountain to a spread of front doors (Roseluck's among them), to the barn's yard, the library,
##   the schoolhouse, Fluttershy's cottage, and out of the southern meadow where Pinkie was found.

const RIVER := preload("res://world/navigation/river_crossings.gd")
const PLACEMENT := preload("res://world/navigation/roster_placement.gd")
var game: Node
var player: Node3D
var profile: Resource
var _answer: Dictionary = {}
var _answered := false


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await get_tree().process_frame


func _ground(x: float, z: float) -> float:
	var h: float = WorldTerrain.instance.height_at(Vector3(x, 0, z)) if is_instance_valid(WorldTerrain.instance) else NAN
	return h


func _service(at: Vector3) -> Node:
	var found: Node = PLACEMENT.select_service(get_tree().get_nodes_in_group("pony_navigation"), at)
	if found != null: return found
	# outside every region's box (the plan's west edge lies 86 m beyond Ponyville's): a resident keeps her region's
	# service there, whose bounds are "a streaming footprint, not an invisible fence" and grow where there is ground
	for s in get_tree().get_nodes_in_group("pony_navigation"):
		if str(s.get("zone_id")) == "ponyville" or str(s.get_path()).contains("ResidentNavigation_ponyville"): return s
	return null


func _stand(x: float, z: float) -> void:
	var h := _ground(x, z)
	player.global_position = Vector3(x, (h if is_finite(h) else 0.0) + 0.4, z)
	if "velocity" in player: player.set("velocity", Vector3.ZERO)


func _got(result: Dictionary, _id: int, _revision: int) -> void:
	_answer = result; _answered = true


## A pony's route between two points: [length or -1, reason]. The game's own request: it loads and samples the
## walk grid along the way itself; a start or goal with no floor a pony can stand on is its "No safe floor" answer.
func _route(from: Vector3, to: Vector3) -> Array:
	var service := _service(from)
	if service == null: return [-1.0, "no navigation service here"]
	for i in 240:
		if service.ready_for_paths: break
		await _wait(0.5)
	var reason := ""
	for attempt in 4:
		_answered = false
		service.request_path(from, to, profile, _got, false, false)
		for i in 3600:
			if _answered: break
			await get_tree().process_frame
		if not _answered: return [-1.0, "no answer in a minute"]
		var path: PackedVector3Array = _answer.get("path", PackedVector3Array())
		if not path.is_empty():
			var length := 0.0
			for k in range(1, path.size()): length += path[k - 1].distance_to(path[k])
			return [length, ""]
		reason = str(_answer.get("reason", "no path"))
		await _wait(2.0)
	return [-1.0, reason]


## Ask for the walk grid round a spot and wait until it is sampled and ready; false when it is not within `seconds`
## (then a "cannot stand" would say nothing about the ground: the game samples a zone a few chunks a frame).
func _sampled(service: Node, at: Vector3, radius: float, seconds := 7.0) -> bool:
	var coords: Array = service.ensure_near(at, radius)
	for i in int(seconds * 10.0):
		var waiting := false
		for c: Vector2i in coords:
			if not service.grid.chunks.has(c) or int(service.grid.chunks[c].state) != 4: waiting = true      # WalkChunk.State.READY
		if not waiting:
			await _wait(0.3)          # the snapshot the queries read is published after the chunk is ready
			return true
		service.ensure_near(at, radius)
		await _wait(0.1)
	return false


## What is in the way at a spot a pony cannot stand at: the solid things within 1.3 m, and what a ray down finds.
func _why_not(at: Vector3) -> void:
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new(); ball.radius = 1.3
	query.shape = ball; query.collision_mask = 1; query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.9)
	var names: Array = []
	for hit: Dictionary in space.intersect_shape(query, 12):
		var c: Node = hit.collider
		names.append(str(c.get_path()).right(70))
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 3.0, 1))
	print("NAV    at (%.1f, %.2f, %.1f): terrain %.2f; ray down hits %s at %.2f (normal y %.2f); within 1.3 m: %s" % [at.x, at.y, at.z, _ground(at.x, at.z),
		str((down.collider as Node).name) if not down.is_empty() else "nothing", down.position.y if not down.is_empty() else NAN,
		down.normal.y if not down.is_empty() else NAN, ", ".join(names)])


func _xz(v: Vector2) -> Vector3:
	var h := _ground(v.x, v.y)
	return Vector3(v.x, h if is_finite(h) else 0.0, v.y)


func _go() -> void:
	if str(name) != "Lab":
		queue_free(); return
	for i in 1200:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.5)
	if not is_instance_valid(game):
		print("NAV no game scene; giving up"); get_tree().quit(); return
	player = game.get("player")
	var arrival: Variant = game.get("arrival")
	if arrival is Node and is_instance_valid(arrival) and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
		await _wait(3.0)
	profile = PLACEMENT.PROFILE.new()
	_stand(118, -170)
	await _wait(45.0)
	# ---- bridges ----
	var bad := 0
	var approaches: Dictionary = RIVER.approaches() if not OS.get_cmdline_user_args().has("--nav-skip-bridges") else {}
	for id: String in approaches:
		var ends: Array = approaches[id]
		var a := _xz(ends[0]); var b := _xz(ends[1])
		_stand((a.x + b.x) / 2.0 + 6.0, (a.z + b.z) / 2.0 + 6.0)
		await _wait(3.0)
		var there: Array = await _route(a, b)
		var back: Array = await _route(b, a)
		var straight := a.distance_to(b)
		var ok: bool = float(there[0]) > 0.0 and float(there[0]) < straight * 1.6 and float(back[0]) > 0.0 and float(back[0]) < straight * 1.6
		if not ok: bad += 1
		print("NAV bridge %s: %s; straight %.1f m, there %.1f m %s, back %.1f m %s" % [id, "crossed" if ok else "NOT CROSSED", straight, there[0], there[1], back[0], back[1]])
	print("NAV bridges a pony cannot cross: ", bad, " of ", approaches.size())
	# ---- doors ----
	var homes: Array = get_tree().get_nodes_in_group("house_interiors")
	var skip_doors := OS.get_cmdline_user_args().has("--nav-skip-doors")
	for s in get_tree().get_nodes_in_group("pony_navigation"): print("NAV service ", s.get_path(), " zone ", s.get("zone_id"), " bounds ", s.get("bounds"))
	# `--nav-doors plot_052,town_hall`: only these houses' doors (and no trips after them)
	var only_doors := PackedStringArray()
	var lab_args := OS.get_cmdline_user_args()
	for i in lab_args.size():
		if lab_args[i] == "--nav-doors" and i + 1 < lab_args.size(): only_doors = lab_args[i + 1].split(",")
	var sunk := 0; var blocked := 0; var walked := 0
	var again: Array = []
	for home: Node3D in homes:
		if skip_doors or not home.is_inside_tree() or not home.has_method("outside") or not home.has_method("inside"): continue
		if not only_doors.is_empty() and not only_doors.has(str(home.get_parent().name)): continue
		var out: Vector3 = home.outside()
		if not only_doors.is_empty(): print("NAV door %s: outside %s, inside %s, service %s" % [home.get_parent().name, out, home.inside(), _service(out)])
		var h := _ground(out.x, out.z)
		var off := out.y - h if is_finite(h) else 0.0
		if off > 30.0: continue                                  # a sky home's door is not on the ground
		if absf(off) > 0.5:
			sunk += 1
			print("NAV door %s at (%.1f, %.1f): the spot before it is %+.2f m from the ground" % [home.get_parent().name, out.x, out.z, off])
		# a pony walks up to the door: from 6 m out before it to the spot where she stands to go in
		var front: Vector3 = out - home.inside(); front.y = 0.0
		var start := _xz(Vector2(out.x, out.z) + Vector2(front.x, front.z).normalized() * 6.0)
		var got: Array = await _route(start, out)
		if float(got[0]) > 0.0 and float(got[0]) < 14.0: walked += 1
		else: again.append([home, start, got])
	# the ones that failed: once more with the player standing by (the ground's collision is only loaded near him)
	for item: Array in again:
		var home2: Node3D = item[0]
		var out2: Vector3 = home2.outside()
		_stand(out2.x + 7.0, out2.z + 7.0)
		await _wait(5.0)
		var got2: Array = await _route(_xz(Vector2((item[1] as Vector3).x, (item[1] as Vector3).z)), out2)
		if float(got2[0]) > 0.0 and float(got2[0]) < 14.0: walked += 1
		else:
			blocked += 1
			print("NAV door %s (%s) at (%.1f, %.1f): a pony CANNOT walk the last 6 m to it: %s" % [home2.get_parent().name, home2.place_id() if home2.has_method("place_id") else "", out2.x, out2.z,
				("her way is %.0f m long" % got2[0]) if float(got2[0]) > 0.0 else str(got2[1])])
			_why_not(out2)
	print("NAV walk-in houses: ", homes.size(), "; a pony walks up to the door of ", walked, "; cannot: ", blocked, "; door spots more than 0.5 m off the ground: ", sunk, "; asked twice: ", again.size())
	# ---- routes ----
	if not only_doors.is_empty():
		print("NAV done"); get_tree().quit(); return
	var fountain := Vector2(108.0, -183.0)
	var trips: Array = []
	var population: Variant = game.get("population")
	var n := 0
	for home: Node3D in homes:
		if not home.is_inside_tree() or not home.has_method("outside") or not str(home.get_parent().name).begins_with("plot_"): continue
		n += 1
		var who := ""
		if population is Node and (population as Node).has_method("residents_of"): who = ", ".join((population as Node).residents_of(home.place_id()))
		if n % 9 == 0 or "rose" in who.to_lower():
			var out2: Vector3 = home.outside()
			trips.append(["the fountain to %s's door (%s)" % [who if who != "" else "nopony", home.get_parent().name], fountain, Vector2(out2.x, out2.z)])
	for home: Node3D in homes:
		var nm := str(home.get_parent().name)
		if home.has_method("outside") and (nm.contains("barn") or nm.contains("library") or nm.contains("cottage") or nm.contains("boutique") or nm.contains("sugarcube")):
			var out3: Vector3 = home.outside()
			trips.append(["the fountain to the door of " + nm, fountain, Vector2(out3.x, out3.z)])
	trips.append(["the southern meadow (134, -55) to the fountain", Vector2(134, -55), fountain])
	trips.append(["the fountain to the schoolhouse steps", fountain, Vector2(45.5, -50.0)])
	trips.append(["the fountain to the east meadow (240, -20)", fountain, Vector2(240, -20)])
	trips.append(["the fountain to Carrot Top's farmhouse", fountain, Vector2(359.2, -174.0)])
	trips.append(["the east meadow (240, -20) to Sugarcube Corner's front", Vector2(240, -20), Vector2(4.0, -143.0)])
	trips.append(["the fountain to Fluttershy's door", fountain, Vector2(410.6, -8.0)])
	trips.append(["the fountain to the clubhouse", fountain, Vector2(-36.0, -10.5)])
	trips.append(["the fountain to the library door", fountain, Vector2(-9.5, -251.5)])
	trips.append(["the fountain to the station", fountain, Vector2(-48.0, -246.0)])
	var failed := 0
	for trip: Array in trips:
		var a2 := _xz(trip[1]); var b2 := _xz(trip[2])
		_stand(b2.x + 6.0, b2.z + 6.0)
		await _wait(4.0)
		# as a pony goes: by the bridges' approach points when the straight way crosses water, leg by leg
		var stops: Array = [a2] + RIVER.route(a2, b2) + [b2]
		# and no leg longer than her own (pony_navigator.gd JOURNEY_LEG, 110 m): a long one is walked in pieces
		var pieces: Array = [stops[0]]
		for k in range(1, stops.size()):
			var from_stop: Vector3 = stops[k - 1]; var to_stop: Vector3 = stops[k]
			var parts := maxi(1, ceili(Vector2(to_stop.x - from_stop.x, to_stop.z - from_stop.z).length() / 100.0))
			for part in range(1, parts + 1):
				var at_part := from_stop.lerp(to_stop, float(part) / parts)
				pieces.append(_xz(Vector2(at_part.x, at_part.z)) if part < parts else to_stop)
		var bridge_points := stops.size() - 2
		stops = pieces
		var got: Array = [0.0, "%d bridge points, %d legs" % [bridge_points, stops.size() - 1]]
		for k in range(1, stops.size()):
			var leg: Array = await _route(stops[k - 1], stops[k])
			if float(leg[0]) < 0.0:
				got = [-1.0, "leg %d of %d, (%.0f, %.0f) to (%.0f, %.0f): %s" % [k, stops.size() - 1, stops[k - 1].x, stops[k - 1].z, stops[k].x, stops[k].z, leg[1]]]; break
			got[0] = float(got[0]) + float(leg[0])
		if float(got[0]) < 0.0: failed += 1
		print("NAV route %s: %s (straight %.0f m)" % [trip[0], ("%.0f m by %s" % [got[0], got[1]]) if float(got[0]) > 0.0 else "NONE: " + str(got[1]), a2.distance_to(b2)])
	print("NAV routes with no way: ", failed, " of ", trips.size())
	print("NAV done")
	get_tree().quit()
