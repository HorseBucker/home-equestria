extends Node
## Anon's mailbox (docs/LETTERS_PLAN_2026_10_29.md section 10). The replies and notes Derpy dropped
## (letter_courier.gd state mailbox) show as one letter (activity/letter.scn) poking out of the kit
## mailbox nearest his house within 25 m, or lying on the ground by his front door when none stands
## there. Taking it works like harvest_pickup.gd: VR grip through the grab router (group
## grab_providers), desktop click or E while aiming at it with a free hand. letter_courier.gd
## take_letter does the take (briefcase, hand, gift, status taken); the oldest letter comes first.
## In the provider groups only while a letter is shown, so an empty mailbox costs nothing.
const KIT_SPOTS := preload("res://world/props/ponyville_kit/kit_spots.gd")
const FITS := preload("res://world/props/ponyville_kit/kit_fits.gd")
const FLIGHT := preload("res://player/wing_flight.gd")
const LETTER := "res://world/props/ponyville_kit/activity/letter.scn"
const MAILBOX_REACH := 25.0
const DESKTOP_REACH := 2.4
## Metres the desktop aim ray may pass beside the letter.
const AIM_SLACK := 0.16
const VR_REACH := 0.25
## A letter by the door lies flat, a little to the side of the step.
const DOOR_OFFSET := Vector3(0.6, 0.02, 0.0)
var courier: Node
## The briefcase node: grab_router.gd matches its providers by this field.
var inventory: Node
var prop: Node3D

func setup(owner_courier: Node) -> void:
	courier = owner_courier
	set_process_unhandled_input(false)

## Shows, moves or removes the letter for the current mailbox (letter_courier.gd poll and takes).
func refresh() -> void:
	inventory = courier.call("_briefcase") if courier != null else null
	var ids: Array = courier.call("mailbox_ids") if courier != null else []
	var spot: Variant = spot_transform() if not ids.is_empty() else null
	if not spot is Transform3D:
		_clear()
		return
	if not is_instance_valid(prop):
		var scene := load(LETTER) as PackedScene
		if scene == null: return
		prop = scene.instantiate() as Node3D
		if prop == null: return
		prop.name = "MailboxLetter"
		prop.transform = spot
		add_child(prop)
	elif not prop.transform.is_equal_approx(spot):
		prop.transform = spot
	for group: String in ["grab_providers", "interaction_hint_sources"]:
		if not is_in_group(group): add_to_group(group)
	set_process_unhandled_input(true)

func _clear() -> void:
	for group: String in ["grab_providers", "interaction_hint_sources"]:
		if is_in_group(group): remove_from_group(group)
	set_process_unhandled_input(false)
	if is_instance_valid(prop): prop.queue_free()
	prop = null

## Where the letter sits: out of the door of the kit mailbox nearest his house (activity/fit.json
## letter_rest), else flat by his front door; null without a loaded home.
func spot_transform() -> Variant:
	var home: Node3D = courier.call("player_home") if courier != null else null
	if home == null: return null
	var door: Vector3 = home.call("outside") if home.has_method("outside") else home.global_position
	KIT_SPOTS._index()
	var best := ""
	var gap := MAILBOX_REACH * MAILBOX_REACH
	for id: String in KIT_SPOTS._by_kind.get("mailbox", []):
		var row: Dictionary = KIT_SPOTS._by_id[id]
		var distance := Vector2(float(row.x) - door.x, float(row.z) - door.z).length_squared()
		if distance < gap: gap = distance; best = id
	var fit := FITS.get_kind("mailbox")
	if not best.is_empty() and not fit.is_empty():
		var spot: Dictionary = KIT_SPOTS.by_id(best)
		var rest: Transform3D = (spot.transform as Transform3D) * FITS.transform(fit.get("letter_rest"))
		if rest.is_finite(): return rest
	var facing := home.global_basis.orthonormalized() if home.global_basis.is_finite() else Basis.IDENTITY
	return Transform3D(facing, door + facing * DOOR_OFFSET)

func letter_point() -> Vector3:
	return prop.global_position if is_instance_valid(prop) and prop.is_inside_tree() else Vector3.INF

func _available() -> bool:
	if not is_instance_valid(prop) or not is_instance_valid(inventory): return false
	var camera: Variant = inventory.get("camera")
	var body: Variant = inventory.get("player_body")
	if not camera is Camera3D or not is_instance_valid(camera) or not body is Node or not is_instance_valid(body): return false
	if bool((body as Node).get("controls_locked")): return false
	return not (inventory.has_method("_quick_blocked") and bool(inventory.call("_quick_blocked")))

func desktop_offer() -> Dictionary:
	if not _available() or bool(inventory.call("hand_busy", "desktop")): return {}
	var camera: Camera3D = inventory.get("camera")
	var point := letter_point()
	var eye := camera.global_position
	var ahead := -camera.global_basis.z
	var along := (point - eye).dot(ahead)
	if along <= 0.0 or along > DESKTOP_REACH: return {}
	if (point - eye - ahead * along).length() > AIM_SLACK: return {}
	var excluded: Array[RID] = []
	var body: Variant = inventory.get("player_body")
	if body is CollisionObject3D: excluded.append((body as CollisionObject3D).get_rid())
	var hit: Dictionary = prop.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, point, 1, excluded))
	if not hit.is_empty() and (hit.position as Vector3).distance_to(point) > 0.15: return {}
	return {"target": prop, "point": point, "text": "Click / E · Take letter", "visible_pick": true}

func grab_offer(side: String, sample: Dictionary) -> Dictionary:
	if not _available() or not sample.get("active", false): return {}
	var pose: Transform3D = sample.get("pose", Transform3D.IDENTITY)
	var from: Vector3 = sample.get("grip_position", pose.origin)
	var point := letter_point()
	if not from.is_finite() or not point.is_finite(): return {}
	var distance := from.distance_to(point)
	if distance > VR_REACH: return {}
	return {"target": prop, "point": point, "distance": distance, "text": side.capitalize() + " grip · Take letter"}

func grab_take(side: String, _offer: Dictionary, _sample: Dictionary) -> bool:
	return take(side)

func take(side: String) -> bool:
	if not _available(): return false
	var ids: Array = courier.call("mailbox_ids")
	if ids.is_empty(): return false
	var taken: bool = courier.call("take_letter", str(ids[0]), side)
	if taken and inventory.has_method("_haptic") and side != "desktop": inventory.call("_haptic", side)
	return taken

func interaction_hint() -> Dictionary:
	if not is_instance_valid(inventory) or not bool(inventory.get("_desktop")): return {}
	return desktop_offer()

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(prop) or not is_instance_valid(inventory) or not bool(inventory.get("_desktop")): return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or FLIGHT.reserves_mouse(event, inventory.get("player_body")): return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	pressed = pressed or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E)
	if not pressed or desktop_offer().is_empty(): return
	if take("desktop"): get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	for group: String in ["grab_providers", "interaction_hint_sources"]:
		if is_in_group(group): remove_from_group(group)
