extends Node
## The walk-in Ponyville Schoolhouse, built into the Ponyville overhaul (2026-11-23). This is mitty's "Ponyville
## Schoolhouse" mod 0.1.0 (school.pck), merged with his permission and credited in the overhaul's changelog. His
## classroom, door, props, school day, lessons and jobs for Anon are as he made them; the overhaul adds:
## - holidays: no class when the overhaul's school routine has none (day_planner.gd school_day: weekends and the
##   Hearth's Warming holidays), so the classroom and the town agree;
## - any other foal (Anonfilly, a modded-in filly or colt) comes to class too, sitting at the back of the room
##   (BACK_SPOTS: the open floor between the last row of desks and the door wall, clear of the aisle and the door's
##   swing): the nine desks keep their fillies; a back-row foal lines up last and may answer Cheerilee's questions;
## - his standalone pack installed beside the overhaul: version 0.1.0 or older (this one) is stopped
##   (mods.gd _stop) and this copy runs; a newer one is left to run and this copy stands down
##   (_standalone_wins), so the two never build two classrooms or claim the same ponies.
## Attached by town_density.gd fill() with the town; its items (worksheets, globe, telescope) are the overhaul pack's
## data merges (mods/ponyville_overhaul/merge, from tools/town_planner/build/overhaul_merge), the same ids as his.
## The mod's state stays under his id ("schoolhouse", Mods.state), so a world moves between the two unchanged.
##
## mitty's notes follow.
##
## Ponyville Schoolhouse. The game's schoolhouse (RNL scenery "schoolhouse_01") is a solid shell; this
## mod swaps in the user's own building (M:/Home equestria projects/schoolhouse/building.glb, baked by
## tools/schoolhouse/bake.gd into models/), modelled in that scenery node's frame: a classroom with
## nine desks, Cheerilee's desk, the chalkboard, two long shelves (with the globe and the telescope),
## curtains, and a front door that swings in and stays as it was left (user 2026-11-18: open until
## somepony closes it). The shelves and her desk are dressed with props the game already has.
##
## School (user 2026-11-18): weekdays (Monday to Friday) from 9 to 15. From GATHER_AT the nine
## fillies walk to their desks (one Seat_* marker each) and Cheerilee to the front; they sit through
## the lesson and go back to their day at 3 pm. While Anon is in the classroom Cheerilee teaches out
## loud now and then (her AI, a topic of the day) and a filly may answer; and every few minutes she
## may ask him to help: hand out the worksheets (one onto every desk) or fetch the globe or telescope
## from the shelf to her desk (and later put it back). Anon does not sit at a desk.
## A pony with no body (Anon far away) has her essence parked at her seat, so she is there when he comes.

const MOD := "schoolhouse"
const MODELS := "res://world/towns/ponyville/schoolhouse/models/%s.scn"
const SCHOOL_PATH := "Zones/PonyvilleTown/RNLScenery/South/School/schoolhouse_01"

const ASKS := preload("res://world/mechanics/asks/asks.gd")
const FACTS := preload("res://world/mechanics/facts.gd")
const HAND_OVER := preload("res://world/mechanics/hand_over.gd")
const ITEM_CATALOG := preload("res://world/inventory/item_catalog.gd")
const ESSENCE := preload("res://world/life/essence.gd")
const LIFE_CORE := preload("res://world/life/living_world.gd")
const DEV := preload("res://world/dev_tools.gd")
const SFX := preload("res://world/audio/interaction_sounds.gd")
const PONY_SCHEDULE := preload("res://world/ai/pony_schedule.gd")
const PLANNER := preload("res://world/life/day/day_planner.gd")
const LOADER := preload("res://world/modding/mod_loader.gd")
## mitty's version merged here; his standalone pack at this version or older is stopped, a newer one runs instead.
const BUILT_ON := "0.1.0"
const STANDALONE := "schoolhouse"
## The back of the class (building frame): two blocks of four either side of the aisle, behind the last row of desks
## (z 1.4) and short of the door's swing (it opens in over x -1..1 to z 4.9), inside the shelves (x +-4.07). Foals
## that have no desk sit here, facing the board, in this order.
const BACK_SPOTS := [Vector3(-2.2, 0.79, 3.3), Vector3(2.2, 0.79, 3.3), Vector3(-3.4, 0.79, 3.3), Vector3(3.4, 0.79, 3.3),
	Vector3(-2.2, 0.79, 4.6), Vector3(2.2, 0.79, 4.6), Vector3(-3.4, 0.79, 4.6), Vector3(3.4, 0.79, 4.6)]
## Never in the class, whatever their identity says.
const NOT_PUPILS := ["spike"]

const TEACHER := "cheerilee"
## Seat markers in the building (Seat_R<row>C<column>; row 3 is nearest the board) -> filly.
const SEATS := {
	"Seat_R3C1": "apple_bloom", "Seat_R3C2": "sweetie_belle", "Seat_R3C3": "scootaloo",
	"Seat_R2C1": "diamond_tiara", "Seat_R2C2": "silver_spoon", "Seat_R2C3": "dinky_doo",
	"Seat_R1C1": "ruby_pinch", "Seat_R1C2": "archer", "Seat_R1C3": "noi",
}
const DESKS := {
	"Seat_R1C1": "SchoolDesk_R1C1", "Seat_R1C2": "SchoolDesk_R1C2", "Seat_R1C3": "SchoolDesk_R1C3",
	"Seat_R2C1": "SchoolDesk_R2C1", "Seat_R2C2": "SchoolDesk_R2C2", "Seat_R2C3": "SchoolDesk_R2C3",
	"Seat_R3C1": "SchoolDesk_R3C1", "Seat_R3C2": "SchoolDesk_R3C2", "Seat_R3C3": "SchoolDesk_R3C3",
}

## In the building's frame (tools/schoolhouse/probe_inside.gd): floor y 0.79, walls x +-4.88,
## chalkboard wall z -7.99, front wall (door) z 6.78; the class faces -Z.
const FLOOR_Y := 0.79
const ROOM := AABB(Vector3(-4.88, 0.3, -7.99), Vector3(9.76, 4.5, 14.77))
const BOARD_LOOK := Vector3(0.0, 1.6, -7.4)
var TEACH_AT := Vector3(-1.45, FLOOR_Y, -4.9)          # the user's TeacherSpot marker replaces these (_read_markers)
var TEACH_LOOK := Vector3(0.0, 1.0, 1.0)
const DESK_TOP := 1.55                                 # desks' and shelves' tops
const STUDENT_DESK_TOP := 1.53
## The door (models/door.scn, origin on the hinge, the leaf along -X); it swings in (toward -Z).
var DOOR_HINGE := Vector3(0.6735, 0.7939, 6.7887)
var DOOR_SIZE := Vector3(1.9, 2.44, 0.08)        # x from the DoorHinge marker's leaf_size
const DOOR_LIFT := 0.37
const DOOR_OPEN := -PI * 0.5
const DOOR_SPEED := 2.2                                # rad/s
const DOOR_AUTO := 2.6                                 # a class pony this near the door is "at" it
const ANON_DOOR_RESPECT := 60.0                       # after Anon works the door, the class leaves it this long
const LEAVING_FOR := 120.0                            # after class the door is kept for the leavers at most this long
## Where things sit (building frame): their shelf homes (the user's spots), Cheerilee's desk.
const HOMES := {"globe": Vector3(-4.4877, 1.551, -4.6203), "telescope": Vector3(4.2773, 1.542, 0.4766)}
const HOME_YAW := {"globe": 0.0, "telescope": 0.0}
var ON_DESK := {"globe": Vector3(-0.22, DESK_TOP, -5.25), "telescope": Vector3(-0.22, DESK_TOP, -5.22)}
var PAPERS_AT := Vector3(0.35, DESK_TOP, -4.98)
var DOOR_OUTSIDE := Vector3(0.0, 0.19, 10.785)      # the user's DoorOutside marker: where the class lines up
const ITEMS := {"papers": "food:schoolhouse-worksheets", "globe": "food:schoolhouse-globe", "telescope": "food:schoolhouse-telescope"}
const THING_NAMES := {"globe": "globe", "telescope": "telescope"}

## Decorations: game props (not the mods'), [path, building-frame position, yaw degrees]. The book
## rows (Fluttershy's cottage) show their spines toward +X: turned 180 on the +X shelf.
const DECOR := [
	["res://world/buildings/fluttershy/interior/book_row_wide_1.glb", Vector3(4.44, DESK_TOP, -5.6), 180.0],
	["res://world/buildings/fluttershy/interior/book_row_small_1.glb", Vector3(4.44, DESK_TOP, -3.8), 180.0],
	["res://world/props/lamps/kit/table_lamp.glb", Vector3(4.42, DESK_TOP, -2.2), 0.0],
	["res://world/buildings/fluttershy/interior/book_row_wide_2.glb", Vector3(4.44, DESK_TOP, 2.6), 180.0],
	["res://world/buildings/fluttershy/interior/book_row_small_2.glb", Vector3(4.44, DESK_TOP, 4.6), 180.0],
	["res://world/buildings/fluttershy/interior/small_frame.glb", Vector3(4.5, DESK_TOP, 5.8), 180.0],
	["res://world/buildings/fluttershy/interior/book_row_small_2.glb", Vector3(-4.42, DESK_TOP, -2.9), 0.0],
	["res://world/buildings/fluttershy/interior/book_row_wide_2.glb", Vector3(-4.42, DESK_TOP, -1.0), 0.0],
	["res://world/buildings/fluttershy/interior/small_frame.glb", Vector3(-4.5, DESK_TOP, 0.7), 0.0],
	["res://world/buildings/fluttershy/interior/book_row_wide_1.glb", Vector3(-4.42, DESK_TOP, 2.6), 0.0],
	["res://world/buildings/fluttershy/interior/book_row_small_1.glb", Vector3(-4.42, DESK_TOP, 4.4), 0.0],
	["res://world/props/lamps/kit/table_lamp.glb", Vector3(-4.45, DESK_TOP, 5.8), 0.0],
	["res://world/props/food/red-apple.glb", Vector3(0.74, DESK_TOP, -4.9), 20.0],
]

## The school day: weekdays (pony_schedule.gd DAYS: day 0 is Sunday) 9 to 15.
const GATHER_AT := 8.0             # user 2026-11-18: they set off at 8 to be in by 9
const LATE_AT := 9.5               # anypony not in her place by 9:30 is put there
const CLASS_FROM := 9.0
const CLASS_TO := 15.0         # user 2026-11-18: 9 to 3
const ARRIVED := 0.45
const ROUTE_RETRY := 10.0
const STUCK_AFTER := 30.0           # not moving this long on the way: a fresh route, or put at her place unseen
const LINE_WAIT := 30.0             # the longest she waits outside for the ones sitting further in
const ANON_FAR := 30.0
const OWNER := "schoolhouse:"
const ENCOUNTER := "schoolhouse:class:%d"
## Free to take from these (day_runner.gd _free, her schedule's steps, idle chats).
const FREE_OWNERS := ["day:", "life:", "social:", "chat:", "rest_after_command"]

## Lessons while Anon is in the room.
const LESSON_MIN := 100.0
const LESSON_MAX := 170.0
const ANSWER_CHANCE := 0.5
const TOPICS := [
	"adding and taking away, counted in apples", "spelling words with silent letters", "how pegasi make the weather and the water cycle",
	"the four seasons and Winter Wrap Up", "the map of Equestria: Canterlot, Cloudsdale, Manehattan and Ponyville", "the stars and the constellations",
	"rhyming and writing a short poem", "how seeds grow into plants", "good manners and being a good friend",
	"Hearth's Warming and how the three pony tribes came together", "telling the time on a clock", "the animals of the Everfree Forest, from a safe distance",
	"multiplying with bundles of carrots", "the parts of a letter and how to write one",
]
## Jobs for Anon while he is in the room: the first after FIRST_JOB, then JOB_GAP apart, at most JOBS_A_DAY.
const FIRST_JOB := Vector2(60.0, 120.0)
const JOB_GAP := Vector2(240.0, 420.0)
const RETURN_AFTER := Vector2(150.0, 300.0)
const JOBS_A_DAY := 3

const REACH := 2.8                  # desktop, camera to a thing
const AIM := 0.3
const DOOR_AIM := 0.7
const VR_REACH := 0.35

var inventory: Node
var _game: Node
var _school: Node3D                 # the game's scenery node (our frame)
var _root: Node3D                   # everything of ours, under it
var _door: AnimatableBody3D
var _door_angle := 0.0
var _door_settled := true
var _things := {}                   # "globe"/"telescope" -> Node3D
var _papers: Node3D
var _sheets := {}                   # seat -> Node3D
var _seats := {}                    # seat -> Vector3 (building frame)
var _members := {}                  # id -> {"since": clock, "lie_after": float}
var _retry := 0.0
var _clock := 0.0
var _lesson_at := -1.0
var _job_at := -1.0
var _was_in_room := false
var _renav_box := AABB()
var _renav_left := 0
var _debug_press := false
var _debug_class := false
var _anon_door_at := -1000.0
var _class_opened := false          # the class opened the door (and shuts it after the last one)
var _leavers: Array = []
var _leaving_until := -1.0
var _extras: Array = []             # foals with no desk, in class today, in BACK_SPOTS order


func _ready() -> void:
	if _standalone_wins():
		print("[schoolhouse] a newer Ponyville Schoolhouse pack is installed: it runs, the overhaul's copy stands down")
		queue_free()
		return
	if Mods.is_active(STANDALONE) and Mods.has_node(NodePath(STANDALONE)) and Mods.has_method("_stop"):
		Mods.call("_stop", STANDALONE)
		print("[schoolhouse] the Ponyville Schoolhouse pack (%s) is built into the overhaul: its own copy is stopped" % BUILT_ON)
	add_to_group("grab_providers")
	add_to_group("interaction_hint_sources")
	add_to_group("pony_prompt_notes")
	Mods.world_ready.connect(_on_world)
	Mods.world_closed.connect(_on_closed)
	set_physics_process(false)
	if Mods.game != null: _on_world(Mods.game)


func _on_world(game: Node) -> void:
	_clear()
	_game = game
	inventory = game.get("inventory") as Node
	_retry = 0.0
	set_physics_process(true)


func _on_closed(_game_node: Node) -> void:
	_clear()
	_game = null
	inventory = null
	set_physics_process(false)


func _exit_tree() -> void:
	_clear()


func _clear() -> void:
	_release_all()
	if is_instance_valid(_school):
		var mesh := _school.get_node_or_null("Mesh1") as Node3D
		if mesh != null: mesh.visible = true
		_game_solid(true)
	if is_instance_valid(_root): _root.queue_free()
	_root = null
	_school = null
	_door = null
	_things = {}
	_papers = null
	_sheets = {}
	_seats = {}


func _state() -> Dictionary:
	return Mods.state(MOD)


# --- per tick ---------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_game) or not _game.is_inside_tree(): return
	if _game.get_node_or_null("LoadingCover") != null: return
	_clock += delta
	_move_door(delta)
	_vr_place()
	_retry -= delta
	if _retry > 0.0: return
	_retry = 1.0
	if not _find_school(): return
	_keep_game_shell_hidden()
	_keep_sign()
	_renav()
	var phase := _phase()
	_keep_door(phase)
	if phase.is_empty():
		if not _members.is_empty() or _state().has("class_day"): _end_class()
	else:
		_keep_class(phase)
	_keep_things()
	_reconcile_carried()
	_keep_lessons_and_jobs(phase)


func _hours() -> float:
	return float(FACTS.clock().hours)


func _today() -> int:
	return int(FACTS.clock().day)


## "" (no school now), "gather" (on the way) or "class".
func _phase() -> String:
	if _debug_class: return "class"
	if not _school_day(): return ""
	var h := _hours()
	if h >= CLASS_FROM and h < CLASS_TO: return "class"
	if h >= GATHER_AT and h < CLASS_FROM: return "gather"
	return ""


## The game's own weekday (world/ai/pony_schedule.gd day_name: day 0 is a Sunday); school Monday-Friday.
func _day_name() -> String:
	return PONY_SCHEDULE.day_name()


func _school_day() -> bool:
	# The overhaul's school days (day_planner.gd): Monday to Friday, not in the Hearth's Warming holidays.
	var events: Array = []
	var calendar: Node = get_tree().get_first_node_in_group("town_calendar") if is_inside_tree() else null
	if calendar != null and calendar.has_method("today_events"):
		for event: Variant in calendar.call("today_events"):
			if event is Dictionary: events.append(str((event as Dictionary).get("id", "")))
	return PLANNER.school_day(_today(), events)


## A newer copy of mitty's own pack is installed and switched on: it runs instead of this one.
static func _standalone_wins() -> bool:
	var mods: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Mods")
	if mods == null or not bool(mods.call("is_active", STANDALONE)): return false
	for mod: Variant in mods.call("list"):
		if mod is Dictionary and str((mod as Dictionary).get("id", "")) == STANDALONE:
			return LOADER.version_older(BUILT_ON, str((mod as Dictionary).get("version", "")))
	return false


# --- the sign by the door (user 2026-11-18: the game shows no weekday) ------------------------------

const SIGN_AT := Vector3(1.75, 2.15, 6.97)       # building frame: on the front wall, right of the door
const SIGN_SIZE := Vector2(1.0, 0.5)
var _sign: Label3D
var _sign_text := ""


func _build_sign() -> void:
	var board := MeshInstance3D.new()
	board.name = "SchoolSign"
	var quad := QuadMesh.new()
	quad.size = SIGN_SIZE
	board.mesh = quad
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.2, 0.33, 0.24)        # chalkboard green
	paint.roughness = 0.9
	board.material_override = paint
	board.position = SIGN_AT
	_root.add_child(board)
	var frame := MeshInstance3D.new()
	var frame_quad := QuadMesh.new()
	frame_quad.size = SIGN_SIZE + Vector2(0.08, 0.08)
	frame.mesh = frame_quad
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.36, 0.2)
	frame.material_override = wood
	frame.position = Vector3(0.0, 0.0, -0.005)
	board.add_child(frame)
	_sign = Label3D.new()
	_sign.position = Vector3(0.0, 0.0, 0.006)
	_sign.pixel_size = 0.0022
	_sign.font_size = 48
	_sign.outline_size = 0
	_sign.modulate = Color(0.96, 0.96, 0.92)
	_sign.width = SIGN_SIZE.x / _sign.pixel_size - 30.0
	_sign.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sign.double_sided = false
	board.add_child(_sign)
	_sign_text = ""
	_keep_sign()


func _keep_sign() -> void:
	if not is_instance_valid(_sign): return
	var day := _day_name()
	var text := ""
	if not _school_day():
		text = "%s\nNo school today\nBack on Monday!" % day
	elif _hours() < CLASS_TO:
		text = "%s\nSchool today\n9 to 3" % day
	else:
		text = "%s\nSchool's out!\n%s" % [day, "See you Monday!" if posmod(_today(), 7) == 5 else "See you tomorrow!"]
	if text == _sign_text: return
	_sign_text = text
	_sign.text = text


# --- the building ------------------------------------------------------------------------------------

func _find_school() -> bool:
	if is_instance_valid(_root) and _root.is_inside_tree(): return true
	_clear()
	var found := _game.get_node_or_null(SCHOOL_PATH) as Node3D
	if found == null or not found.is_inside_tree(): return false
	_school = found
	_root = Node3D.new()
	_root.name = "SchoolInterior"
	_school.add_child(_root)
	var building: Node3D = (load(MODELS % "building") as PackedScene).instantiate()
	building.name = "Building"
	_root.add_child(building)
	for seat: String in SEATS:
		var marker := building.get_node_or_null(seat) as Node3D
		if marker != null: _seats[seat] = marker.position
	_read_markers(building)
	# Small furniture is not drawn from afar.
	for node: Node in building.get_children():
		if node is MeshInstance3D and str(node.name) != "SchoolhouseShell":
			(node as MeshInstance3D).visibility_range_end = 70.0
	_build_door()
	_build_decor()
	_build_sign()
	for thing: String in HOMES:
		var piece: Node3D = (load(MODELS % thing) as PackedScene).instantiate()
		piece.name = thing.capitalize()
		_root.add_child(piece)
		_things[thing] = piece
	_papers = (load(MODELS % "papers") as PackedScene).instantiate()
	_papers.name = "Worksheets"
	_root.add_child(_papers)
	var sheet_scene := load(MODELS % "sheet") as PackedScene
	for seat: String in DESKS:
		var desk := building.get_node_or_null(DESKS[seat]) as Node3D
		if desk == null: continue
		var sheet: Node3D = sheet_scene.instantiate()
		sheet.name = "Sheet_" + seat
		sheet.position = Vector3(desk.position.x, STUDENT_DESK_TOP, desk.position.z)
		# The user's marker on top of the desk (user 2026-11-18), if there is one: any marker but the
		# seat named for that desk's row and column ("R1C1"), e.g. "Paper_R1C1".
		var cell := seat.trim_prefix("Seat_")
		for marker: Node in building.get_children():
			if marker is Marker3D and str(marker.name).contains(cell) and not str(marker.name).begins_with("Seat_"):
				sheet.transform = Transform3D((marker as Node3D).basis.orthonormalized(), (marker as Node3D).position)    # the desk top slopes
		sheet.basis = sheet.basis * Basis(Vector3.UP, randf_range(-0.12, 0.12))
		sheet.visible = false
		_root.add_child(sheet)
		_sheets[seat] = sheet
	_keep_game_shell_hidden()
	_keep_sign()
	_renav_box = AABB(Vector3(-6.2, -1.0, -10.2), Vector3(12.4, 8.0, 20.4))
	_renav_left = 100000     # until a grid takes it (it may still be baking when the town loads)
	_keep_things()
	print("[schoolhouse] the schoolhouse has its classroom")
	return true


## The user's markers in the building (user 2026-11-18): where Cheerilee stands and which way she
## faces, where the globe, telescope and worksheets go on her desk, and the door's hinge and size.
func _read_markers(building: Node3D) -> void:
	var spot := building.get_node_or_null("TeacherSpot") as Node3D
	if spot != null:
		TEACH_AT = spot.position
		var forward := -spot.transform.basis.z
		forward.y = 0.0
		TEACH_LOOK = spot.position + forward.normalized() * 3.0 + Vector3.UP * 0.6
	for thing: String in ["globe", "telescope"]:
		var marker := building.get_node_or_null(thing.capitalize() + "OnDesk") as Node3D
		if marker != null: ON_DESK[thing] = marker.position
	var papers := building.get_node_or_null("PapersOnDesk") as Node3D
	if papers != null: PAPERS_AT = papers.position
	var outside := building.get_node_or_null("DoorOutside") as Node3D
	if outside != null: DOOR_OUTSIDE = outside.position
	var hinge := building.get_node_or_null("DoorHinge") as Node3D
	if hinge != null:
		DOOR_HINGE = hinge.position
		var leaf: Variant = hinge.get_meta("leaf_size", null)
		if leaf is Vector3: DOOR_SIZE.x = (leaf as Vector3).x


## The game's own shell stops drawing and its five solid boxes (which fill the inside) switch off.
func _keep_game_shell_hidden() -> void:
	var mesh := _school.get_node_or_null("Mesh1") as Node3D
	if mesh != null and mesh.visible: mesh.visible = false
	_game_solid(false)


func _game_solid(on: bool) -> void:
	var solid := _school.get_node_or_null("Solid") as StaticBody3D
	if solid == null: return
	for shape: Node in solid.get_children():
		if shape is CollisionShape3D and (shape as CollisionShape3D).disabled == on:
			(shape as CollisionShape3D).set_deferred("disabled", not on)


func _build_door() -> void:
	_door = AnimatableBody3D.new()
	_door.name = "Door"
	_door.sync_to_physics = true
	_door.position = DOOR_HINGE
	_root.add_child(_door)
	var leaf: Node3D = (load(MODELS % "door") as PackedScene).instantiate()
	_door.add_child(leaf)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# From DOOR_LIFT up: the walk grid's wall probe (14-34 cm above the floor) must not see the leaf, or
	# the doorway beside it reads too narrow (the bake cuts the frame the same way).
	box.size = Vector3(DOOR_SIZE.x, DOOR_SIZE.y - DOOR_LIFT, DOOR_SIZE.z)
	shape.shape = box
	shape.position = Vector3(-DOOR_SIZE.x * 0.5, DOOR_LIFT + (DOOR_SIZE.y - DOOR_LIFT) * 0.5, 0.0)
	_door.add_child(shape)
	_door_angle = DOOR_OPEN if bool(_state().get("door_open", false)) else 0.0
	_door.rotation.y = _door_angle


func _build_decor() -> void:
	var decor := Node3D.new()
	decor.name = "Decor"
	_root.add_child(decor)
	for row: Array in DECOR:
		var scene := load(str(row[0])) as PackedScene
		if scene == null: continue
		var piece: Node3D = scene.instantiate()
		piece.position = row[1]
		piece.rotation.y = deg_to_rad(float(row[2]))
		decor.add_child(piece)
		for mi: Node in piece.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visibility_range_end = 50.0
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The ponies' walk grid re-reads the ground in and around the schoolhouse (it has the old solid
## boxes cached, and may not be ready when the building goes in: tried until a grid takes it).
func _renav() -> void:
	if _renav_left <= 0 or _renav_box.size == Vector3.ZERO: return
	_renav_left -= 1
	var box := _school.global_transform * _renav_box
	for service: Node in get_tree().get_nodes_in_group("pony_navigation"):
		if not service.has_method("notify_geometry_changed") or not bool(service.get("ready_for_paths")): continue
		var bounds: Variant = service.get("bounds")
		if not bounds is AABB or not (bounds as AABB).intersects(box): continue
		service.call("notify_geometry_changed", box)
		_renav_left = 0
		print("[schoolhouse] walk grid told to re-read the schoolhouse")


# --- the door ----------------------------------------------------------------------------------------

func _door_open() -> bool:
	return bool(_state().get("door_open", false))


func set_door(open: bool) -> void:
	if _door_open() == open: return
	_state()["door_open"] = open
	Mods.save_changed()
	_door_settled = false
	if is_instance_valid(_door) and _door.is_inside_tree(): SFX.play_at(_door, "prop_door_open" if open else "prop_door_close", _door_point())


## Anon opens or shuts it: the class leaves it as he left it for ANON_DOOR_RESPECT seconds (unless
## one of them is standing right at it and has to get through).
func toggle_door() -> bool:
	set_door(not _door_open())
	_anon_door_at = _clock
	_class_opened = false
	return true


func _move_door(delta: float) -> void:
	if not is_instance_valid(_door): return
	var target := DOOR_OPEN if _door_open() else 0.0
	if is_equal_approx(_door_angle, target):
		if not _door_settled:
			_door_settled = true
			# The doorway changed: the walk grid looks again (the leaf only).
			var door_box := AABB(DOOR_HINGE + Vector3(-1.6, -0.2, -1.6), Vector3(2.0, 2.8, 3.2))
			_renav_box = _renav_box.merge(door_box) if _renav_left > 0 else door_box
			_renav_left = maxi(_renav_left, 600)
		return
	_door_angle = move_toward(_door_angle, target, DOOR_SPEED * delta)
	_door.rotation.y = _door_angle


func _door_point() -> Vector3:
	if not is_instance_valid(_door): return Vector3.INF
	return _door.to_global(Vector3(-DOOR_SIZE.x * 0.5, 1.15, 0.0))


## The door and the class (user 2026-11-18: it stayed open all day and sprang open again when shut).
## While somepony of the class has to get through (in before class, out after it) the door is opened
## for her (her route needs the doorway: the walk grid sees a shut leaf as a wall); once the last of
## them is through and clear of it, it is shut behind them. Otherwise it stays as it is.
func _keep_door(phase: String) -> void:
	if not is_instance_valid(_school): return
	var ids: Array = _members.keys() if not phase.is_empty() else (_leavers if _clock < _leaving_until else [])
	var middle := _school.to_global(DOOR_HINGE + Vector3(-DOOR_SIZE.x * 0.5, 0.0, 0.0))
	var needs := false
	var at_door := false
	for id: String in ids:
		var actor := _live(id)
		if actor == null: continue
		var inside := ROOM.has_point(_school.to_local(actor.global_position))
		var close := Vector2(actor.global_position.x - middle.x, actor.global_position.z - middle.z).length() < DOOR_AUTO
		var coming := not phase.is_empty() and not inside and not bool((_members[id] as Dictionary).get("arrived", false))
		var going := phase.is_empty() and inside
		if coming or going:
			needs = true
			if close: at_door = true
		elif close:
			at_door = true          # just through: not shut on her
	if needs and not _door_open():
		if at_door or _clock - _anon_door_at > ANON_DOOR_RESPECT:
			set_door(true)
			_class_opened = true
			print("[schoolhouse] the door is opened for the class")
	elif not needs and not at_door and _door_open() and _class_opened:
		set_door(false)
		_class_opened = false
		print("[schoolhouse] the last one through shuts the door")


# --- the class ---------------------------------------------------------------------------------------

func _class_ids() -> Array:
	var ids: Array = [TEACHER]
	ids.append_array(SEATS.values())
	ids.append_array(_extras)
	return ids


## Foals in the town today with no desk of their own (Anonfilly, modded-in fillies and colts): they join the class at
## the back, as many as there are BACK_SPOTS, in the order they are first seen.
func _gather_extras() -> void:
	if _extras.size() >= BACK_SPOTS.size(): return
	var population: Variant = _game.get("population") if is_instance_valid(_game) else null
	var live: Variant = (population as Node).get("live") if is_instance_valid(population) else null
	if not live is Dictionary: return
	var seated: Array = SEATS.values()
	for id: String in (live as Dictionary).keys():
		if _extras.size() >= BACK_SPOTS.size(): return
		if id == TEACHER or id in seated or id in NOT_PUPILS or id in _extras: continue
		var actor := _live(id)
		if actor == null or str(actor.name) == "PlayerPony": continue
		var identity: Variant = actor.get("identity")
		if identity == null or not bool((identity as Object).get("filly")): continue
		_extras.append(id)
		print("[schoolhouse] %s joins the class at the back" % id)


func _spot_of(id: String) -> Vector3:
	if id == TEACHER: return TEACH_AT
	for seat: String in SEATS:
		if SEATS[seat] == id and _seats.has(seat): return _seats[seat]
	var back := _extras.find(id)
	if back >= 0 and back < BACK_SPOTS.size(): return BACK_SPOTS[back]
	return Vector3.INF


func _keep_class(phase: String) -> void:
	var state := _state()
	if int(state.get("class_day", -1)) != _today():
		state["class_day"] = _today()
		state["jobs_done"] = 0
		state.erase("job")
		state.erase("return_at")
		state["topics"] = [TOPICS[posmod(_today() * 7, TOPICS.size())], TOPICS[posmod(_today() * 7 + 5, TOPICS.size())]]
		Mods.save_changed()
		_lesson_at = -1.0
		_job_at = -1.0
		_extras.clear()
		print("[schoolhouse] school day: %s" % ", ".join(PackedStringArray(state.topics)))
	_gather_extras()
	_begin_encounter()
	for id: String in _class_ids():
		var spot := _spot_of(id)
		if not spot.is_finite(): continue
		var population: Variant = _game.get("population")
		if not is_instance_valid(population): return
		if ESSENCE.record(population, id).is_empty() and _live(id) == null: continue    # not in this world
		var actor := _live(id)
		if actor == null:
			_park_essence(id, _school.to_global(spot))
			continue
		_lift_pause(id)
		if not _members.has(id):
			if _busy(id, actor): continue
			_claim(id, actor)
		_keep_member(id, actor, _school.to_global(spot))


func _claim(id: String, actor: Node3D) -> void:
	var nav: Node = actor.get_node_or_null("Navigator")
	if nav == null: return
	nav.call("stay")
	nav.set("command_owner", OWNER + id)
	nav.set("wander_enabled", false)
	actor.set_meta("event_placed", true)
	_members[id] = {"since": _clock}
	print("[schoolhouse] %s heads to school" % id)


func _keep_member(id: String, actor: Node3D, spot: Vector3) -> void:
	var row: Dictionary = _members.get(id, {})
	if row.is_empty(): return
	var nav: Node = actor.get_node_or_null("Navigator")
	if nav == null: return
	var owner_now := str(nav.get("command_owner"))
	if not owner_now.begins_with(OWNER):
		# A conversation turned her to Anon, or she was taken: she comes back once it is over.
		if owner_now.is_empty() or owner_now.begins_with("ai:") or owner_now.begins_with("rest_after_command"):
			nav.call("stay")
			nav.set("command_owner", OWNER + id)
			nav.set("wander_enabled", false)
			_stand(id, actor)
		return
	var away := Vector2(actor.global_position.x - spot.x, actor.global_position.z - spot.z).length()
	var low := absf(actor.global_position.y - spot.y) > 1.2
	if away > ARRIVED or low:
		row.arrived = false
		_stand(id, actor)
		# User 2026-11-18: they set off at 8, should be in by 9; still not there at 9:30, she is put
		# in her place.
		if not _debug_class and _phase() == "class" and _hours() >= LATE_AT and not bool(row.get("been_in", false)):
			_put_at(actor, spot)
			return
		var outside :=not ROOM.has_point(_school.to_local(actor.global_position))
		# In line (headless test 2026-11-18: ponies seated first blocked the aisles for the rest):
		# outside, she waits by the steps until the ones sitting further in are in.
		if outside and not _my_turn(id, row):
			var wait_at := _school.to_global(_waiting_spot(id))
			if Vector2(actor.global_position.x - wait_at.x, actor.global_position.z - wait_at.z).length() > 0.8:
				if not bool(nav.get("_has_target")) or nav.get("target").distance_to(wait_at) > 0.5: nav.call("go_to", wait_at, 0)
			elif bool(nav.get("_has_target")): nav.call("stay")
			row.moved_at = _clock
			return
		if bool(row.get("waited", false)) and bool(nav.get("_has_target")) and nav.get("target").distance_to(spot) > 0.5: nav.call("stay")
		row.waited = false
		# Stuck (bumped into a classmate, a route that will not come): a fresh route; with Anon not
		# in the classroom to see it, she is simply put at her place.
		var last: Vector3 = row.get("last_pos", Vector3.INF)
		if not last.is_finite() or last.distance_to(actor.global_position) > 0.3:
			row.last_pos = actor.global_position
			row.moved_at = _clock
		elif _clock - float(row.get("moved_at", _clock)) > STUCK_AFTER:
			row.moved_at = _clock
			if not _anon_in_room() or _anon_distance(actor.global_position) > ANON_FAR:
				_put_at(actor, spot)
				return
			nav.call("stay")
		# A route that failed (planned before the grid knew the doorway, or the search gave up) is
		# asked for again now and then; the navigator itself does not retry.
		var failed := str(nav.get("reason")).contains("budget") or str(nav.get("reason")).to_lower().contains("no route")
		if failed and _clock - float(row.get("routed", -100.0)) > ROUTE_RETRY: nav.call("stay")
		if not bool(nav.get("_has_target")):
			nav.call("go_to", spot, 0)
			row.routed = _clock
		nav.set("face_point", Vector3.INF)
		return
	row.since = _clock
	row.arrived = true
	row.been_in = true
	if bool(nav.get("_has_target")): nav.call("stay")
	if id == TEACHER:
		nav.set("face_point", _school.to_global(TEACH_LOOK))
	else:
		var look := _school.to_global(BOARD_LOOK)
		nav.set("face_point", Vector3(look.x, actor.global_position.y + 0.6, look.z))
		_sit(id, actor)


## Who goes in first: Cheerilee (0), then the row by the board (1), the middle row (2), the row by
## the door (3).
func _rank(id: String) -> int:
	if id == TEACHER: return 0
	for seat: String in SEATS:
		if SEATS[seat] == id: return 4 - int(seat.substr(6, 1))      # "Seat_R3C1" -> row 3 -> 1
	if id in _extras: return 4                                       # the back of the class goes in last
	return 3


## Her turn to go in: everypony who sits further in is in (or not coming), or she has waited LINE_WAIT.
func _my_turn(id: String, row: Dictionary) -> bool:
	var rank := _rank(id)
	if rank == 0: return true
	if not row.has("wait_from"): row.wait_from = _clock
	if _clock - float(row.wait_from) > LINE_WAIT: return true
	for other: String in _members:
		if other == id or _rank(other) >= rank or _live(other) == null: continue
		if not bool((_members[other] as Dictionary).get("arrived", false)):
			row.waited = true
			return false
	return true


## Where she waits outside: a little crowd at the foot of the ramp (DoorOutside marker), by row and seat.
func _waiting_spot(id: String) -> Vector3:
	var column := 2
	for seat: String in SEATS:
		if SEATS[seat] == id: column = int(seat.substr(8, 1))
	if id in _extras: column = 1 + _extras.find(id) % 3
	return DOOR_OUTSIDE + Vector3((column - 2) * 1.1, 0.0, 0.8 + (_rank(id) - 1) * 1.0)


## Put straight at her spot (stuck on the way, nobody watching).
func _put_at(actor: Node3D, spot: Vector3) -> void:
	var pose := Transform3D(actor.global_basis, spot + Vector3.UP * 0.02)
	if actor.has_method("reset_motion"): actor.call("reset_motion", pose)   # pony_locomotion.gd: moves her and clears her motion
	else: actor.global_transform = pose
	var nav: Node = actor.get_node_or_null("Navigator")
	if nav != null: nav.call("stay")
	print("[schoolhouse] %s put at her place" % str(actor.name))


func _sit(id: String, actor: Node3D) -> void:
	if not actor.has_method("request_posture"): return
	var status: Dictionary = actor.call("posture_status") if actor.has_method("posture_status") else {}
	if str(status.get("requested", "")) != "sit": actor.call("request_posture", "sit")
	var posture: Variant = actor.get("posture")
	var row: Dictionary = _members[id]
	if posture is RefCounted and "lie_after_seconds" in posture and not row.has("lie_after"):
		row.lie_after = float(posture.lie_after_seconds)
		posture.lie_after_seconds = 1e9


func _stand(id: String, actor: Node3D) -> void:
	if not actor.has_method("posture_status"): return
	var status: Dictionary = actor.call("posture_status")
	if str(status.get("requested", "stand")) not in ["stand", ""]: actor.call("request_posture", "stand")


func _release(id: String) -> void:
	var row: Dictionary = _members.get(id, {})
	_members.erase(id)
	var actor := _live(id)
	_lift_pause(id)
	if actor == null: return
	if actor.has_meta("event_placed"): actor.remove_meta("event_placed")
	var posture: Variant = actor.get("posture")
	if row.has("lie_after") and posture is RefCounted and "lie_after_seconds" in posture:
		posture.lie_after_seconds = float(row.lie_after)
	if actor.has_method("request_posture"): actor.call("request_posture", "stand")
	var nav: Node = actor.get_node_or_null("Navigator")
	if nav != null and str(nav.get("command_owner")).begins_with(OWNER):
		nav.set("face_point", Vector3.INF)
		nav.call("stay")
		nav.set("command_owner", "")
		nav.set("wander_enabled", true)
	var schedule := actor.get_node_or_null("Schedule")
	if schedule != null and schedule.has_method("_apply"): schedule.call("_apply")


func _release_all() -> void:
	for id: String in _members.keys(): _release(id)
	if not is_instance_valid(_game): return
	for id: String in _class_ids(): _lift_pause(id)


## Three o'clock (or the mod's class switched off): everypony goes back to her day, the room is tidied.
func _end_class() -> void:
	_release_all()
	_end_encounter()
	var state := _state()
	state.erase("class_day")
	state.erase("job")
	state.erase("return_at")
	state.erase("sheets")
	state.erase("papers")
	state.erase("things")
	Mods.save_changed()
	# Out they go: _keep_door opens for them and shuts it after the last one.
	_leavers = _class_ids()
	_leaving_until = _clock + LEAVING_FOR
	_lesson_at = -1.0
	_job_at = -1.0
	print("[schoolhouse] class is over")


func _live(id: String) -> Node3D:
	var population: Variant = _game.get("population") if is_instance_valid(_game) else null
	if not is_instance_valid(population): return null
	var live: Variant = (population as Node).get("live")
	var row: Variant = (live as Dictionary).get(id) if live is Dictionary else null
	var actor: Variant = (row as Dictionary).get("actor") if row is Dictionary else null
	return actor as Node3D if is_instance_valid(actor) and actor is Node3D and (actor as Node3D).is_inside_tree() else null


func _park_essence(id: String, spot: Vector3) -> void:
	var population: Variant = _game.get("population")
	if not is_instance_valid(population) or not ESSENCE.unloaded(population, id): return
	var resident := ESSENCE.record(population, id)
	if resident.is_empty(): return
	var core: RefCounted = ESSENCE.core(population)
	var paused: Dictionary = _paused()
	var reason := "Teaching her class at the schoolhouse" if id == TEACHER else "In class at the schoolhouse"
	if not paused.has(id):
		ESSENCE.leave_outing(population, id, reason)
		if core != null and not bool(resident.get("paused", false)):
			core.pause_resident(id, true, reason)
			paused[id] = true
			Mods.save_changed()
	resident.position = LIFE_CORE.vector(spot)
	resident.last_reason = reason


func _paused() -> Dictionary:
	if not _state().get("paused") is Dictionary: _state()["paused"] = {}
	return _state().paused


func _lift_pause(id: String) -> void:
	var paused := _paused()
	if not paused.has(id): return
	paused.erase(id)
	Mods.save_changed()
	var core: RefCounted = ESSENCE.core(_game.get("population"))
	if core != null: core.pause_resident(id, false)


## Not now: someone else steers her (an event, a favour, bedtime), she sleeps, flies or talks with Anon.
func _busy(id: String, actor: Node3D) -> bool:
	var nav: Node = actor.get_node_or_null("Navigator")
	if nav == null: return true
	var owner_now := str(nav.get("command_owner"))
	if owner_now == "social:talk": return true
	if not owner_now.is_empty() and not owner_now.begins_with(OWNER):
		var routine := false
		for prefix: String in FREE_OWNERS:
			if owner_now.begins_with(prefix): routine = true
		if not routine: return true
	if bool(actor.get("sleeping")): return true
	if actor.has_meta("event_placed") or bool(actor.get_meta("balloon_passenger", false)): return true
	var flight: Variant = actor.get("flight")
	if flight is Object and is_instance_valid(flight) and bool((flight as Object).call("active")): return true
	var director: Variant = _game.get("director")
	if is_instance_valid(director) and str(director.get("_current")) == id and str(director.get("state")) != "idle": return true
	return false


## The class as a story the ponies' AI keeps to: they stay in class until three.
func _begin_encounter() -> void:
	var encounters: Variant = _game.get("encounters")
	if not is_instance_valid(encounters): return
	var key := ENCOUNTER % _today()
	if bool((encounters as Node).call("active", key)): return
	var movers := {}
	for id: String in _class_ids(): movers[id] = [OWNER]
	var knows := {}
	for id: String in _class_ids(): knows[id] = [_class_knows(id)]
	(encounters as Node).call("begin", key, {
		"title": "class at the schoolhouse", "place": "the Ponyville Schoolhouse",
		"participants": _class_ids(), "movers": movers, "hold": true, "knows": knows,
		"commitment": {TEACHER: "Teach your class until three in the afternoon."},
		"allowed": "School is in until three in the afternoon: you stay in the classroom. If Anon asks you to go somewhere or follow him, that waits until class is over.",
		"beats": []})


func _end_encounter() -> void:
	var encounters: Variant = _game.get("encounters") if is_instance_valid(_game) else null
	if is_instance_valid(encounters) and bool((encounters as Node).call("active", ENCOUNTER % _today())):
		(encounters as Node).call("complete", ENCOUNTER % _today())


func _class_knows(id: String) -> String:
	if id == TEACHER:
		return "It is a school day: you teach your class of fillies in the Ponyville Schoolhouse from nine until three in the afternoon (Apple Bloom, Sweetie Belle, Scootaloo, Diamond Tiara, Silver Spoon, Dinky Doo, Ruby Pinch, Archer and Noi). Anon may drop by: he can watch or lend a hoof when you ask, but he does not sit at a desk."
	return "It is a school day: you are in class at the Ponyville Schoolhouse until three in the afternoon, at your own desk, with Miss Cheerilee teaching. Anon may drop by and watch or help her."


# --- lessons and jobs (only while Anon is in the classroom) --------------------------------------------

func _anon_position() -> Vector3:
	var body: Variant = inventory.get("player_body") if is_instance_valid(inventory) else null
	return (body as Node3D).global_position if is_instance_valid(body) and body is Node3D else Vector3.INF


func _anon_distance(at: Vector3) -> float:
	var anon := _anon_position()
	return anon.distance_to(at) if anon.is_finite() else INF


func _anon_in_room() -> bool:
	var anon := _anon_position()
	return anon.is_finite() and is_instance_valid(_school) and ROOM.has_point(_school.to_local(anon))


func _teacher_teaching() -> bool:
	var actor := _live(TEACHER)
	if actor == null or not _members.has(TEACHER): return false
	return actor.global_position.distance_to(_school.to_global(TEACH_AT)) < 1.5


func _keep_lessons_and_jobs(phase: String) -> void:
	var in_room := phase == "class" and _anon_in_room() and _teacher_teaching()
	if in_room and not _was_in_room:
		if _lesson_at < 0.0: _lesson_at = _clock + randf_range(15.0, 35.0)
		if _job_at < 0.0: _job_at = _clock + randf_range(FIRST_JOB.x, FIRST_JOB.y)
	_was_in_room = in_room
	if not in_room: return
	if _clock >= _lesson_at:
		_lesson_at = _clock + randf_range(LESSON_MIN, LESSON_MAX)
		_teach()
	var state := _state()
	if state.has("job"): return
	if state.has("return_at") and _clock >= float(state.return_at):
		var thing := str(state.get("return_thing", ""))
		state.erase("return_at")
		if _thing_where(thing) == "desk": _ask("return", thing)
		return
	if state.has("return_at"): return
	if _clock < _job_at or int(state.get("jobs_done", 0)) >= JOBS_A_DAY: return
	_job_at = _clock + randf_range(JOB_GAP.x, JOB_GAP.y)
	if randf() < 0.5: _ask("papers", "")
	else: _ask("fetch", ["globe", "telescope"].pick_random())


func _topic() -> String:
	var topics: Variant = _state().get("topics")
	if not topics is Array or (topics as Array).size() < 2: return TOPICS[0]
	return str(topics[0] if _hours() < 12.0 else topics[1])


func _teach() -> void:
	var director: Node = _game.get("director") as Node
	if director == null or not director.has_method("queue_generated_intent"): return
	var key := "schoolhouse:lesson:%d" % Time.get_ticks_msec()
	# User 2026-11-18: nopony answered her questions (the answer was queued at random, alongside the
	# lesson, before she had asked anything). Now she always ends with a question, and once her line is
	# done a filly answers it, then she answers the filly.
	var purpose := "[Observed situation, not player speech] You are teaching your class of fillies at the schoolhouse; today's lesson is %s. Teach the next little bit of it out loud to the class: two or three short sentences, the way a kind schoolteacher explains things to young fillies, and end by asking the class one simple question about it." % _topic()
	director.call("queue_generated_intent", TEACHER, purpose, key, _in_class_with_anon, _answer.bind(key), true)


func _in_class_with_anon() -> bool:
	return _anon_in_room() and _phase() == "class"


## After Cheerilee's question: a filly in class raises her hoof and answers it.
func _answer(key: String) -> void:
	var director: Node = _game.get("director") as Node if is_instance_valid(_game) else null
	if director == null or not _in_class_with_anon(): return
	var pupils: Array = SEATS.values() + _extras
	var present: Array = pupils.filter(func(id: String) -> bool: return _members.has(id) and _live(id) != null)
	if present.is_empty(): return
	var filly: String = present.pick_random()
	var place := "at the back of the classroom" if filly in _extras else "at your desk"
	var words := "[Observed situation, not player speech] You are sitting " + place + " in class at the schoolhouse. Miss Cheerilee is teaching about %s and has just said to the class: \"%s\" Raise your hoof and answer her question, in one short sentence, the way you would in class; your answer may be right or a little bit wrong, as fits you." % [_topic(), _heard(key)]
	director.call("queue_generated_intent", filly, words, key + ":answer", _in_class_with_anon, _reply.bind(key, filly), true)
	print("[schoolhouse] %s answers Cheerilee's question" % filly)


## The sentences of a delivered line (the director keeps them with the queued purpose, "heard").
func _heard(key: String) -> String:
	var director: Node = _game.get("director") as Node if is_instance_valid(_game) else null
	var lines: Variant = director.get("_authored_lines") if director != null else null
	var row: Variant = (lines as Dictionary).get(key) if lines is Dictionary else null
	var heard: Variant = (row as Dictionary).get("heard") if row is Dictionary else null
	return " ".join(PackedStringArray(heard as Array)).replace("\"", "'").left(500) if heard is Array else ""


## And Cheerilee answers the filly.
func _reply(key: String, filly: String) -> void:
	var director: Node = _game.get("director") as Node if is_instance_valid(_game) else null
	if director == null or not _in_class_with_anon(): return
	var words := "[Observed situation, not player speech] %s just answered the question you asked your class: \"%s\" Reply to her in one short sentence like a kind teacher: praise her if she is right, gently correct her if not." % [_pony_name(filly), _heard(key + ":answer")]
	director.call("queue_generated_intent", TEACHER, words, key + ":reply", _in_class_with_anon, Callable(), true)


const ASK_WORDS := {
	"papers": "Anon is visiting your classroom. Turn to him and ask him, nicely, to help you hand out today's worksheets: the stack is on your desk, and one goes on each filly's desk. One or two sentences.",
	"fetch": "Anon is visiting your classroom. Turn to him and ask him, nicely, to bring you the %s from the shelf by the window and set it on your desk, for the lesson. One or two sentences.",
	"return": "Anon is visiting your classroom. You are done with the %s on your desk: ask him, nicely, to put it back on its shelf by the window. One or two sentences.",
}
const THANKS_WORDS := {
	"papers": "Anon just put a worksheet on every filly's desk for you. Thank him warmly, in one sentence, and tell the class they may begin.",
	"fetch": "Anon just brought the %s from the shelf to your desk. Thank him in one sentence and use it in your lesson.",
	"return": "Anon just put the %s back on its shelf. Thank him in one sentence.",
}


func _ask(kind: String, thing: String) -> void:
	_state()["job"] = {"kind": kind, "thing": thing}
	if kind == "papers":
		_state()["papers"] = "desk"
		_state()["sheets"] = {}
	Mods.save_changed()
	_keep_things()
	print("[schoolhouse] Cheerilee asks Anon: %s %s" % [kind, thing])
	_say(ASK_WORDS[kind] if kind == "papers" else ASK_WORDS[kind] % THING_NAMES.get(thing, thing), "ask")


func _job_done(kind: String, thing: String) -> void:
	var state := _state()
	state.erase("job")
	if kind != "return": state["jobs_done"] = int(state.get("jobs_done", 0)) + 1
	if kind == "fetch":
		state["return_at"] = _clock + randf_range(RETURN_AFTER.x, RETURN_AFTER.y)
		state["return_thing"] = thing
	Mods.save_changed()
	print("[schoolhouse] job done: %s %s" % [kind, thing])
	_say(THANKS_WORDS[kind] if kind == "papers" else THANKS_WORDS[kind] % THING_NAMES.get(thing, thing), "thanks")


func _say(words: String, tag: String) -> void:
	var director: Node = _game.get("director") as Node
	if director == null or not director.has_method("queue_generated_intent"): return
	var key := "schoolhouse:%s:%d" % [tag, Time.get_ticks_msec()]
	director.call("queue_generated_intent", TEACHER, words, key, func() -> bool: return _phase() == "class", Callable(), true)


# --- the things: worksheets, globe, telescope -----------------------------------------------------------

## "shelf" (home), "desk" (Cheerilee's) or "carried".
func _thing_where(thing: String) -> String:
	var things: Variant = _state().get("things")
	return str((things as Dictionary).get(thing, "shelf")) if things is Dictionary else "shelf"


func _set_thing(thing: String, where: String) -> void:
	if not _state().get("things") is Dictionary: _state()["things"] = {}
	_state().things[thing] = where
	Mods.save_changed()
	_keep_things()


func _sheets_down() -> Dictionary:
	if not _state().get("sheets") is Dictionary: _state()["sheets"] = {}
	return _state().sheets


func _keep_things() -> void:
	if not is_instance_valid(_root): return
	for thing: String in _things:
		var node := _things[thing] as Node3D
		var where := _thing_where(thing)
		node.visible = where != "carried"
		node.position = HOMES[thing] if where == "shelf" else ON_DESK[thing]
		node.rotation.y = HOME_YAW[thing]
	var papers := str(_state().get("papers", "none"))
	_papers.visible = papers == "desk"
	_papers.position = PAPERS_AT
	var down := _sheets_down()
	for seat: String in _sheets: (_sheets[seat] as Node3D).visible = down.has(seat)


## Things Anon carries that should not be with him (class over, or the job gone) go back where
## they belong; a carried one gone from his hands and briefcase goes back too.
func _reconcile_carried() -> void:
	if not is_instance_valid(inventory): return
	var owned := _owned()
	var in_class := not _phase().is_empty() and _state().has("class_day")
	for key: String in ITEMS:
		var id: String = ITEMS[key]
		var carried := (str(_state().get("papers", "none")) == "carried") if key == "papers" else _thing_where(key) == "carried"
		if not in_class:
			if owned.has(id): _take_away(id)
			continue
		if carried and not owned.has(id):
			if key == "papers": _state()["papers"] = "desk"
			else: _set_thing(key, "shelf")
			Mods.save_changed()
			_keep_things()
			print("[schoolhouse] the %s went missing from Anon; it is back in its place" % key)
		elif not carried and owned.has(id):
			_take_away(id)


func _owned() -> Dictionary:
	var out := {}
	var store: Variant = inventory.get("inventory")
	if store == null: return out
	for slot: Variant in store.get("slots"):
		if slot is Dictionary and not (slot as Dictionary).is_empty():
			var id := ITEM_CATALOG.canonical(str(slot.get("id", "")))
			if id in ITEMS.values(): out[id] = true
	for loan: Variant in (store.get("loans") as Dictionary).values():
		if not loan is Dictionary or bool((loan as Dictionary).get("equipped", false)): continue
		var id := ITEM_CATALOG.canonical(str(loan.get("id", "")))
		if id in ITEMS.values(): out[id] = true
	return out


func _take_away(id: String) -> void:
	var store: Variant = inventory.get("inventory")
	if store != null: store.call("discard", id)
	for side: String in ["desktop", "left", "right"]:
		var item := _held_item(side)
		if item != null and ITEM_CATALOG.canonical(str(item.get_meta("item_id", ""))) == id: _consume_held(side, item)


func _held_item(side: String) -> Node:
	if not is_instance_valid(inventory): return null
	var held: Variant = inventory.get("held")
	if not held is Dictionary or not (held as Dictionary).has(side): return null
	var item: Variant = held[side]
	return item as Node if is_instance_valid(item) else null


## "papers", "globe", "telescope" or "" for what that hand holds.
func _held_key(side: String) -> String:
	var item := _held_item(side)
	if item == null: return ""
	var id := ITEM_CATALOG.canonical(str(item.get_meta("item_id", "")))
	for key: String in ITEMS:
		if ITEMS[key] == id: return key
	return ""


func _consume_held(side: String, item: Node) -> bool:
	var token := str(item.get_meta("token", ""))
	var store: Variant = inventory.get("inventory")
	if store == null or not (store.get("loans") as Dictionary).has(token) or not bool(store.call("consume", token)): return false
	var held: Dictionary = inventory.get("held")
	held.erase(side)
	(inventory.get("loose") as Dictionary).erase(token)
	(inventory.get("_track") as Dictionary).erase(side)
	inventory.call("_claim", side, false)
	item.queue_free()
	inventory.call("_refresh_holding")
	return true


func _job() -> Dictionary:
	var job: Variant = _state().get("job")
	return job if job is Dictionary else {}


func _take(key: String, side: String) -> bool:
	if HAND_OVER.give_to_anon(inventory, ITEMS[key], side).is_empty(): return false
	if key == "papers": _state()["papers"] = "carried"
	else: _set_thing(key, "carried")
	Mods.save_changed()
	_keep_things()
	if inventory.has_method("_haptic"): inventory.call("_haptic", side)
	return true


func _put_sheet(seat: String, side: String) -> bool:
	var down := _sheets_down()
	if down.has(seat): return false
	down[seat] = true
	Mods.save_changed()
	if inventory.has_method("_haptic"): inventory.call("_haptic", side)
	if down.size() >= _sheets.size():
		var item := _held_item(side)
		if item != null: _consume_held(side, item)
		_state()["papers"] = "none"
		_job_done("papers", "")
	_keep_things()
	return true


## The carried thing goes on Cheerilee's desk ("desk") or back on its shelf ("shelf").
func _put_thing(thing: String, where: String, side: String) -> bool:
	var item := _held_item(side)
	if item == null or not _consume_held(side, item): return false
	_set_thing(thing, where)
	var job := _job()
	if where == "desk" and str(job.get("kind", "")) == "fetch" and str(job.get("thing", "")) == thing: _job_done("fetch", thing)
	elif where == "shelf" and str(job.get("kind", "")) == "return" and str(job.get("thing", "")) == thing: _job_done("return", thing)
	if where == "shelf" and str(_state().get("return_thing", "")) == thing:
		_state().erase("return_at")
		_state().erase("return_thing")
	return true


func _w(local: Vector3) -> Vector3:
	return _school.to_global(local)


func _thing_point(thing: String) -> Vector3:
	var node := _things.get(thing) as Node3D
	return node.global_position + Vector3.UP * 0.3 if is_instance_valid(node) else Vector3.INF


func _seat_desk_point(seat: String) -> Vector3:
	var sheet := _sheets.get(seat) as Node3D
	return sheet.global_position + Vector3.UP * 0.05 if is_instance_valid(sheet) else Vector3.INF


## What can be done now, with its aim point: [{"do", "point", "text", ...}].
func _actions(side: String) -> Array:
	var out: Array = []
	if not is_instance_valid(_root): return out
	out.append({"do": "door", "point": _door_point(), "aim": DOOR_AIM, "text": "Close the door" if _door_open() else "Open the door"})
	if _state().get("class_day", -1) == -1 or _phase().is_empty(): return out
	var held := _held_key(side)
	var job := _job()
	var kind := str(job.get("kind", ""))
	if held == "papers":
		var down := _sheets_down()
		for seat: String in _sheets:
			if not down.has(seat):
				out.append({"do": "sheet", "seat": seat, "point": _seat_desk_point(seat), "aim": AIM, "text": "Put a worksheet on %s's desk" % _pony_name(SEATS[seat])})
	elif held in HOMES:
		out.append({"do": "thing_desk", "thing": held, "point": _w(ON_DESK[held]) + Vector3.UP * 0.1, "aim": 0.45, "text": "Set the %s on Cheerilee's desk" % held})
		out.append({"do": "thing_shelf", "thing": held, "point": _w(HOMES[held]) + Vector3.UP * 0.2, "aim": 0.45, "text": "Put the %s back on the shelf" % held})
	elif held.is_empty():
		# Something else in that hand: the pick-up is shown, but says why it cannot be done.
		var full := _held_item(side) != null
		var hands := "Your hands are full · put down what you're holding to take the %s"
		if kind == "papers" and str(_state().get("papers", "none")) == "desk":
			out.append({"do": "full" if full else "take", "key": "papers", "point": _papers.global_position + Vector3.UP * 0.03, "aim": AIM,
				"text": hands % "worksheets" if full else "Take the worksheets"})
		for thing: String in HOMES:
			var where := _thing_where(thing)
			var asked := (kind == "fetch" and where == "shelf") or (kind == "return" and where == "desk")
			if asked and str(job.get("thing", "")) == thing:
				out.append({"do": "full" if full else "take", "key": thing, "point": _thing_point(thing), "aim": 0.4,
					"text": hands % thing if full else "Pick up the %s" % thing})
	return out


func _pony_name(id: String) -> String:
	var director: Variant = _game.get("director") if is_instance_valid(_game) else null
	var characters: Variant = director.get("characters") if is_instance_valid(director) else null
	if characters is Dictionary and (characters as Dictionary).has(id):
		var profile: Variant = ((characters as Dictionary)[id] as Dictionary).get("profile")
		if profile is Dictionary and (profile as Dictionary).has("name"): return str((profile as Dictionary).name)
	return id.replace("_", " ").capitalize()


func _do(action: Dictionary, side: String) -> bool:
	match str(action.get("do", "")):
		"door": return toggle_door()
		"take": return _take(str(action.key), side)
		"sheet": return _put_sheet(str(action.seat), side)
		"thing_desk": return _put_thing(str(action.thing), "desk", side)
		"thing_shelf": return _put_thing(str(action.thing), "shelf", side)
	return false


# --- desktop: look and click / E -----------------------------------------------------------------------

func _available() -> bool:
	if not is_instance_valid(inventory) or not is_instance_valid(_root): return false
	if _debug_press: return true
	var body: Variant = inventory.get("player_body")
	if not is_instance_valid(body) or bool((body as Node).get("controls_locked")): return false
	if inventory.has_method("_quick_blocked") and bool(inventory.call("_quick_blocked")): return false
	return true


func _aim_miss(point: Vector3, reach: float) -> float:
	var camera: Camera3D = inventory.get("camera") as Camera3D
	if camera == null or not point.is_finite(): return INF
	var forward := -camera.global_basis.z
	var to := point - camera.global_position
	var along := to.dot(forward)
	if along <= 0.0 or to.length() > reach: return INF
	return (to - forward * along).length()


func _desktop_action() -> Dictionary:
	if not _available() or not bool(inventory.get("_desktop")): return {}
	var best := {}
	var best_miss := INF
	for action: Dictionary in _actions("desktop"):
		var miss := _aim_miss(action.point, REACH)
		if miss < float(action.aim) and miss < best_miss:
			best = action
			best_miss = miss
	return best


func interaction_hint() -> Dictionary:
	if not is_instance_valid(inventory) or not bool(inventory.get("_desktop")): return {}
	var action := _desktop_action()
	if action.is_empty(): return {}
	var target: Node = _door if str(action.do) == "door" else _root
	return {"target": target, "point": action.point, "text": "Click / E · " + str(action.text), "outline": null}


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	pressed = pressed or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E)
	if pressed and press(): get_viewport().set_input_as_handled()


## What a desktop click / E does here (public for the playtest bridge).
func press() -> bool:
	var action := _desktop_action()
	return not action.is_empty() and _do(action, "desktop")


# --- VR: grip near a thing; a held thing brought to its place goes there ---------------------------------

func grab_offer(side: String, sample: Dictionary) -> Dictionary:
	if not _available() or bool(inventory.get("_desktop")) or not bool(sample.get("active", false)): return {}
	var pose: Transform3D = sample.get("pose", Transform3D.IDENTITY)
	var from: Vector3 = sample.get("grip_position", pose.origin)
	if not from.is_finite(): return {}
	var best := {}
	var best_distance := VR_REACH
	for action: Dictionary in _actions(side):
		if str(action.do) not in ["door", "take"]: continue
		var distance := from.distance_to(action.point)
		if distance < best_distance:
			best = action
			best_distance = distance
	if best.is_empty(): return {}
	return {"target": _door if str(best.do) == "door" else _root, "point": best.point, "distance": best_distance,
		"text": side.capitalize() + " grip · " + str(best.text), "action": best}


func grab_take(side: String, offer: Dictionary, _sample: Dictionary) -> bool:
	var action: Variant = offer.get("action")
	return action is Dictionary and _do(action, side)


var _vr_wait := 0.0
func _vr_place() -> void:
	_vr_wait -= get_physics_process_delta_time()
	if _vr_wait > 0.0: return
	_vr_wait = 0.2
	if not _available() or bool(inventory.get("_desktop")): return
	for side: String in ["left", "right"]:
		if _held_key(side).is_empty(): continue
		var item := _held_item(side) as Node3D
		for action: Dictionary in _actions(side):
			if str(action.do) in ["sheet", "thing_desk", "thing_shelf"] and item.global_position.distance_to(action.point) < VR_REACH + 0.1:
				_do(action, side)
				return


# --- what the ponies know ---------------------------------------------------------------------------------

## What a pony knows. Every pony knows the day of the week (user 2026-11-18: the game never shows or
## tells it, so the weekend could not be told from a school day); the class knows about school.
func prompt_note(id: String) -> String:
	var day := _day_name()
	var today := "- Today is %s." % day
	if id in _class_ids():
		if _school_day():
			if _hours() < CLASS_FROM: today += " It is a school day: class at the schoolhouse from nine until three."
			elif _hours() >= CLASS_TO: today += " School is out for today."
		else:
			today += " There is no school today." if posmod(_today(), 7) in [1, 2, 3, 4, 5] else " It is the weekend: no school today; school starts again on Monday."
	if not _members.has(id) or _phase() != "class": return today
	return today + "\n" + _class_note(id)


func _class_note(id: String) -> String:
	var topic := _topic()
	var anon := " Anon is here in the classroom." if _anon_in_room() else ""
	if id == TEACHER:
		var job := _job()
		var doing := ""
		if not job.is_empty(): doing = " You asked Anon to help (%s); he is on it." % ("hand out the worksheets" if job.kind == "papers" else ("bring you the %s" % job.thing if job.kind == "fetch" else "put the %s back on its shelf" % job.thing))
		return "- You are teaching your class at the Ponyville Schoolhouse, standing at the front beside your desk; today's lesson: %s. Keep it gentle and clear for young fillies.%s%s" % [topic, anon, doing]
	var place := "at the back of the room" if id in _extras else "at your desk"
	return "- You are in class at the Ponyville Schoolhouse, sitting " + place + "; Miss Cheerilee is teaching %s. Keep your voice down, it is class time.%s" % [topic, anon]


# --- testing -------------------------------------------------------------------------------------------

## Ctrl+Shift+7 (dev tools on; every letter is taken by the game or another mod, J by raritys_cave): class now, whatever the day and hour (again: back to the clock).
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key := event as InputEventKey
	if key.physical_keycode != KEY_7 or not key.ctrl_pressed or not key.shift_pressed or not DEV.enabled(): return
	print("[schoolhouse] ", debug_class())
	get_viewport().set_input_as_handled()


func debug_class() -> String:
	_debug_class = not _debug_class
	_retry = 0.0
	return "class forced on" if _debug_class else "class back on the clock"


## For the playtest bridge: "ask papers|globe|telescope", "jobs now", "door".
func debug_do(what: String) -> Dictionary:
	var parts := what.split(" ")
	match parts[0]:
		"ask":
			_state().erase("job")
			if parts[1] == "papers": _ask("papers", "")
			else: _ask("fetch", parts[1])
		"return": _ask("return", parts[1])
		"door": toggle_door()
		"press":
			# Aim the desktop camera at action #n of _actions and press.
			var actions := _actions("desktop")
			var index := int(parts[1]) if parts.size() > 1 else 0
			if index >= actions.size(): return {"error": "no action %d" % index, "actions": actions.map(func(a: Dictionary) -> String: return str(a.text))}
			var camera: Camera3D = inventory.get("camera") as Camera3D
			var point: Vector3 = actions[index].point
			var from := point + (_w(Vector3(0, 2.2, 0)) - point).normalized() * 1.2
			camera.global_transform = Transform3D(Basis.looking_at(point - from), from)
			_debug_press = true
			var action := _desktop_action()
			var did := press()
			_debug_press = false
			return {"action": str(action.get("text", "")), "did": did}
	return debug_where()


func debug_where() -> Dictionary:
	var out := {"found": is_instance_valid(_root), "phase": _phase(), "door_open": _door_open(), "job": _job(),
		"jobs_done": _state().get("jobs_done", 0), "papers": _state().get("papers", "none"), "sheets": _sheets_down().keys(),
		"things": _state().get("things", {}), "anon_in_room": _anon_in_room() if is_instance_valid(_root) else false}
	if not is_instance_valid(_root): return out
	var ponies := {}
	for id: String in _class_ids():
		var actor := _live(id)
		var spot := _spot_of(id)
		ponies[id] = {"member": _members.has(id), "body": actor != null,
			"away": snappedf(actor.global_position.distance_to(_w(spot)), 0.01) if actor != null and spot.is_finite() else -1.0,
			"owner": str(actor.get_node("Navigator").get("command_owner")) if actor != null and actor.get_node_or_null("Navigator") else "",
			"posture": str((actor.call("posture_status") as Dictionary).get("kind", "")) if actor != null and actor.has_method("posture_status") else ""}
	out["ponies"] = ponies
	out["actions"] = _actions("desktop").map(func(a: Dictionary) -> String: return str(a.text))
	return out


## For the playtest bridge: the walk grid's two floor spans along the way in (building frame x = `x`,
## z from 14 out front to -2 inside): "z: height/slope/clearance/flags" per span, in local heights.
func debug_nav(x: float = 0.0) -> Array:
	var out: Array = []
	var service: Node = get_tree().get_first_node_in_group("pony_navigation")
	if service == null or not is_instance_valid(_school): return ["no grid"]
	for zi in range(28, -5, -1):
		var z := zi * 0.5
		var world := _school.to_global(Vector3(x, 0.0, z))
		var col := WalkGrid.column(world)
		var row := "%5.1f:" % z
		for span in WalkGrid.SPANS:
			var s: Dictionary = service.call("cached_sample", Vector3i(col.x, span, col.y))
			if s.is_empty(): row += " --"; continue
			var local_y := float(s.height) - _school.global_position.y
			row += " %.2f/%d/%.2f/%d" % [local_y, int(s.slope), minf(float(s.clearance), 99.0), int(s.flags)]
		out.append(row)
	return out


## For the playtest bridge: flood the walk grid from pony `id` with her own profile (WalkGrid.connected
## + has_room, as the planner links cells), inside the schoolhouse's neighbourhood. Says how far toward
## the room it gets, and why the deepest cells stop.
func debug_flood(id: String) -> Dictionary:
	var actor := _live(id)
	var service: Node = get_tree().get_first_node_in_group("pony_navigation")
	if actor == null or service == null: return {"error": "no pony or grid"}
	var p := WalkGrid.profile(actor.get("profile"))
	var data: Dictionary = (service.get("grid") as WalkGrid).snapshot()
	var start := WalkGrid.nearest(data, actor.global_position, p, 1.0)
	if start.y < 0: return {"error": "no start cell", "profile": p}
	var seen := {start: true}
	var todo: Array[Vector3i] = [start]
	var deepest := start
	var deepest_z := INF
	var inside := 0
	var ends := {}
	while not todo.is_empty() and seen.size() < 20000:
		var key: Vector3i = todo.pop_back()
		var a := WalkGrid.sample(data, key)
		var here := _school.to_local(Vector3((key.x + 0.5) * WalkGrid.CELL, float(a.height), (key.z + 0.5) * WalkGrid.CELL))
		if absf(here.x) > 9.0 or here.z < -14.0 or here.z > 20.0: continue
		if ROOM.has_point(here): inside += 1
		var to_door := here.distance_to(Vector3(0.0, FLOOR_Y, 5.5))
		if to_door < deepest_z: deepest_z = to_door; deepest = key
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			for span in WalkGrid.SPANS:
				var next := Vector3i(key.x + d.x, span, key.z + d.y)
				if seen.has(next): continue
				var b := WalkGrid.sample(data, next)
				if b.is_empty(): continue
				if WalkGrid.connected(a, b, WalkGrid.CELL, p) and WalkGrid.has_room(data, next, p):
					seen[next] = true
					todo.append(next)
	# Why the deepest cell goes no further toward the room.
	var why: Array = []
	var a := WalkGrid.sample(data, deepest)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for span in WalkGrid.SPANS:
			var next := Vector3i(deepest.x + d.x, span, deepest.z + d.y)
			var b := WalkGrid.sample(data, next)
			if b.is_empty() or seen.has(next): continue
			var at := _school.to_local(Vector3((next.x + 0.5) * WalkGrid.CELL, float(b.height), (next.z + 0.5) * WalkGrid.CELL))
			why.append("to %s h%.2f s%d c%.2f f%d allowed %s linked %s room %s" % [str(at.snapped(Vector3.ONE * 0.01)), at.y, int(b.slope), minf(float(b.clearance), 99.0), int(b.flags),
				WalkGrid.allowed(b, p), WalkGrid.connected(a, b, WalkGrid.CELL, p), WalkGrid.has_room(data, next, p)])
	var here := _school.to_local(Vector3((deepest.x + 0.5) * WalkGrid.CELL, float(a.height), (deepest.z + 0.5) * WalkGrid.CELL))
	return {"profile": p, "reached": seen.size(), "inside_room": inside, "closest_to_door": here.snapped(Vector3.ONE * 0.01), "deepest": {"slope": a.slope, "clearance": a.clearance}, "why": why}
