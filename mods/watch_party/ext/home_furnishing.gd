extends "res://world/housing/home_furnishing.gd"
## Watch Party: a television can be placed anywhere.
## - In any house, not only Anon's own. The game finds the house inside plan() (home(): the one
##   reserved for the player), and offer(), place(), hint() and wheel() reach plan() from inside the
##   game's script, where a mod cannot step in. So for a held set inside another house these five
##   run their own copy, which differs from the game's only in the house it places into.
## - Out of doors (dev 2026-11-07: "I have to just drop it and hope it doesn't tip over"): the
##   console sets stand on the ground or anything flat enough, the wall flatscreen hangs on any
##   wall, fence, rock face or tree trunk, aimed and placed like furniture indoors (desktop
##   Shift+Q, the wheel turns a standing set; VR let go of the grip). It is kept in the save as
##   furniture of the home OUTSIDE (home() answers for it with the game node), so it loads back
##   exactly where it was, frozen, on a tree as well as on the ground.
## Everything else, and a set in Anon's own house, takes the game's own path unchanged. A set placed
## in a house loads back through the game's home(tree, id) like any furniture.
## Applied by res://mods/watch_party/ext_loader.gd.

const WATCH_PARTY_PATH := "res://world/housing/home_furnishing.gd"
const WATCH_PARTY_LOADER := preload("res://mods/watch_party/ext_loader.gd")
const WATCH_PARTY_CATALOG := "res://mods/watch_party/catalog.gd"
const WATCH_PARTY_SETS := ["goods:watch-tv-vintage", "goods:watch-tv-flat", "goods:watch-tv-flat-wall"]
## The home id of a set placed out of doors.
const WATCH_PARTY_OUTSIDE := "watch_party:outside"
## Out of doors: the ground under a standing set may slope this much (normal's up part), a wall may
## lean this much, and the aim reaches this far (a tree a step or two away).
const WATCH_PARTY_GROUND := 0.8
const WATCH_PARTY_WALL := 0.35
const WATCH_PARTY_REACH := 3.5

static func _watch_party_game() -> Script:
	return WATCH_PARTY_LOADER.base(WATCH_PARTY_PATH)

## A Watch Party set in this hand, or null.
static func _watch_party_set(ui: Node3D, side: String) -> RigidBody3D:
	var item: Variant = ui.held.get(side)
	if not is_instance_valid(item) or not item is RigidBody3D: return null
	if str((item as Node3D).get_meta("item_id", "")) not in WATCH_PARTY_SETS: return null
	return item as RigidBody3D

## Where a set held in this hand goes when that is not Anon's own house: {house} for another house,
## {outside: true} out of doors; {} for the game's own path.
static func _watch_party_where(ui: Node3D, side: String) -> Dictionary:
	var item := _watch_party_set(ui, side)
	if item == null or not is_instance_valid(ui.camera): return {}
	var house: Variant = load(WATCH_PARTY_CATALOG).call("house_at", ui.get_tree(), [item.global_position, ui.camera.global_position])
	if house == null: return {"outside": true}
	if not house is Node3D or house == home(ui.get_tree()): return {}
	return {"house": house}

## The out-of-doors home for loading a set back (the game node: it is always there).
static func home(tree: SceneTree, id: String = "") -> Node3D:
	if id == WATCH_PARTY_OUTSIDE:
		return Mods.game as Node3D if is_instance_valid(Mods.game) and Mods.game is Node3D else null
	return _watch_party_game().call("home", tree, id)

static func plan(ui: Node3D, side: String) -> Dictionary:
	var where := _watch_party_where(ui, side)
	if where.is_empty(): return _watch_party_game().call("plan", ui, side)
	if where.has("outside"): return _watch_party_outside_plan(ui, side)
	return _watch_party_plan(ui, side, where.house)

static func offer(ui: Node3D, side: String) -> Dictionary:
	if _watch_party_where(ui, side).is_empty(): return _watch_party_game().call("offer", ui, side)
	var pick := plan(ui, side)
	return pick if not pick.is_empty() and bool(pick.ok) else {}

static func place(ui: Node3D, side: String) -> bool:
	if _watch_party_where(ui, side).is_empty(): return bool(_watch_party_game().call("place", ui, side))
	var pick := offer(ui, side)
	if pick.is_empty(): return false
	var item: RigidBody3D = ui.held[side]
	var token := str(item.get_meta("token", ""))
	if not ui.inventory.set_furnishing(token, pick.pose, pick.home, size_of(item)): ui._error(); return true
	item.global_transform = pick.pose
	ui._unglow(item)
	configure(item, true)
	for key: String in ["hold_offset", "hold_blend", "hold_from", "ray_hold"]:
		if item.has_meta(key): item.remove_meta(key)
	ui.held.erase(side); ui._track.erase(side); ui._eat_time.erase(side)
	ui._claim(side, false); ui._refresh_holding(); ui._haptic(side)
	SFX.play_event(item, "prop_place", {"material": "wood"})
	return true

static func hint(ui: Node3D) -> Dictionary:
	var sides: Array = ["desktop"] if ui._desktop else ["right", "left"]
	var elsewhere := false
	for side: String in sides:
		if not _watch_party_where(ui, side).is_empty(): elsewhere = true
	if not elsewhere: return _watch_party_game().call("hint", ui)
	for side: String in sides:
		var pick := plan(ui, side)
		if pick.is_empty(): continue
		var item: RigidBody3D = ui.held[side]
		if not bool(pick.ok): return {"target": item, "point": pick.point, "text": str(pick.why), "outline": null, "visible_pick": true}
		var action := "Hang it here" if pick.wall else "Place it here"
		if side == "desktop": action += "   Wheel · Size" if resizable(item) else "   Wheel · Turn" if not pick.wall else ""
		elif resizable(item): action += "   Trigger · Size"
		var control := "Shift+Q" if side == "desktop" else "Grip" if ui.inventory.loans.get(str(item.get_meta("token", "")), {}).get("equipped", false) else "Release grip"
		return {"target": item, "point": pick.point, "text": control + " · " + action, "outline": null, "visible_pick": true}
	# Aimed at nothing to place on (the sky): the game's own hint.
	return _watch_party_game().call("hint", ui)

static func wheel(ui: Node3D, side: String, step: int) -> bool:
	if _watch_party_where(ui, side).is_empty(): return bool(_watch_party_game().call("wheel", ui, side, step))
	var item: RigidBody3D = ui.held.get(side)
	if not eligible(item) or plan(ui, side).is_empty(): return false
	if resizable(item): return step_size(ui, side, step)
	if RULES.wall(str(item.get_meta("item_id", ""))): return false
	item.set_meta("furnishing_turn", float(item.get_meta("furnishing_turn", 0.0)) + step * RULES.TURN_DEGREES)
	return true

## What the hand or the view is aimed at for placing (the game's plan() rays), or {}.
static func _watch_party_hit(ui: Node3D, side: String, item: RigidBody3D, reach: float) -> Dictionary:
	var holder := shape(item)
	if holder == null: return {}
	var id := str(item.get_meta("item_id", ""))
	var excluded := _watch_party_excluded(ui, item)
	var space := ui.get_world_3d().direct_space_state
	if side == "desktop":
		return space.intersect_ray(PhysicsRayQueryParameters3D.create(ui.camera.global_position, ui.camera.global_position - ui.camera.global_basis.z * reach, 1, excluded))
	if RULES.wall(id):
		var center: Vector3 = item.global_transform * holder.transform * holder.shape.get_debug_mesh().get_aabb().get_center()
		var back: Vector3 = -item.global_basis.z.normalized()
		return space.intersect_ray(PhysicsRayQueryParameters3D.create(center, center + back * .55, 1, excluded))
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(item.global_position + Vector3.UP * .12, item.global_position + Vector3.DOWN * .3, 1, excluded))

static func _watch_party_excluded(ui: Node3D, item: RigidBody3D) -> Array[RID]:
	var excluded: Array[RID] = [item.get_rid()]
	if ui.player_body is CollisionObject3D: excluded.append(ui.player_body.get_rid())
	for other: Variant in ui.held.values():
		if is_instance_valid(other) and other is CollisionObject3D: excluded.append(other.get_rid())
	return excluded

## The game's plan() with `house` in place of Anon's own home.
static func _watch_party_plan(ui: Node3D, side: String, house: Node3D) -> Dictionary:
	var item: RigidBody3D = ui.held.get(side)
	if not eligible(item) or ui.get_tree().paused: return {}
	if not is_instance_valid(ui.camera) or not ui.camera.global_transform.is_finite(): return {}
	if item.global_position.distance_to(house.global_position) > 35.0: return {}
	var hit := _watch_party_hit(ui, side, item, REACH)
	if hit.is_empty(): return {}
	return surface_offer(ui, item, house, hit, side, _watch_party_excluded(ui, item))

## Out of doors: the game's surface_offer() without a house to fit in. A standing set needs ground
## that is flat enough; the wall set any surface steep enough (a tree trunk too: the trunk it hangs
## on is not counted as in the way).
static func _watch_party_outside_plan(ui: Node3D, side: String) -> Dictionary:
	var item: RigidBody3D = ui.held.get(side)
	if not eligible(item) or ui.get_tree().paused: return {}
	if not is_instance_valid(ui.camera) or not ui.camera.global_transform.is_finite(): return {}
	var holder := shape(item)
	if holder == null: return {}
	var hit := _watch_party_hit(ui, side, item, WATCH_PARTY_REACH)
	if hit.is_empty(): return {}
	var id := str(item.get_meta("item_id", ""))
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var point: Vector3 = hit.get("position", Vector3.INF)
	if not point.is_finite() or not normal.is_finite() or normal.length() < 0.1: return {}
	normal = normal.normalized()
	var size := size_of(item)
	var local_box: AABB = holder.transform * holder.shape.get_debug_mesh().get_aabb()
	local_box = AABB(local_box.position * size, local_box.size * size)
	var pose := Transform3D.IDENTITY
	var why := ""
	var wall := RULES.wall(id)
	if wall:
		if absf(normal.y) > WATCH_PARTY_WALL:
			why = "That needs a wall or a tree"
			pose.basis = Basis.looking_at(-normal, ui.camera.global_basis.x if absf(normal.y) > .9 else Vector3.UP)
			pose.origin = point + normal * .012
		else:
			var flat := Vector3(normal.x, 0.0, normal.z).normalized()
			pose.basis = Basis(Vector3.UP.cross(flat), Vector3.UP, flat)
			pose.origin = point + flat * (-local_box.position.z + .012) - Vector3.UP * local_box.get_center().y
	else:
		if normal.y < WATCH_PARTY_GROUND: why = "That needs flatter ground"
		var heading: Basis = ui.camera.global_basis if side == "desktop" else item.global_basis
		pose.basis = Basis(Vector3.UP, heading.get_euler().y + deg_to_rad(float(item.get_meta("furnishing_turn", 0.0))))
		var turned: AABB = Transform3D(pose.basis, Vector3.ZERO) * local_box
		pose.origin = point + Vector3.UP * (-turned.position.y + .008)
	if why.is_empty():
		var excluded := _watch_party_excluded(ui, item)
		var under: Variant = hit.get("collider")
		# What it stands on or hangs from is not in the way (a curved trunk touches a flat panel).
		if under is CollisionObject3D: excluded.append((under as CollisionObject3D).get_rid())
		elif hit.get("rid") is RID: excluded.append(hit.rid)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _sized_shape(holder.shape, size)
		query.transform = pose * Transform3D(holder.transform.basis, holder.transform.origin * size)
		# A little off the surface, so the ground it rests on is not counted either.
		query.transform.origin += (normal if wall else Vector3.UP) * 0.02
		query.collision_mask = 1 | ITEM_LAYER; query.exclude = excluded
		if not ui.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): why = "Something is in the way"
	return {"target": item, "point": point, "pose": pose, "home": WATCH_PARTY_OUTSIDE, "wall": wall, "ok": why.is_empty(), "why": why}
