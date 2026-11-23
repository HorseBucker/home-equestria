extends Node
## Play test 2026-11-16 checks (agent a): the Cloudominium faces the town as it drifts, and the
## orchard's apples follow the crowns (none on bare trees). Run through the game's --lab hook.
## Prints with a LAB prefix, saves pictures to tools/town_planner/build/out/lab_agent_a/, quits.

const OUT := "res://tools/town_planner/build/out/lab_agent_a"
const DRIFT := preload("res://world/buildings/cloudominium/cloud_drift.gd")
var game: Node
var cam: Camera3D

func _ready() -> void:
	_go.call_deferred()

func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await get_tree().process_frame

func _ground(x: float, z: float) -> float:
	if is_instance_valid(WorldTerrain.instance):
		var h: float = WorldTerrain.instance.height_at(Vector3(x, 0, z))
		if is_finite(h): return h
	return 0.0

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT).path_join(label + ".png"))
	print("LAB shot ", label)

## The rig and its Body (the Body can stand away from the rig root, as cloud_drift.gd notes).
func _place(at: Vector3) -> void:
	var rig: Node3D = game.get("player")
	rig.global_position = at
	var body := rig.find_child("Body", true, false) as Node3D
	if body != null: body.global_position = at
	for n: Node3D in [rig, body]:
		if n != null and "velocity" in n: n.set("velocity", Vector3.ZERO)
	print("LAB placed at ", at, " body ", body.global_position if body != null else Vector3.INF)

func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if str(name) != "Lab":
		queue_free(); return
	for i in 1200:
		if not is_instance_valid(game) or not ("player" in game):
			var scene := get_tree().current_scene
			game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.5)
	if not is_instance_valid(game):
		print("LAB no game"); get_tree().quit(); return
	var arrival: Variant = game.get("arrival")
	if arrival is Node and is_instance_valid(arrival) and (arrival as Node).has_method("skip_to_free_home"):
		await (arrival as Node).skip_to_free_home()
		await _wait(3.0)
	var tod := get_node_or_null("/root/TimeOfDay")
	tod.hours = 12.0; tod.paused = true
	cam = Camera3D.new(); cam.name = "LabCamera"; cam.far = 4000.0; cam.fov = 60.0
	game.add_child(cam)
	await _cloud(tod)
	if not OS.get_cmdline_user_args().has("--lab-cloud-only"): await _apples(tod)
	print("LAB done")
	get_tree().quit()

# ------------------------------------------------------------------ the cloud house

func _cloud(tod: Node) -> void:
	var drift: Node = null
	for n: Node in get_tree().root.find_children("CloudDrift", "", true, false):
		print("LAB CLOUD drift node ", n.get_path(), " processing ", n.is_physics_processing(), " can_process ", n.can_process(), " game ", n.get("game"))
		drift = n
	if drift == null:
		print("LAB CLOUD no CloudDrift"); return
	var frame: Node3D = drift.get("frame")
	var pivot: Vector3 = drift.get("pivot")
	var front: Vector3 = drift.get("front")
	print("LAB CLOUD pivot ", pivot, " rest door direction ", front, " town ", DRIFT.TOWN)
	# The pure pose over two in-game weeks of clock: facing error and the largest turn per 0.1 s step.
	var worst_error := 0.0; var worst_turn := 0.0
	var last_yaw := NAN
	var t := 0.0
	while t < 200000.0:
		var pose: Transform3D = DRIFT.motion(t, pivot, front)
		var door: Vector3 = pose.basis * front; door.y = 0.0
		var at: Vector3 = pose * pivot
		var to_town := Vector3(DRIFT.TOWN.x - at.x, 0.0, DRIFT.TOWN.z - at.z)
		worst_error = maxf(worst_error, rad_to_deg(door.angle_to(to_town)))
		var yaw := atan2(door.x, door.z)
		if is_finite(last_yaw): worst_turn = maxf(worst_turn, rad_to_deg(absf(angle_difference(last_yaw, yaw))) / (37.0 / 0.1))
		last_yaw = yaw
		t += 37.0
	print("LAB CLOUD over 200000 s: worst facing error %.4f deg, largest turn per 0.1 s step %.6f deg" % [worst_error, worst_turn])
	# Live: the door now, and a rider standing in the hall carried through the drift.
	var player: Node3D = game.get("player")
	var home: Node = frame.get_node_or_null("HouseInterior")
	var live_door: Vector3 = frame.global_basis.z; live_door.y = 0.0
	var to_town_now := Vector3(DRIFT.TOWN.x - frame.global_position.x, 0.0, DRIFT.TOWN.z - frame.global_position.z)
	print("LAB CLOUD live: frame at ", frame.global_position, " door off the town bearing by %.3f deg" % rad_to_deg(live_door.angle_to(to_town_now)))
	if home != null: print("LAB CLOUD outside() (door approach) ", home.call("outside"), " inside() ", home.call("inside"))
	# Pictures: from the ground on the town side of the house, and from the hall's own square.
	var to_house: Vector3 = frame.global_position - DRIFT.TOWN; to_house.y = 0.0
	var stand: Vector3 = frame.global_position - to_house.normalized() * 70.0
	_place(Vector3(stand.x, _ground(stand.x, stand.z) + 0.4, stand.z))
	await _wait(40.0)
	cam.look_at_from_position(Vector3(stand.x, frame.global_position.y - 4.0, stand.z), frame.global_position + Vector3.UP * 4.0, Vector3.UP)
	cam.make_current()
	await _wait(2.0)
	await _shot("cloud_from_town_side")
	# Hop the clock a quarter of the slowest wave: the house has drifted, still faces the town.
	var before_t: float = float(tod.active_seconds)
	var before_at: Vector3 = frame.global_position
	tod.active_seconds = before_t + 340.0
	await _wait(3.0)
	var who: Node3D = drift.call("_player")
	print("LAB CLOUD drift's player ", who.get_path() if who != null else NodePath(), " at ", who.global_position if who != null else Vector3.INF, " can_process ", drift.can_process())
	print("LAB CLOUD clock %.1f -> %.1f, moved %.2f m" % [before_t, float(tod.active_seconds), before_at.distance_to(frame.global_position)])
	live_door = frame.global_basis.z; live_door.y = 0.0
	to_town_now = Vector3(DRIFT.TOWN.x - frame.global_position.x, 0.0, DRIFT.TOWN.z - frame.global_position.z)
	print("LAB CLOUD after 340 s: frame at ", frame.global_position, " door off the town bearing by %.3f deg" % rad_to_deg(live_door.angle_to(to_town_now)))
	cam.look_at_from_position(Vector3(stand.x, frame.global_position.y - 4.0, stand.z), frame.global_position + Vector3.UP * 4.0, Vector3.UP)
	await _wait(1.0)
	await _shot("cloud_from_town_side_later")
	# A rider through the drift's own step (_move, as _physics_process calls it; the real player is
	# kept far off by the new game's spawn, past FAR_METRES, so the live loop sleeps): a stand-in
	# body in the hall, the clock run 30 s a step over 12000 s. It must stay where it stood in the
	# house's frame, the door must keep facing the town, and the yaw must change.
	var rider := Node3D.new(); rider.name = "LabRider"; game.add_child(rider)
	rider.global_position = (home.call("inside") if home != null else frame.to_global(Vector3(0, 0.3, 0)))
	var start_local: Vector3 = frame.to_local(rider.global_position)
	var t0: float = float(tod.active_seconds)
	var kept := 0; var worst_slip := 0.0; var worst_face := 0.0
	var yaws := PackedFloat32Array()
	for i in 400:
		drift.call("_move", t0 + 30.0 * (i + 1), rider)
		if bool(drift.call("holds", rider.global_position)): kept += 1
		worst_slip = maxf(worst_slip, frame.to_local(rider.global_position).distance_to(start_local))
		var d: Vector3 = frame.global_basis.z; d.y = 0.0
		var tt := Vector3(DRIFT.TOWN.x - frame.global_position.x, 0.0, DRIFT.TOWN.z - frame.global_position.z)
		worst_face = maxf(worst_face, rad_to_deg(d.angle_to(tt)))
		yaws.append(rad_to_deg(atan2(d.x, d.z)))
	var lo := 999.0; var hi := -999.0
	for y in yaws: lo = minf(lo, y); hi = maxf(hi, y)
	print("LAB CLOUD rider via _move: aboard %d/400, worst slip in the house frame %.4f m, worst door error %.4f deg, door yaw range %.3f..%.3f deg" % [kept, worst_slip, worst_face, lo, hi])
	drift.call("_move", float(tod.active_seconds), null)
	rider.queue_free()

# ------------------------------------------------------------------ the orchard's apples

func _apples(tod: Node) -> void:
	var bucking: Node = game.get("apple_bucking")
	var season: Node = get_tree().get_first_node_in_group("season_state")
	var farm: Node3D = get_tree().get_first_node_in_group("apple_orchards") as Node3D
	if bucking == null or season == null or farm == null:
		print("LAB APPLES missing node: ", bucking, season, farm); return
	var trees: Array = farm.get("orchard_trees")
	var batch: MultiMesh = farm.get("_apple_batch")
	var length: int = int(season.call("season_days"))
	var start: int = int(tod.day)
	var bad := 0
	var shots := {}
	for d in range(start, start + length * 4 + 1):
		tod.day = d
		season.call("tick")
		bucking.call("refresh")
		await get_tree().process_frame
		await get_tree().process_frame
		var crowns: bool = bool(season.call("crowns_out"))
		var shown := 0
		for tree: Dictionary in trees:
			for k in int((tree.apples as Array).size()):
				if batch.get_instance_transform(int(tree.first) + k).basis.x.length() > 0.01: shown += 1
		var ripe: int = int(bucking.get("_ripe_count"))
		var markers: Array = bucking.call("activity_markers")
		var state := "%s day %d" % [season.call("season"), int(season.call("day_into_season")) + 1]
		var bare: bool = float(season.call("leaf_drop")) >= 0.999 or (float(season.call("spring")) > 0.0 and float(season.call("spring")) <= 0.28)
		if bare and (shown > 0 or ripe > 0 or not markers.is_empty()): bad += 1
		print("LAB APPLES %-14s drop %.2f spring %.3f crowns_out %s apples shown %d ripe trees %d markers %d%s" % [state,
			float(season.call("leaf_drop")), float(season.call("spring")), crowns, shown, ripe, markers.size(), "  <-- APPLES ON BARE TREES" if bare and shown > 0 else ""])
		var label := ""
		if str(season.call("season")) == "spring" and int(season.call("day_into_season")) == 2: label = "orchard_spring_day3"
		elif str(season.call("season")) == "spring" and int(season.call("day_into_season")) == 6: label = "orchard_spring_day7"
		elif str(season.call("season")) == "winter" and int(season.call("day_into_season")) == 5: label = "orchard_winter_day6"
		elif str(season.call("season")) == "autumn" and int(season.call("day_into_season")) == length - 1: label = "orchard_autumn_last_day"
		elif str(season.call("season")) == "summer" and int(season.call("day_into_season")) == 5: label = "orchard_summer_day6"
		if label != "" and not shots.has(label):
			shots[label] = true
			await _orchard_shot(label)
	print("LAB APPLES days with fruit, a ripe count or a marker on bare crowns: ", bad)

func _orchard_shot(label: String) -> void:
	var player: Node3D = game.get("player")
	var rows: Dictionary = game.get("apple_bucking").get("trees")
	var look: Vector3 = (rows.values()[0] as Dictionary).position
	var at := Vector2(look.x + 26.0, look.z + 20.0)
	_place(Vector3(at.x, _ground(at.x, at.y) + 0.4, at.y))
	if "velocity" in player: player.set("velocity", Vector3.ZERO)
	await _wait(20.0 if label == "orchard_spring_day3" or label == "orchard_summer_day6" else 6.0)
	cam.look_at_from_position(Vector3(at.x, _ground(at.x, at.y) + 4.0, at.y), Vector3(look.x, _ground(look.x, look.z) + 1.5, look.z), Vector3.UP)
	cam.make_current()
	await _wait(1.5)
	await _shot(label)
