extends Node
## The televisions lying in the Everfree for the first days of a world (finds.gd): the vintage set
## at the forest's edge, not far from Fluttershy's cottage, the two flatscreens deeper in, toward
## Zecora's hut. Each is a one-item shop display (world/shop/shop_display.gd) with no table and no
## price card, at no price: picking it up is the game's own take (world/shop/shop_purchase.gd), so
## it works the same on desktop and in VR. A set nopony found is gone once somepony has taken it to
## the market (finds.gd MARKET_FROM), but never while Anon is close enough to see it go.
## Also here: the remote that comes with the first television, and the rumours (their prompt note:
## the game's pony_prompt_notes group, as watch_company.gd), each only while its set still lies out
## there: Fluttershy heard the vintage set come down somewhere near her cottage but never saw it
## (she cannot show the way); Zecora has seen the flatscreen on its stand and can lead Anon to it
## (ext/pony_action_schema.gd gives her the place, finds.gd slab_place). The wall flatscreen has no
## rumour: it is found on one's own or bought.

const FINDS := preload("res://mods/watch_party/finds.gd")
const DISPLAY := preload("res://world/shop/shop_display.gd")
## A set is laid out once Anon is this close (the terrain under it has collision by then).
const PLACE_RANGE := 120.0
## Tree trunks have collision only within about 96 m of Anon (world/foliage/biome_foliage.gd), so a
## spot is only known to be clear from closer: within CHECK_RANGE (its whole 32 m cell then
## has trunks) the set's spot is checked once each session, and a set in a trunk or a rock moves
## to the nearest clear spot, kept from then on (playtest 2026-11-07: laid out from 120 m, the
## flatscreen had been put inside a tree). Each session, so a tree that only grows at a higher
## foliage density (Settings → Video) or after a game update is found too.
const CHECK_RANGE := 45.0
## The space a set takes up on the ground, half extents in its own frame (width, height, depth;
## the wall flatscreen lies flat).
const FOOTPRINT := {FINDS.VINTAGE: Vector3(0.6, 0.55, 0.4), FINDS.FLAT_STAND: Vector3(0.88, 0.6, 0.35), FINDS.FLAT_WALL: Vector3(0.78, 0.12, 0.48)}
## A set taken to the market vanishes only while Anon is further away than this.
const LEAVE_RANGE := 60.0
## Spots tried around the nominal one: rings of this many metres, eight to a ring.
const RINGS := [0.0, 3.0, 6.0, 9.0, 13.0]
const CHECK_SECONDS := 1.0
## The wall flatscreen lies on its back in the leaves, this far up (the panel's own depth).
const LYING_LIFT := 0.07
const REMOTE_NOTE := "A TV remote came with it. It is in your briefcase."
## pony id -> [the set it is about, what she knows while it lies in the forest, what she knows
## once it is gone from there]. The first is the rumour; the second only lets her remember having
## told it (playtest 2026-11-05: asked about it a minute later, Fluttershy said she never had) and
## never sends Anon looking for a set that is no longer there.
const NOTES := {
	"fluttershy": [FINDS.VINTAGE,
		"Something that has been on your mind: one night recently you heard something big and heavy crash down in the Everfree, somewhere not far from your cottage, with an odd glassy clunk, and it gave you quite a fright. You never saw what it was or where exactly it landed, and you have not dared go and look, so you could not show anypony the way. Only bring it up if it comes up or feels natural; if you have already told Anon about it, you remember telling him and stand by it.",
		"A while ago you heard something big and heavy crash down in the Everfree near your cottage, and you may have told Anon about it. You have heard since that whatever it was has been found and taken out of the forest, so there is nothing out there to look for any more. Do not bring it up yourself; if Anon asks, that is what you know."],
	"zecora": [FINDS.FLAT_STAND,
		"On your walks through the Everfree you came upon something that does not belong to the forest: a flat black slab, smooth and shiny as still water, standing on a low little table among the trees, partway along the way between Ponyville and your hut. You do not know what it is, and it did not grow there; it does not seem dangerous, only asleep, as if waiting for some kind of magic. You know exactly where it is: if Anon asks you to show him, you can take him there yourself with [lead: player, strange black slab]. If he asks what to do with it, your advice is that he carry it to Twilight Sparkle in Ponyville, who knows more of such riddles than anypony; it is heavy, but it can be carried, and her books and tools are at home, not out here. Only bring it up if it comes up or feels natural.",
		"You once came upon a strange flat black slab on a little table in the Everfree, and you may have told Anon about it or shown him the way. It is no longer where it was: somepony has taken it. Do not bring it up yourself; if Anon asks, that is what you know."],
}
## The story begins this long after a world opens with Anon in it (its save and briefcase are
## loaded by then, so a world that already has a set is known as one).
const BEGIN_AFTER := 3.0
## A set is looked for only this long after the world opened, and counts as missing after this
## many passes (CHECK_SECONDS apart) without it (_note_lost).
const LOST_AFTER := 10.0
const LOST_CHECKS := 5
var hub: Node
var _displays: Dictionary = {}
var _check := 0.0
var _opened := 0.0
## Set id -> passes in a row it was in no briefcase slot or loan (_note_lost).
var _absent: Dictionary = {}
## The sets whose spot was checked this session (CHECK_RANGE).
var _checked: Dictionary = {}

func _ready() -> void:
	add_to_group("pony_prompt_notes")

## A world opened: its story begins (finds.gd begin) and its forest is laid out as Anon comes near.
func world(_game: Node) -> void:
	_displays.clear()
	_checked.clear()
	_absent.clear()
	_opened = 0.0

func _process(delta: float) -> void:
	_opened += delta
	_check -= delta
	if _check > 0.0: return
	_check = CHECK_SECONDS
	var game: Node = Mods.game
	if not is_instance_valid(game): return
	var inventory: Node = game.get("inventory") as Node
	var eye := _eye(inventory)
	if not eye.is_finite(): return
	# Begun once per world (finds.gd keeps it in the save); again if a save loaded over it.
	if not FINDS.state().has("first_day"):
		if _opened < BEGIN_AFTER: return
		FINDS.begin(FINDS.owned(inventory))
	if FINDS.state().is_empty(): return
	for id: String in FINDS.TVS:
		var display: Variant = _displays.get(id)
		if FINDS.in_forest(id):
			if not is_instance_valid(display) and _flat(eye, FINDS.forest_point(id)) < PLACE_RANGE: _place(id, game)
			elif is_instance_valid(display) and not _checked.has(id) and _flat(eye, (display as Node3D).global_position) < CHECK_RANGE: _recheck(id, display as Node3D, game)
		elif is_instance_valid(display):
			if FINDS.had(id) or _flat(eye, (display as Node3D).global_position) > LEAVE_RANGE:
				(display as Node).queue_free()
				_displays.erase(id)
				if not FINDS.had(id): print("[watch_party] forest: the %s is gone (somepony took it to the market)" % FINDS.kind_name(id))
	_note_owned(inventory)
	_give_remote(inventory)
	_note_lost(inventory)

## A set Anon had that is nowhere now goes back to the market at the next restock (finds.gd
## tidy_lost). Only once the briefcase has been steady for a while: a set counts as missing after
## LOST_CHECKS passes in a row without it, so a briefcase still loading loses nothing.
func _note_lost(inventory: Node) -> void:
	var store: Variant = inventory.get("inventory") if is_instance_valid(inventory) else null
	if _opened < LOST_AFTER or not store is Object or not (store as Object).get("slots") is Array or not (store as Object).get("loans") is Dictionary:
		_absent.clear()
		return
	var present: Array = FINDS.owned(inventory) + FINDS.parked(inventory)
	for id: String in FINDS.TVS:
		if id in present: _absent.erase(id)
		else:
			_absent[id] = int(_absent.get(id, 0)) + 1
			if int(_absent[id]) < LOST_CHECKS: present.append(id)
	FINDS.tidy_lost(present)

## A set in Anon's briefcase, hands or placed somewhere is his: the one of its kind, so it is
## gone from the forest and the market (bought at the market, it is in his loans the
## moment it is paid for: world/shop/shop_purchase.gd).
func _note_owned(inventory: Node) -> void:
	for id: Variant in FINDS.owned(inventory):
		if not id in FINDS.TVS or FINDS.had(str(id)): continue
		if FINDS.in_forest(str(id)): FINDS.mark_found(str(id))
		else: FINDS.mark_bought(str(id))

func _eye(inventory: Node) -> Vector3:
	var camera: Variant = inventory.get("camera") if is_instance_valid(inventory) else null
	return (camera as Node3D).global_position if camera is Node3D and (camera as Node3D).is_inside_tree() else Vector3.INF

## The set on the forest floor at its kept spot, else at the first clear spot found near its
## finds.gd FOREST spot.
func _place(id: String, game: Node) -> void:
	var where: Variant = FINDS.spot(id)
	if where == null:
		where = _find_spot(id, game)
		if where == null: return   # the ground there has no collision yet: the next pass tries again
		FINDS.keep_spot(id, where)
	var pose: Transform3D = where
	if id == FINDS.FLAT_WALL:
		# Lying on its back, screen to the sky (the screen faces +Z: tv_set.gd).
		pose = Transform3D(pose.basis * Basis(Vector3.RIGHT, -PI * 0.5), pose.origin + Vector3.UP * LYING_LIFT)
	var display: Node3D = DISPLAY.new()
	display.name = "WatchPartyFind_" + id.get_slice(":", 1)
	display.display_id = "watch_party:forest:" + id.get_slice(":", 1)
	display.item_ids = PackedStringArray([id])
	display.columns = 1
	display.build_surface = false
	display.top_level = true
	game.add_child(display)
	display.global_transform = pose
	display.stock_changed.connect(_on_taken.bind(id))
	_displays[id] = display
	display.populate()
	# No price card in the woods.
	var cards: Variant = display.get("_cards")
	if cards is Dictionary:
		for card: Variant in (cards as Dictionary).values():
			if is_instance_valid(card): (card as Node3D).visible = false
	print("[watch_party] forest: the %s lies at %s" % [FINDS.kind_name(id), str(pose.origin.snapped(Vector3.ONE * 0.1))])

## Where a set first lies: an exact FOREST spot (y not 0, chosen in play) as it is; for a guessed
## one, level ground near it. Null when the terrain there is not loaded yet. Either way the spot is
## checked for trunks once Anon comes close (_recheck).
func _find_spot(id: String, game: Node) -> Variant:
	var space := _space(game)
	if space == null: return null
	var row: Array = FINDS.FOREST[id]
	var centre: Vector3 = row[0]
	var facing := Basis(Vector3.UP, deg_to_rad(float(row[1])))
	if not is_zero_approx(centre.y): return Transform3D(facing, centre)
	var none: Array[RID] = []
	return _search(space, id, centre, facing, none, true)

func _space(game: Node) -> PhysicsDirectSpaceState3D:
	if game is Node3D and (game as Node3D).is_inside_tree(): return (game as Node3D).get_world_3d().direct_space_state
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	return camera.get_world_3d().direct_space_state if camera != null else null

## The first clear, level spot in RINGS around `centre`, facing `facing`. `skip`: bodies not to
## count (the set itself). With `fallback`, the first ground found when none is clear; else null.
func _search(space: PhysicsDirectSpaceState3D, id: String, centre: Vector3, facing: Basis, skip: Array[RID], fallback: bool) -> Variant:
	var first: Variant = null
	for ring: float in RINGS:
		for step in (1 if ring == 0.0 else 8):
			var angle := TAU * step / 8.0
			var at := centre + Vector3(cos(angle), 0.0, sin(angle)) * ring
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, centre.y + 400.0, at.z), Vector3(at.x, centre.y - 400.0, at.z), 1, skip))
			if hit.is_empty(): continue
			var pose := Transform3D(facing, hit.position)
			if first == null: first = pose
			if (hit.normal as Vector3).y < 0.85: continue
			if _open_at(space, id, pose, skip, hit.get("rid")): return pose
	return first if fallback else null

## Nothing standing where the set would be: its footprint, lifted a little off the ground it rests
## on (`ground`, not counted: a slope would otherwise touch it), holds no trunk, rock or wall.
func _open_at(space: PhysicsDirectSpaceState3D, id: String, pose: Transform3D, skip: Array[RID], ground: Variant = null) -> bool:
	var half: Vector3 = FOOTPRINT.get(id, Vector3(0.6, 0.5, 0.4))
	var box := BoxShape3D.new()
	box.size = half * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 1
	var exclude: Array[RID] = skip.duplicate()
	if ground is RID: exclude.append(ground)
	query.exclude = exclude
	query.transform = Transform3D(pose.basis, pose.origin + Vector3.UP * (half.y + 0.15))
	return space.intersect_shape(query, 1).is_empty()

## Close enough for every trunk around it to be solid: a set in one moves to the nearest clear spot.
func _recheck(id: String, display: Node3D, game: Node) -> void:
	var space := _space(game)
	var kept: Variant = FINDS.spot(id)
	if space == null or not kept is Transform3D: return
	_checked[id] = true
	var pose: Transform3D = kept
	var skip: Array[RID] = []
	_bodies(display, skip)
	var under := space.intersect_ray(PhysicsRayQueryParameters3D.create(pose.origin + Vector3.UP * 0.5, pose.origin + Vector3.DOWN * 1.0, 1, skip))
	if _open_at(space, id, pose, skip, under.get("rid") if not under.is_empty() else null): return
	var moved: Variant = _search(space, id, pose.origin, pose.basis, skip, false)
	if moved == null:
		print("[watch_party] forest: the %s is boxed in at %s and nowhere near is clear; left as it is" % [FINDS.kind_name(id), str(pose.origin.snapped(Vector3.ONE * 0.1))])
		return
	FINDS.keep_spot(id, moved)
	display.queue_free()
	_displays.erase(id)
	print("[watch_party] forest: the %s was inside something at %s; moved to %s" % [FINDS.kind_name(id), str(pose.origin.snapped(Vector3.ONE * 0.1)), str((moved as Transform3D).origin.snapped(Vector3.ONE * 0.1))])

## Every body under `node` (the display's own set).
static func _bodies(node: Node, into: Array[RID]) -> void:
	for child: Node in node.get_children():
		if child is CollisionObject3D: into.append((child as CollisionObject3D).get_rid())
		_bodies(child, into)

## Picked up: found for good (the briefcase has it now).
func _on_taken(state: Dictionary, id: String) -> void:
	if (state.get("taken", []) as Array).is_empty(): return
	FINDS.mark_found(id)
	print("[watch_party] forest: Anon found the %s" % FINDS.kind_name(id))

## The remote comes with whichever television Anon gets first (found or bought).
func _give_remote(inventory: Node) -> void:
	var data := FINDS.state()
	if bool(data.get("remote_given", false)) or not is_instance_valid(inventory): return
	var mine := FINDS.owned(inventory)
	if not mine.any(func(id: Variant) -> bool: return id in FINDS.TVS): return
	if not FINDS.REMOTE in mine:
		var store: Variant = inventory.get("inventory")
		if not store is Object or int((store as Object).call("grant", FINDS.REMOTE, 1)) < 0: return   # no room yet: tries again
		_say(inventory, REMOTE_NOTE)
		print("[watch_party] the TV remote came with the first television")
	data.remote_given = true
	FINDS.changed()

## A line on the hotbar for a few seconds (as world/shop/shop_purchase.gd _say).
static func _say(inventory: Node, text: String) -> void:
	var bar: Variant = inventory.get("hotbar")
	if not is_instance_valid(bar) or not (bar as Node).has_method("set_message"): return
	(bar as Node).call("set_message", text)
	inventory.get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if is_instance_valid(bar) and str((bar as Node).get("message")) == text: (bar as Node).call("set_message", ""))

## What Fluttershy heard and Zecora saw while that set still lies in the forest; found or taken to
## the market, the rumour is gone (nopony sends Anon looking for nothing) and only her memory of it
## is left, for if he asks.
func prompt_note(id: String) -> String:
	var row: Array = NOTES.get(id, [])
	if row.is_empty() or FINDS.state().is_empty(): return ""
	return str(row[1]) if FINDS.in_forest(str(row[0])) else str(row[2])

# --- for testing: clearing the forest sets ---------------------------------------------------

func _clear_one(id: String) -> void:
	var display: Variant = _displays.get(id)
	if is_instance_valid(display): (display as Node).queue_free()
	_displays.erase(id)

func _clear() -> void:
	for id: Variant in _displays.keys(): _clear_one(str(id))

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
