extends "res://world/shop/shop_world.gd"
## Watch Party: the televisions at the Ponyville market, inside one of the market tents, built after
## the game's own tables (its PLACEMENTS are a constant) by the same steps the game builds one, and
## saved with them. Two shop displays (world/shop/shop_display.gd):
## - the sets on a stepped stand built like the market's own counters (light wood, white panels
##   on the front: playtest 2026-11-05, "like this table right outside the tent"): a front step with up to two sets side by side, and,
##   when all three are there, a raised back step in the middle with the flatscreen on its console
##   (tall enough to show over the front two). The front sets' cards lie on the step in front of
##   them; the back set's card stands upright on the face of the raised step, in the gap between
##   the front two, so it can be read from the front (playtest 2026-11-05: the back cards could
##   only be read from on top of the table). Once one is gone (found or bought: only three ever
##   came over, finds.gd had), the stand is built again with the others in front.
## - the remote on its own little counter beside it, always clear of the widest stand
##   (playtest 2026-11-05: it was left where the narrower one-set stand had ended, inside the new one). Only the remote is sold again: the market's
##   keepers restock only the tables in PLACEMENTS (world/mechanics/market/market.gd plan_restock),
##   so _restock_check refills these at the same 06:00 restock itself.
## What is out follows the story (res://mods/watch_party/finds.gd market_items): nothing on the
## first day (the sets still lie in the Everfree), the vintage set and the remote from the second,
## both flatscreens as well from the third. Their sales go to the market (shops.json default_owner).
## Applied by res://mods/watch_party/ext_loader.gd.

const WATCH_PARTY_FINDS := preload("res://mods/watch_party/finds.gd")
## Where the stand's front step is centred, on the ground, and which way its front faces (degrees
## about up, as "tv here" prints them): inside the tent, out of the ponies' way (playtest
## 2026-11-05: the old table by the furniture tent stood where ponies walk, and they walked through
## it). The tent is only the parent node (and a sign the town is loaded).
const WATCH_PARTY_AT := Vector3(206.27, -9.25, -217.76)
const WATCH_PARTY_FACING := 351.0
const WATCH_PARTY_ANCHOR := "RNLScenery/Town/Market/tent_friagram_pinkish_01"
const WATCH_PARTY_SETS := "ponyville:market:televisions"
const WATCH_PARTY_REMOTE := "ponyville:market:television-remote"
## Front sets first, in this order; the third (when there are three) goes on the back step.
const WATCH_PARTY_FRONT_ORDER := [WATCH_PARTY_FINDS.VINTAGE, WATCH_PARTY_FINDS.FLAT_WALL, WATCH_PARTY_FINDS.FLAT_STAND]
## Each set's width (tv_model.gd WIDTH, flat_model.gd PANEL / CONSOLE), to space them.
const WATCH_PARTY_WIDTH := {WATCH_PARTY_FINDS.VINTAGE: 1.12, WATCH_PARTY_FINDS.FLAT_WALL: 1.46, WATCH_PARTY_FINDS.FLAT_STAND: 1.7}
## The stand (metres, in its own frame: +Z is the front, toward the buyer): the front step's top
## (high enough to read its cards: playtest 2026-11-05), depth and the gap between its sets; the
## back step's top (the flatscreen's picture clears the vintage set in front), depth and width.
const WATCH_PARTY_FRONT_TOP := 0.6
const WATCH_PARTY_FRONT_DEPTH := 1.0
const WATCH_PARTY_GAP := 0.5
const WATCH_PARTY_BACK_TOP := 1.17
const WATCH_PARTY_BACK_DEPTH := 0.6
const WATCH_PARTY_BACK_WIDTH := 1.9
## The remote's little counter: this far to the right of the widest stand's end (seen from the
## front), its top this high, this big.
const WATCH_PARTY_REMOTE_GAP := 0.5
const WATCH_PARTY_REMOTE_TOP := 0.85
const WATCH_PARTY_REMOTE_SIZE := Vector2(0.55, 0.45)
## The counters' look (the market goods counter's colours).
const WATCH_PARTY_WOOD_TOP := Color("ecd49e")
const WATCH_PARTY_WOOD := Color("e2c58a")
const WATCH_PARTY_PANEL := Color("eef1f4")
## The price cards here are bigger: the seller's plaque name (catalog.gd PLAQUES: ponies don't know
## what a television is), the price, and the seller's note (the good's description, catalog.gd
## GOODS). The game's cards show only the good's name and price.
const WATCH_PARTY_CARD := Vector3(0.42, 0.004, 0.16)
const WATCH_PARTY_CARD_FONT := 20

func _place() -> void:
	super()
	_watch_party_place()

func _restock_check() -> void:
	var day := restocked_day
	super()
	if restocked_day == day: return
	for id: String in [WATCH_PARTY_SETS, WATCH_PARTY_REMOTE]:
		var display: Variant = _displays.get(id)
		if not is_instance_valid(display): continue
		var snap: Variant = (display as Node).call("snapshot")
		if snap is Dictionary and not ((snap as Dictionary).get("taken", []) as Array).is_empty():
			(display as Node).call("restock")

## Today's goods on the stand and the remote's table; each is built again when its goods change.
func _watch_party_place() -> void:
	var items := PackedStringArray(WATCH_PARTY_FINDS.market_items())
	var sets := PackedStringArray()
	for id: String in WATCH_PARTY_FRONT_ORDER:
		if id in items: sets.append(id)
	var remote := PackedStringArray([WATCH_PARTY_FINDS.REMOTE]) if WATCH_PARTY_FINDS.REMOTE in items else PackedStringArray()
	_watch_party_build(WATCH_PARTY_SETS, sets, _watch_party_layout(sets))
	_watch_party_build(WATCH_PARTY_REMOTE, remote, {})

## Where everything goes, in the stand's frame: {slots: [Transform3D] (one per set, in order),
## back: the back set's index or -1, front_width, gap_x (the middle of the front gap), back_z}.
func _watch_party_layout(sets: PackedStringArray) -> Dictionary:
	var back := 2 if sets.size() == 3 else -1
	var front: Array = []
	for index in sets.size():
		if index != back: front.append(index)
	var total := 0.0
	for index: int in front: total += float(WATCH_PARTY_WIDTH.get(sets[index], 1.5))
	total += WATCH_PARTY_GAP * maxf(front.size() - 1, 0)
	var slots: Array[Transform3D] = []
	slots.resize(sets.size())
	var x := -total * 0.5
	var gap_x := 0.0
	for n in front.size():
		var width := float(WATCH_PARTY_WIDTH.get(sets[front[n]], 1.5))
		slots[front[n]] = Transform3D(Basis.IDENTITY, Vector3(x + width * 0.5, WATCH_PARTY_FRONT_TOP, 0.0))
		x += width
		if n == 0: gap_x = x + WATCH_PARTY_GAP * 0.5
		x += WATCH_PARTY_GAP
	var back_z := -(WATCH_PARTY_FRONT_DEPTH + WATCH_PARTY_BACK_DEPTH) * 0.5
	if back >= 0: slots[back] = Transform3D(Basis.IDENTITY, Vector3(0.0, WATCH_PARTY_BACK_TOP, back_z))
	var front_width := maxf(total + 0.2, 1.4)
	return {"slots": slots, "back": back, "front_width": front_width, "gap_x": gap_x, "back_z": back_z}

## Where the remote's counter stands (in the stand's frame): past the end of the widest front step
## any set of goods makes, so it never moves and never meets the stand.
func _watch_party_remote_at() -> Vector3:
	var widest := 0.0
	var ids: Array = WATCH_PARTY_FRONT_ORDER
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			widest = maxf(widest, float(_watch_party_layout(PackedStringArray([ids[a], ids[b]])).front_width))
	return Vector3(widest * 0.5 + WATCH_PARTY_REMOTE_GAP + WATCH_PARTY_REMOTE_SIZE.x * 0.5, 0.0, 0.15)

## One of the two displays with `items`, unless it already has them.
func _watch_party_build(display_id: String, items: PackedStringArray, layout: Dictionary) -> void:
	var built: Variant = _displays.get(display_id)
	# The old one is still there until the end of the frame: the ground ray must pass through it
	# (playtest 2026-11-05: the new table stood on the old one's top, floating).
	var old_tables: Array[RID] = []
	if is_instance_valid(built):
		if PackedStringArray((built as Node).get("item_ids")) == items: return
		for node: Node in (built as Node).find_children("*", "CollisionObject3D", true, false):
			old_tables.append((node as CollisionObject3D).get_rid())
		(built as Node).queue_free()
		_displays.erase(display_id)
	if items.is_empty(): return
	var anchor := _anchor(WATCH_PARTY_ANCHOR)
	if anchor == null or not anchor.is_inside_tree(): return
	var facing := Basis(Vector3.UP, deg_to_rad(WATCH_PARTY_FACING))
	var remote := display_id == WATCH_PARTY_REMOTE
	var at: Vector3 = WATCH_PARTY_AT + facing * _watch_party_remote_at() if remote else WATCH_PARTY_AT
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 4.0, 1, old_tables)
	var hit := anchor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return   # terrain collision not streamed yet; the next pass tries again
	var ground: float = (hit.position as Vector3).y
	var display: Node3D = DISPLAY.new()
	display.name = "ShopDisplay_" + ("tv_remote" if remote else "televisions")
	display.display_id = display_id
	display.item_ids = items
	display.owned_check = _owns
	display.top_level = true
	display.build_surface = false
	if remote:
		display.columns = 1
		display.spacing = Vector2(0.4, 0.4)
		var top: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(0.0, WATCH_PARTY_REMOTE_TOP, 0.0))]
		display.slot_transforms = top
	else:
		display.spacing = Vector2(1.5, WATCH_PARTY_FRONT_DEPTH - 0.1)
		display.slot_transforms = layout.slots
	anchor.add_child(display)
	display.global_transform = Transform3D(facing, Vector3(at.x, ground, at.z))
	if remote: _watch_party_counter(display, Vector3(WATCH_PARTY_REMOTE_SIZE.x, WATCH_PARTY_REMOTE_TOP, WATCH_PARTY_REMOTE_SIZE.y), Vector3.ZERO)
	else: _watch_party_stand(display, layout)
	if _stock.has(display_id): display.restore_stock(_stock[display_id])
	display.stock_changed.connect(_remember)
	_displays[display_id] = display
	display.populate()
	_watch_party_notes(display, layout)
	print("[watch_party] %s set up at the market: %s" % ["remote counter" if remote else "television stand", ", ".join(items)])

## The stepped stand under the sets: two counters standing on the ground (the display's origin),
## the back one only when a set stands on it.
func _watch_party_stand(display: Node3D, layout: Dictionary) -> void:
	var width := float(layout.front_width)
	_watch_party_counter(display, Vector3(width, WATCH_PARTY_FRONT_TOP, WATCH_PARTY_FRONT_DEPTH), Vector3.ZERO)
	if int(layout.back) >= 0:
		_watch_party_counter(display, Vector3(WATCH_PARTY_BACK_WIDTH, WATCH_PARTY_BACK_TOP, WATCH_PARTY_BACK_DEPTH), Vector3(0.0, 0.0, float(layout.back_z)))

## A counter like the market's: a body of light wood under a top that overhangs it a little, and
## white panels set into its front. `size` is its whole width, height and depth; `foot` the
## middle of its footprint. Solid (one box) for ponies, the player and anything set on it.
func _watch_party_counter(display: Node3D, size: Vector3, foot: Vector3) -> void:
	var counter := StaticBody3D.new()
	counter.name = "WatchPartyCounter"
	counter.position = foot
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = Vector3.UP * size.y * 0.5
	counter.add_child(collision)
	var top := 0.05
	var overhang := 0.04
	var body := Vector3(size.x - overhang * 2.0, size.y - top, size.z - overhang * 2.0)
	_watch_party_box(counter, body, Vector3(0.0, body.y * 0.5, 0.0), WATCH_PARTY_WOOD)
	_watch_party_box(counter, Vector3(size.x, top, size.z), Vector3(0.0, size.y - top * 0.5, 0.0), WATCH_PARTY_WOOD_TOP)
	# The panels: about a metre each, framed by a hand's width of wood, above a low plinth.
	var count := maxi(1, roundi(body.x / 1.0))
	var frame := 0.07
	var panel := Vector2((body.x - frame * (count + 1)) / count, body.y - frame * 2.0 - 0.04)
	if panel.x > 0.05 and panel.y > 0.05:
		for n in count:
			var x := -body.x * 0.5 + frame + panel.x * 0.5 + n * (panel.x + frame)
			_watch_party_box(counter, Vector3(panel.x, panel.y, 0.012), Vector3(x, 0.04 + frame + panel.y * 0.5, body.z * 0.5 + 0.006), WATCH_PARTY_PANEL)
	display.add_child(counter)

func _watch_party_box(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	mesh.material = material
	visual.mesh = mesh
	visual.position = at
	parent.add_child(visual)

## The seller's notes on the price cards (world/shop/shop_display.gd _make_price_card makes them;
## their text is card_text, name and price), and the back set's card stood up on its step's face.
func _watch_party_notes(display: Node3D, layout: Dictionary) -> void:
	var cards: Variant = display.get("_cards")
	if not cards is Dictionary: return
	var items := load("res://world/shop/shop_items.gd")
	var catalog := load("res://mods/watch_party/catalog.gd")
	for key: Variant in (cards as Dictionary).keys():
		var card: Variant = (cards as Dictionary)[key]
		if not card is MeshInstance3D or not is_instance_valid(card): continue
		var index := int(str(key).get_slice(":", 0))
		var id := str(key).substr(str(key).find(":") + 1)
		if index == int(layout.get("back", -1)):
			# On the white panel of the back counter's front (set back 0.04 under its top, 0.012 proud).
			var face := -WATCH_PARTY_FRONT_DEPTH * 0.5 - 0.04 + 0.012 + 0.004
			var upright := Basis(Vector3.RIGHT, PI * 0.5)
			(card as Node3D).global_transform = display.global_transform * Transform3D(upright, Vector3(float(layout.gap_x), (WATCH_PARTY_FRONT_TOP + WATCH_PARTY_BACK_TOP) * 0.5, face))
		var note := str(items.call("definition", id).get("description", ""))
		var label := (card as Node).get_node_or_null("PriceLabel") as Label3D
		if note.is_empty() or label == null: continue
		var mesh: Variant = (card as MeshInstance3D).mesh
		if mesh is BoxMesh:
			var bigger := (mesh as BoxMesh).duplicate() as BoxMesh
			bigger.size = WATCH_PARTY_CARD
			(card as MeshInstance3D).mesh = bigger
		label.font_size = WATCH_PARTY_CARD_FONT
		label.width = (WATCH_PARTY_CARD.x - 0.02) / label.pixel_size
		var plaque := str(catalog.call("plaque", id))
		label.text = str(DISPLAY.card_text(id, false)).replace(str(items.call("definition", id).get("name", "")), plaque) + "\n" + note
