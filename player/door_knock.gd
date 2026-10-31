extends RefCounted
## Knocking on a house's front door (player bug board #31). The door raps and reports the knock
## (hinged_door.knock_from_desktop for a right click, hand_rap for a VR fist); this finds who
## answers. Only a free, awake pony who is home comes: the one inside nearest the door
## (pony_player_approaches.knock_answerer). With the AI on she walks out and greets the player
## (conversation_director.answer_knock); with it off she walks out and waits by him a little while.

const SHUTDOWN := preload("res://world/shutdown_waits.gd")
const APPROACHES := preload("res://world/ai/pony_player_approaches.gd")
const OWNER := "knock:answer"
const WAIT_AT_DOOR := 30.0

static func answer(door: Node3D) -> void:
	if not is_instance_valid(door) or not door.is_inside_tree(): return
	var home: Node3D = null
	for candidate: Node in door.get_tree().get_nodes_in_group("house_interiors"):
		if candidate.has_method("door") and candidate.door() == door: home = candidate; break
	var camera := door.get_viewport().get_camera_3d()
	# Knocking from inside, or on a door that is not a home's front door: only the raps.
	if home == null or camera == null or home.contains(camera.global_position, true): return
	var director: Node = door.get_tree().get_first_node_in_group("conversation_director")
	if director != null and director.has_method("answer_knock"):
		director.answer_knock(door, home)
		return
	var pony := APPROACHES.knock_answerer(door, home, door.get_tree().get_nodes_in_group("sim_ponies"))
	if pony == null: print("[knock] nopony answers at %s" % home.label())
	else: _answer_without_ai(door, home, pony, camera)

## No AI: she walks out, turns to the player and waits by the door, then goes back to her day.
static func _answer_without_ai(door: Node3D, home: Node3D, pony: Node3D, player: Node3D) -> void:
	var nav: Node = pony.get_node("Navigator")
	var spot: Vector3 = APPROACHES.knock_spot(home, nav, player.global_position)
	if not spot.is_finite(): return
	var previous := {"owner": nav.command_owner, "wander": nav.wander_enabled}
	nav.command_owner = OWNER; nav.wander_enabled = false
	if pony.has_method("request_posture"): pony.request_posture("stand")
	if not nav.command_destination(spot, "walk"):
		nav.command_owner = previous.owner; nav.wander_enabled = previous.wander
		return
	print("[knock] %s comes to the door" % pony.name)
	var waited := 0.0
	var arrived_at := -1.0
	while waited < 75.0 + WAIT_AT_DOOR:
		if not await SHUTDOWN.seconds(door, 0.5): return
		waited += 0.5
		if not is_instance_valid(pony) or not is_instance_valid(nav) or nav.command_owner != OWNER: return
		if arrived_at < 0.0:
			if nav.state in [nav.State.UNREACHABLE, nav.State.BLOCKED]: break
			if nav.state == nav.State.ARRIVED or pony.global_position.distance_to(spot) < 0.8: nav.stay(); arrived_at = waited
			# Getting up from lying down interrupts the walk: send her on again.
			elif nav.state == nav.State.IDLE and nav.get("_has_target") != true: nav.command_destination(spot, "walk")
		if arrived_at >= 0.0:
			if is_instance_valid(player): nav.face_point = player.global_position
			if waited - arrived_at >= WAIT_AT_DOOR or (is_instance_valid(player) and player.global_position.distance_to(spot) > 12.0): break
	if is_instance_valid(nav) and nav.command_owner == OWNER:
		nav.face_point = Vector3.INF
		nav.command_owner = previous.owner; nav.wander_enabled = previous.wander
