extends SceneTree
## Build step 4: the background houses, one scene per design (world/towns/ponyville/background/house_X_bg.scn).
## A background house is the real house seen from outside and nothing more: nopony lives in it or goes in.
## - its outside (walls, roof, door, window frames) merged into one mesh, one surface per material, with
##   identical materials shared: a handful of draws instead of a hundred nodes (the designs' own far
##   versions are kept);
## - the windows opaque: soft lilac panes, as the show draws house windows, instead of clear glass onto an
##   empty room; each pane a little larger than the real one, so it reaches in behind its frame all round
##   (the real panes stop short of the frame and showed slits of daylight), and the inside of the outer walls
##   and roof kept as a plain lilac lining, so anything that still shows past a pane is a wall, not the sky;
##   the front door shut for good;
## - no rooms (floors, room faces, light seals) and no interior script, so it is never in the
##   house_interiors group: residents, beds, furniture and the player's home grant all pass it by;
## - collision: a box over each of its floor rectangles (layout.json), walls high;
## - a small script (background/background_house.gd) that leans what is drawn by the house's own `lean`.
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/make_background_houses.gd

const OUT := "res://world/towns/ponyville/background"
const SCENES := {"a": "house_a.tscn", "b": "house_b.tscn", "c": "house_c.tscn", "d": "house_d.tscn",
	"e": "house_e.scn", "f": "house_f.scn", "g": "house_g.scn", "h": "house_h.scn"}
## Parts of a house that belong to its rooms (never seen through opaque windows and a shut door).
const INSIDE := ["RoomFace", "FloorSlab", "LightSeal", "WallFill", "EdgeFill", "Baseboard", "FittedFloor", "Interior", "InnerThreshold", "WallBase"]
## Each window pane, about its own middle. Was 1.18, so a pane reached in behind its frame all round (the real panes
## stop short of their frames and showed slits of daylight), but on arched windows, dormers and E's balcony windows its
## grown corners stood out past the frames as lilac shapes (2026-11-22 play test: "the windows have this purple-ish color
## sticking out"). The inward lining behind the panes was added after: a slit now shows lilac lining, not daylight.
const PANE_GROW := 1.0
## The window reveals (the lavender lining round each window's opening) are left out: behind an opaque pane they read
## as a thick dark band round every window, with a tab up over the beam on F's side windows and lilac shapes round E's
## windows above the balcony (2026-11-22 play test); without them a window looks as it does on the real house.
## A pane is the real house's glass slab made opaque. Where the slab reaches past its window's opening (its edges, and
## F's tab up over the beam above its side windows: spots on E's and G's too) it showed as a blue band and lilac
## shapes; on a real house the glass is clear and they never showed. A pane triangle with the house's own wall, beam or
## frame right behind it, within PANE_CLIP (model units, about 20 cm in town), is left out; panes across an opening
## have open room behind them and stay.
const PANE_CLIP := 0.02
const WALL_HEIGHT := 0.55      # model units: the collision boxes' height (a house is about 1 unit tall)
## Lighter background houses (2026-11-22 optimisation pass, recommendation 2; tools/town_planner/build/qc/
## lab_render_audit.gd): B and C are most of the background rows (74 and 43 at high density), at 23.5k and 25.8k
## triangles each, and their textured shell never got simpler with distance (its UV seams locked the simplifier: one
## distance version at an error the size of the house). They stand along streets and are seen up close, so:
## - near: every untextured surface is its own simplified version within NEAR_ERROR of the original
##   (window sashes, panes, small parts). The lilac lining behind the panes (the shell again, drawn inward) stays whole
##   up close: simplified, it folded across the door recess and hazed the front door;
## - the shell itself stays exactly as it is up close;
## - far: each surface's distance versions come from the lighter mesh; where they stall (above FAR_STALL of its
##   triangles: the shell), further versions are simplified on shape alone (welded across UV seams), which only the
##   distance versions use;
## - the switch to them comes a little earlier (LOD_BIAS).
const LIGHTER := ["a", "b", "c", "e"]     # (A and E added 2026-11-22: the most common and the heaviest of the rest)
const NEAR_ERROR := 0.0035     # model units (about 10 m to the unit in town): about 3.5 cm
## The simplifier measures its error in the model's units, but the town scales a house about 10 times, which the
## renderer's LOD choice does not see. Versions on the shape alone (they blend UVs across seams) count their error
## TOWN_SCALE times over, so they are picked only where that is too small to see (at 1x one showed at 7 m, a smear
## across the front door); the ordinary versions keep the error the base build gave them (switching as before).
## Surfaces under SMALL_PART triangles get no distance versions (the door panel's 30 triangles smeared when one did).
const TOWN_SCALE := 10.0
const SMALL_PART := 64
const FAR_STALL := 0.45
const LOD_BIAS := 0.8


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/towns/ponyville/layout.json"))
	var pane := StandardMaterial3D.new()
	pane.resource_name = "Background window (opaque lilac)"
	pane.albedo_color = Color(0.83, 0.74, 0.93)
	pane.roughness = 0.35
	pane.metallic_specular = 0.6
	var lining := StandardMaterial3D.new()
	lining.resource_name = "Background house lining (opaque lilac)"
	# pale wall white, not lilac (2026-11-22): it also shows through small holes in a design's shell (a blue-lilac
	# triangle beside G's door ornament), where on a real house the pale room behind shows
	lining.albedo_color = Color(0.9, 0.88, 0.93)
	lining.roughness = 1.0
	# the lining is the outer walls' own mesh again: only its inward faces are drawn (drawn two-sided it lies on
	# the walls themselves and the whole house turns lilac)
	lining.cull_mode = BaseMaterial3D.CULL_FRONT
	var only := OS.get_cmdline_user_args()
	for key: String in SCENES:
		if not only.is_empty() and not only.has(key): continue
		var started := Time.get_ticks_msec()
		var house: Node3D = (load("res://world/towns/ponyville/" + SCENES[key]) as PackedScene).instantiate()
		_dress_doors(house, SCENES[key].get_basename())
		var tools := {}                 # [material, vertex layout] -> SurfaceTool
		var order: Array = []
		var source_tris := 0
		var far: Node3D = house.find_child("ExtremelyDistant", true, false) as Node3D
		var range_end := 0.0
		var backings: Array = []        # [mesh, transform in the house]: kept whole (see _back_door)
		var blockers: TriangleMesh = null   # the house's own walls and frames, for _clipped (panes)
		var walls: TriangleMesh = null      # the same without the window parts (sashes)
		var windows: Array[MeshInstance3D] = []   # each window's glass (_window_boxes)
		for mi: MeshInstance3D in house.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null or not _visible(mi, house): continue
			if str(mi.name).begins_with("DoorBacking"):
				backings.append([mi.mesh, _to_house(mi, house)]); continue
			if far != null and far.is_ancestor_of(mi): continue
			var n := str(mi.name)
			var skip := false
			var is_lining := n == "ExteriorRoomFace"          # the inside face of the outer walls and roof
			for word in INSIDE:
				if word in n and not is_lining: skip = true
			var p: Node = mi.get_parent()
			while p != house and p != null:
				if str(p.name) == "HouseInterior": skip = true
				p = p.get_parent()
			if skip: continue
			if "WindowReveal" in n: continue
			range_end = maxf(range_end, mi.visibility_range_end)
			var xf := _to_house(mi, house)
			var source: Mesh = mi.mesh
			if "Glass" in n:
				windows.append(mi)
				var middle := mi.mesh.get_aabb().get_center()
				xf = xf * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * PANE_GROW), middle - middle * PANE_GROW)
				if blockers == null: blockers = _blockers(house, far, false)
				source = _clipped(mi.mesh, xf, blockers)
			elif "Sash" in n:
				# (F's middle bar runs up past its arch over the beam: on a real house too, but there clear glass in
				# front softens it; here the parts of a sash lying over the wall itself go, its frame and bars stay)
				if walls == null: walls = _blockers(house, far, true)
				source = _clipped(mi.mesh, xf, walls)
			for s in source.get_surface_count():
				var mat: Material = mi.get_active_material(s) if source == mi.mesh else source.surface_get_material(s)
				if "Glass" in n: mat = pane
				if is_lining: mat = lining
				mat = _shared(mat)
				# One surface per material AND per kind of vertex (which of normals, tangents, colours, UVs, UV2 it
				# carries): a SurfaceTool takes its vertex layout from the first mesh given to it, and parts of another
				# layout joined to it lose what it lacks. Design h's front door shares the walls' material but not
				# their layout, and came out with the wrong piece of the texture on it (play test 2026-11-16).
				var layout_bits: int = source.surface_get_format(s) & (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR
					| Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_CUSTOM0)
				var slot := [mat, layout_bits]
				if not tools.has(slot):
					var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); st.set_material(mat)
					tools[slot] = st; order.append(slot)
				(tools[slot] as SurfaceTool).append_from(source, s, xf)
				source_tris += maxi(source.surface_get_array_index_len(s), source.surface_get_array_len(s)) / 3
		# a lilac box behind each window, joined to the panes' surface (same material: no extra draw)
		var boxes := _window_boxes(house, far, windows)
		if boxes != null:
			var box_bits: int = boxes.surface_get_format(0) & (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR
				| Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_CUSTOM0)
			var box_slot := [_shared(pane), box_bits]
			if not tools.has(box_slot):
				var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); st.set_material(box_slot[0])
				tools[box_slot] = st; order.append(box_slot)
			(tools[box_slot] as SurfaceTool).append_from(boxes, 0, Transform3D.IDENTITY)
		print("  %s: gathered parts in %.1f s" % [key, (Time.get_ticks_msec() - started) / 1000.0])
		var merged_at := Time.get_ticks_msec()
		var importer := ImporterMesh.new()
		for slot: Array in order:
			var st: SurfaceTool = tools[slot]
			st.index()      # the LOD generator works on indexed surfaces only
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, slot[0])
		# Simpler versions for distance, chosen by the renderer as the house gets smaller on screen, as the real
		# houses' imported meshes have (2026-11-17: without them a background house drew more triangles than the
		# real house beside it; perf_lab.gd measured the town's street views up to a quarter heavier).
		if key in LIGHTER: importer = _lighter(importer)
		else: importer.generate_lods(60.0, 25.0, [])
		importer = _panes_whole(importer)
		var lods := 0
		for s in importer.get_surface_count(): lods = maxi(lods, importer.get_surface_lod_count(s))
		var lod_at := Time.get_ticks_msec()
		var mesh := importer.get_mesh()
		var out := Node3D.new(); out.name = "BackgroundHouse" + key.to_upper()
		out.set_script(load("res://world/towns/ponyville/background/background_house.gd"))     # its lean (build_town.py sets each house's)
		out.set_meta("background_house", true)
		out.set_meta("building_design", key)
		var body := MeshInstance3D.new(); body.name = "Exterior"; body.mesh = mesh
		if key in LIGHTER: body.lod_bias = LOD_BIAS
		if range_end > 0.0: body.visibility_range_end = range_end
		out.add_child(body); body.owner = out
		for i in backings.size():
			var backing := MeshInstance3D.new(); backing.name = "DoorBacking%d" % i
			backing.mesh = backings[i][0]; backing.transform = backings[i][1]
			backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if range_end > 0.0: backing.visibility_range_end = range_end
			out.add_child(backing); backing.owner = out
		if far != null:
			var far_copy := far.duplicate() as Node3D
			out.add_child(far_copy); far_copy.owner = out
			for c in far_copy.find_children("*", "", true, false): c.owner = out
		var col := StaticBody3D.new(); col.name = "Walls"
		out.add_child(col); col.owner = out
		var rects: Array = layout.models[key].get("floor_rectangles", [])
		for i in rects.size():
			var r: Array = rects[i]
			var shape := CollisionShape3D.new(); shape.name = "Wall%d" % i
			var box := BoxShape3D.new(); box.size = Vector3(float(r[2]) - float(r[0]), WALL_HEIGHT, float(r[3]) - float(r[1]))
			shape.shape = box
			shape.position = Vector3((float(r[0]) + float(r[2])) / 2.0, WALL_HEIGHT / 2.0, (float(r[1]) + float(r[3])) / 2.0)
			col.add_child(shape); shape.owner = out
		var packed := PackedScene.new()
		var err := packed.pack(out)
		if err == OK: err = ResourceSaver.save(packed, OUT + "/house_%s_bg.scn" % key, ResourceSaver.FLAG_COMPRESS)
		var tris := 0
		for s in mesh.get_surface_count(): tris += mesh.surface_get_array_index_len(s) / 3
		print("  times: merge %.1f s, lods %.1f s" % [(merged_at - started) / 1000.0, (lod_at - merged_at) / 1000.0])
		print("BG ", key, ": ", order.size(), " surfaces, up to ", lods, " LODs, ", tris, " triangles (from ", source_tris, "), far copy ", far != null, ", walls ", rects.size(), ", save ", err)
		house.free()
		out.free()
	quit()


## A real house's doors are finished when the game runs (hinged_door.gd _ready): the door's artwork, cut out of
## the shell as it was drawn, is swapped for a cleaned panel (door_panels/replacements.json), and an arched door
## is set back into its frame with a jamb lining the gap (ARCH_INSETS, door_frames/). A background house never
## runs that script, so the same is done here before its parts are merged: without it design h showed the raw
## cut-out, a tangle of overlapping wall triangles, where its front door should be (play test 2026-11-16).
func _dress_doors(house: Node3D, scene_name: String) -> void:
	var hinged: Script = load("res://world/buildings/hinged_door.gd")
	var insets: Dictionary = hinged.get_script_constant_map().get("ARCH_INSETS", {})
	var panels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/buildings/door_panels/replacements.json"))
	for door: Node in house.find_children("*", "AnimatableBody3D", true, false):
		if door.get_script() != hinged: continue
		var leaf := door as Node3D
		var art := leaf.get_node_or_null("OriginalDoorArtwork") as MeshInstance3D
		if art != null and art.mesh != null and panels.has(art.mesh.resource_path):
			for s in art.mesh.get_surface_count(): art.set_surface_override_material(s, null)
			art.material_override = null
			art.mesh = load(panels[art.mesh.resource_path])
		var inset_key := scene_name + ":" + str(leaf.name)
		_back_door(leaf, insets.get(inset_key, 0.0), house)
		if not insets.has(inset_key): continue
		leaf.position += leaf.transform.basis * Vector3(0, 0, -float(insets[inset_key]))
		var reveal_name := "DoorReveal" if str(leaf.name) == "FrontDoor" else str(leaf.name) + "Reveal"
		var path := "res://world/buildings/door_frames/" + inset_key.replace(":", "_") + ".res"
		var parent := leaf.get_parent() as Node3D
		if parent == null or not ResourceLoader.exists(path): continue
		var jamb := MeshInstance3D.new(); jamb.name = reveal_name + "Inset"; jamb.mesh = load(path)
		var reveal := parent.get_node_or_null(reveal_name) as MeshInstance3D
		if reveal != null and reveal.mesh != null:
			jamb.material_override = reveal.get_active_material(0)
			jamb.visibility_range_end = reveal.visibility_range_end
		parent.add_child(jamb)
		print("  ", scene_name, ": ", leaf.name, " set back ", insets[inset_key], ", jamb ", path.get_file())


## A real house has a floor and a room behind its front door; a background house has neither, so wherever the
## door does not quite fill its opening (the cleaned panels leave slivers, and an arched leaf set back into its
## frame leaves a gap round its top and foot) one looked through the house onto the grass under it (play test
## 2026-11-17: "Background G and E homes ... allowing you to see through it"). A dark board fills the opening
## just behind the leaf, as the dim hall behind a real door would.
var _backing_material: StandardMaterial3D
func _back_door(leaf: Node3D, inset: float, house: Node3D) -> void:
	var parent := leaf.get_parent() as Node3D
	var reveal_name := "DoorReveal" if str(leaf.name) == "FrontDoor" else str(leaf.name) + "Reveal"
	var reveal := parent.get_node_or_null(reveal_name) as MeshInstance3D if parent != null else null
	if reveal == null or reveal.mesh == null: return
	var box: AABB = reveal.transform * reveal.mesh.get_aabb()
	if _backing_material == null:
		_backing_material = StandardMaterial3D.new()
		_backing_material.resource_name = "Background door backing (dim hall)"
		_backing_material.albedo_color = Color(0.11, 0.085, 0.1)
		_backing_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_backing_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# A deep closed dish (2026-11-18 play test, round 8: "The black background needs to be more like a rectangular
	# dish bowl that goes around the door and connects to the doorframe, leaving no gaps to see through, and it needs
	# to be solid"): back, floor, top and both sides, from just behind the leaf (once set back) forward to the face
	# of the door's frame, a little wider and taller than the opening, so its rim is hidden in the wall and frame all
	# the way round; the open front is the doorway. Unlit, so it reads as one dark hall from every side, and drawn as
	# its own part (not merged and simplified with the house: its distance versions lost the thin box's faces). The
	# offsets are in the model's own units, about 11 times smaller than metres.
	var leaf_z: float = leaf.position.z - inset          # the leaf's front once set back
	# its back just behind the leaf (it was 0.012 behind: on E, whose leaf is set well back, the box showed through the
	# house's back; 2026-11-22 play test, round 2)
	var back := minf(leaf_z, box.position.z) - 0.004
	var front := box.end.z - 0.0015
	var grow := clampf(box.size.x * 0.03, 0.003, 0.006)
	var bottom := box.position.y - grow
	var top := box.end.y + grow
	var half := box.size.x * 0.5 + grow
	var mid := box.get_center().x
	# Its rim reached forward to the frame's face, a little wider and taller than the frame: past the opening it stood out
	# in front of the wall, a black outline round the door (2026-11-22 play test: "this weird black rectangle thing near
	# the door ... I don't want it clipping through the wall"). It stops just behind the wall's face round the doorway,
	# measured at each point along its rim (it was one depth for the whole rim, the deepest: on E, whose doorway stands
	# between a bay and a column, that put it behind the leaf and one saw through the house past the door; round 2).
	var rim: Array[Vector2] = []
	for k in BOX_STEPS: rim.append(Vector2(mid - half, lerpf(bottom, top, float(k) / BOX_STEPS)))
	for k in BOX_STEPS: rim.append(Vector2(lerpf(mid - half, mid + half, float(k) / BOX_STEPS), top))
	for k in BOX_STEPS + 1: rim.append(Vector2(mid + half, lerpf(top, bottom, float(k) / BOX_STEPS)))
	var faces := _wall_face(house, parent, rim, front, back)
	var fronts: Array[float] = []
	for f: float in faces:
		# (a little behind the wall even when it stands level with the frame, as on G: flush, its edge still showed)
		fronts.append(maxf(minf(front, f - 0.004) if is_finite(f) else front, back + 0.006))
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var at := func(u: float, y: float, d: float) -> Vector3: return Vector3(u, y, d)
	# back, then the floor (open rim along it: the doorway's foot), then round the sides and top
	var quads: Array = [[at.call(mid - half, bottom, back), at.call(mid + half, bottom, back), at.call(mid + half, top, back), at.call(mid - half, top, back)],
		[at.call(mid - half, bottom, back), at.call(mid + half, bottom, back), at.call(mid + half, bottom, fronts[-1]), at.call(mid - half, bottom, fronts[0])]]
	for k in rim.size() - 1:
		var a: Vector2 = rim[k]; var b: Vector2 = rim[k + 1]
		quads.append([at.call(a.x, a.y, back), at.call(b.x, b.y, back), at.call(b.x, b.y, fronts[k + 1]), at.call(a.x, a.y, fronts[k])])
	_add_quads(st, quads, Vector3(mid, (bottom + top) * 0.5, front + 0.05))
	st.set_material(_backing_material)
	var board := MeshInstance3D.new(); board.name = "DoorBacking"; board.mesh = st.commit()
	print("    %s door box: back %.4f, rim %.4f to %.4f (frame face %.4f)" % [leaf.name, back, fronts.min(), fronts.max(), front])
	parent.add_child(board)


## A window box behind each window (2026-11-22 play test, round 2: "Almost every single purple window on the background
## houses has a very noticeable gap that lets you see through the building ... from an angle"). A pane is the real
## house's flat glass; the wall round it is neither flat nor quite upright (and every background house leans a little),
## and with the window reveals gone nothing closed the wall's thickness round the opening, so past a pane's edge one
## looked into the empty house and out through its far side (F's front windows: a gap under the pane). As the door's
## dish (_back_door): a closed lilac box in the pane's colour round each opening, its back just behind the pane, a
## little wider and taller than the opening, and its rim reaching forward to just behind the wall's own face, measured
## by a ray at each point along the rim, so it follows a curved or tilted wall and stays hidden in it all the way
## round. Seen straight on it is the pane; from an angle, past the pane's edge, more of the same lilac.
const BOX_GROW := 0.004        # model units past the reveal (the opening and its ring) all round
const BOX_STEPS := 8           # rays along each side of the rim
const BOX_BEHIND := 0.004      # the box's back behind the pane (or the wall's deepest point round it)
const BOX_SHORT := 0.003       # its rim short of the wall's face
func _window_boxes(house: Node3D, far: Node3D, windows: Array[MeshInstance3D]) -> ArrayMesh:
	if windows.is_empty(): return null
	# the house's own outside that a rim can hide in: walls, roof, beams (not window parts, doors, rooms or the lining)
	var faces := PackedVector3Array()
	for mi: MeshInstance3D in house.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not _visible(mi, house) or (far != null and far.is_ancestor_of(mi)): continue
		var n := str(mi.name)
		if "Glass" in n or "Door" in n or "Window" in n or "Backing" in n or "Reveal" in n or "RoomFace" in n: continue
		var inside := false
		for word in INSIDE:
			if word in n: inside = true
		var p: Node = mi.get_parent()
		while p != house and p != null:
			if str(p.name) == "HouseInterior": inside = true
			p = p.get_parent()
		if inside: continue
		var xf := _to_house(mi, house)
		for v: Vector3 in mi.mesh.get_faces(): faces.append(xf * v)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var made := 0
	for glass: MeshInstance3D in windows:
		var gbox: AABB = _to_house(glass, house) * glass.mesh.get_aabb()
		var prefix := str(glass.name).replace("Glass", "")
		var reveal := house.find_child(prefix + "WindowReveal", true, false) as MeshInstance3D
		var rbox: AABB = _to_house(reveal, house) * reveal.mesh.get_aabb() if reveal != null and reveal.mesh != null else gbox.grow(0.006)
		# the pane faces along its thinnest level axis, outward (away from the house's middle)
		var along_x := gbox.size.x < gbox.size.z
		var c := gbox.get_center()
		var out := Vector3(signf(c.x) if c.x != 0.0 else 1.0, 0, 0) if along_x else Vector3(0, 0, signf(c.z) if c.z != 0.0 else 1.0)
		var side := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
		var depth := c.dot(out)
		var u0 := minf(rbox.position.dot(side), rbox.end.dot(side)) - BOX_GROW
		var u1 := maxf(rbox.position.dot(side), rbox.end.dot(side)) + BOX_GROW
		var y0 := rbox.position.y - BOX_GROW
		var y1 := rbox.end.y + BOX_GROW
		var at := func(u: float, y: float, d: float) -> Vector3: return side * u + Vector3.UP * y + out * d
		# nearby wall triangles only
		var near := PackedVector3Array()
		var zone := AABB(at.call(u0, y0, depth - 0.05), Vector3.ZERO).expand(at.call(u1, y1, depth + 0.15)).grow(0.01)
		for i in range(0, faces.size(), 3):
			if AABB(faces[i], Vector3.ZERO).expand(faces[i + 1]).expand(faces[i + 2]).intersects(zone): near.append_array([faces[i], faces[i + 1], faces[i + 2]])
		# the rim, round the rectangle: [u, y] points, corners shared by the sides that meet there
		var rim: Array[Vector2] = []
		for k in BOX_STEPS: rim.append(Vector2(lerpf(u0, u1, float(k) / BOX_STEPS), y0))
		for k in BOX_STEPS: rim.append(Vector2(u1, lerpf(y0, y1, float(k) / BOX_STEPS)))
		for k in BOX_STEPS: rim.append(Vector2(lerpf(u1, u0, float(k) / BOX_STEPS), y1))
		for k in BOX_STEPS: rim.append(Vector2(u0, lerpf(y1, y0, float(k) / BOX_STEPS)))
		var fronts: Array[float] = []
		var deepest := depth
		for r: Vector2 in rim:
			# the wall's face there: the deepest surface a ray straight in meets near the pane's depth (a beam or sill
			# standing out in front of the wall is not where the wall is)
			var from: Vector3 = at.call(r.x, r.y, depth + 0.15)
			var hit_d := INF
			for i in range(0, near.size(), 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(from, -out, near[i], near[i + 1], near[i + 2])
				if hit == null: continue
				var d := (hit as Vector3).dot(out)
				if d > depth - 0.03 and d < depth + 0.08: hit_d = minf(hit_d, d)
			fronts.append(hit_d - BOX_SHORT if is_finite(hit_d) else depth + BOX_SHORT)
			deepest = minf(deepest, fronts[-1])
		var back := deepest - BOX_BEHIND
		var inner: Vector3 = at.call((u0 + u1) * 0.5, (y0 + y1) * 0.5, depth + 0.05)   # the faces turn towards it
		var quads: Array = [[at.call(u0, y0, back), at.call(u1, y0, back), at.call(u1, y1, back), at.call(u0, y1, back)]]
		for k in rim.size():
			var a: Vector2 = rim[k]; var b: Vector2 = rim[(k + 1) % rim.size()]
			quads.append([at.call(a.x, a.y, back), at.call(b.x, b.y, back), at.call(b.x, b.y, fronts[(k + 1) % rim.size()]), at.call(a.x, a.y, fronts[k])])
		_add_quads(st, quads, inner)
		made += 1
	print("    window boxes: %d" % made)
	st.index()
	return st.commit()


## Keeps the panes and window boxes whole at every distance: a box's thin sides are what the simplifier takes first.
func _panes_whole(importer: ImporterMesh) -> ImporterMesh:
	var out := ImporterMesh.new()
	for s in importer.get_surface_count():
		var material := importer.get_surface_material(s)
		var lods := {}
		if material == null or not material.resource_name.begins_with("Background window"):
			for l in importer.get_surface_lod_count(s): lods[importer.get_surface_lod_size(s, l)] = importer.get_surface_lod_indices(s, l)
		out.add_surface(importer.get_surface_primitive_type(s), importer.get_surface_arrays(s), [], lods, material, importer.get_surface_name(s))
	return out


## The house's own outside (walls, roof, beams, frames: not glass, doors, rooms or the lining) as one TriangleMesh in
## the house's space, for the panes' clipping rays.
func _blockers(house: Node3D, far: Node3D, walls_only: bool) -> TriangleMesh:
	var faces := PackedVector3Array()
	for mi: MeshInstance3D in house.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not _visible(mi, house) or (far != null and far.is_ancestor_of(mi)): continue
		var n := str(mi.name)
		if "Glass" in n or "Door" in n or n == "ExteriorRoomFace" or (walls_only and "Window" in n): continue
		var inside := false
		for word in INSIDE:
			if word in n: inside = true
		var p: Node = mi.get_parent()
		while p != house and p != null:
			if str(p.name) == "HouseInterior": inside = true
			p = p.get_parent()
		if inside: continue
		var xf := _to_house(mi, house)
		for v: Vector3 in mi.mesh.get_faces(): faces.append(xf * v)
	var tm := TriangleMesh.new()
	tm.create_from_faces(faces)
	return tm


## A copy of a pane mesh (its own space; xf takes it to the house's) without the triangles that have the house's own
## outside right behind them (PANE_CLIP along the triangle's facing, backwards).
func _clipped(mesh: Mesh, xf: Transform3D, blockers: TriangleMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	var dropped := 0; var kept := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertices.size()))
		var keep := PackedInt32Array()
		for i in range(0, indices.size(), 3):
			var a := xf * vertices[indices[i]]; var b := xf * vertices[indices[i + 1]]; var c := xf * vertices[indices[i + 2]]
			var normal := (b - a).cross(c - a)
			if normal.length() < 1e-12: continue
			normal = normal.normalized()
			var middle := (a + b + c) / 3.0
			var hit: Dictionary = blockers.intersect_segment(middle - normal * 0.0002, middle - normal * PANE_CLIP)
			if not hit.is_empty(): dropped += 1; continue
			keep.append_array([indices[i], indices[i + 1], indices[i + 2]]); kept += 1
		if keep.is_empty(): continue
		arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	if dropped > 0: print("    %s: kept %d triangles, left out %d with the house's own outside right behind them" % [mesh.resource_path.get_file() if not mesh.resource_path.is_empty() else "window part", kept, dropped])
	return out


## How far forward (z, in the door's parent's space) the house's walls stand at each rim point [x, y] round a doorway:
## the nearest surface a ray fired straight back meets at or behind the frame's face (not a canopy or column standing
## out in front of it, as on G) and in front of the box's back. INF where none.
func _wall_face(house: Node3D, parent: Node3D, rim: Array[Vector2], front: float, back: float) -> Array[float]:
	var to_parent := _to_house(parent, house).affine_inverse()
	var lo := Vector2(INF, INF); var hi := Vector2(-INF, -INF)
	for r: Vector2 in rim: lo = Vector2(minf(lo.x, r.x), minf(lo.y, r.y)); hi = Vector2(maxf(hi.x, r.x), maxf(hi.y, r.y))
	var faces := PackedVector3Array()
	for mi: MeshInstance3D in house.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not _visible(mi, house): continue
		var n := str(mi.name)
		if "Door" in n or "Glass" in n or "Backing" in n or "Reveal" in n: continue
		var inside := false
		for word in INSIDE:
			if word in n: inside = true
		var p: Node = mi.get_parent()
		while p != house and p != null:
			if str(p.name) == "HouseInterior": inside = true
			p = p.get_parent()
		if inside: continue
		var xf := to_parent * _to_house(mi, house)
		var tri := mi.mesh.get_faces()
		for i in range(0, tri.size(), 3):
			var a := xf * tri[i]; var b := xf * tri[i + 1]; var c := xf * tri[i + 2]
			# only what lies round this doorway
			if maxf(a.x, maxf(b.x, c.x)) < lo.x - 0.01 or minf(a.x, minf(b.x, c.x)) > hi.x + 0.01: continue
			if maxf(a.y, maxf(b.y, c.y)) < lo.y - 0.01 or minf(a.y, minf(b.y, c.y)) > hi.y + 0.01: continue
			faces.append_array([a, b, c])
	var out: Array[float] = []
	for s: Vector2 in rim:
		var from := Vector3(s.x, s.y, front + 0.5)
		var nearest := -INF
		for i in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.FORWARD, faces[i], faces[i + 1], faces[i + 2])
			if hit != null and (hit as Vector3).z <= front + 0.001 and (hit as Vector3).z > back + 0.002: nearest = maxf(nearest, (hit as Vector3).z)
		out.append(nearest if nearest > -INF else INF)
	return out


## Quads [p0, p1, p2, p3] into st as two triangles each, every face turned towards inner (its normal too).
func _add_quads(st: SurfaceTool, quads: Array, inner: Vector3) -> void:
	for q: Array in quads:
		for tri: Array in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
			var p0: Vector3 = tri[0]; var p1: Vector3 = tri[1]; var p2: Vector3 = tri[2]
			var nrm := (p1 - p0).cross(p2 - p0)
			if nrm.length() < 1e-12: continue
			nrm = nrm.normalized()
			if nrm.dot(inner - (p0 + p1 + p2) / 3.0) < 0.0: nrm = -nrm; var t := p1; p1 = p2; p2 = t
			# (Godot's front faces wind clockwise: the order is flipped for it)
			for v: Vector3 in [p0, p2, p1]:
				st.set_normal(nrm); st.set_uv(Vector2.ZERO); st.add_vertex(v)


var _by_signature := {}


## The lighter house (LIGHTER): each surface's near version and its distance versions, as described above.
func _lighter(source: ImporterMesh) -> ImporterMesh:
	var out := ImporterMesh.new()
	for s in source.get_surface_count():
		var arrays := source.get_surface_arrays(s)
		var material := source.get_surface_material(s)
		var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var lining := material != null and material.resource_name.begins_with("Background house lining")
		# textured, or painted per vertex (the cleaned door panels): its look lives in its vertices, keep them all up close
		var textured: bool = (material is BaseMaterial3D and (material as BaseMaterial3D).albedo_texture != null) or not (material is BaseMaterial3D) 			or (arrays[Mesh.ARRAY_COLOR] != null and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0)
		var whole := material != null and material.resource_name.begins_with("Background window")   # (_panes_whole)
		textured = textured or whole
		var shell := textured and not lining and not whole and full.size() / 3 > 3000
		var near := full
		var near_error := 0.0
		if (lining or shell) and OS.get_cmdline_user_args().has("--chains"):
			for step: Array in _chain(arrays, true): print("      welded %.4f %d" % [step[0], (step[1] as PackedInt32Array).size() / 3])
		# (a textured or vertex-painted part keeps every triangle up close: the simplifier blends across its seams, and
		# the door's panel came out split in two colours)
		if not textured and not lining:
			for step: Array in _chain(arrays, false):
				if float(step[0]) <= NEAR_ERROR and (step[1] as PackedInt32Array).size() < near.size(): near = step[1]; near_error = float(step[0])
		var lighter := arrays.duplicate()
		lighter[Mesh.ARRAY_INDEX] = near
		var steps: Array = _chain(lighter, false) if near.size() / 3 >= SMALL_PART else []
		var least := 1.0
		for step: Array in steps: least = minf(least, float((step[1] as PackedInt32Array).size()) / maxf(near.size(), 1))
		# the shell and lining stall on their UV and normal seams: they get versions on their shape alone too
		if near.size() / 3 >= SMALL_PART and (least > FAR_STALL or shell or lining): steps.append_array(_chain(lighter, true))
		steps.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var lods := {}
		var last := near.size()
		for step: Array in steps:
			var size := (step[1] as PackedInt32Array).size()
			if float(step[0]) <= near_error or size >= last or size < 3: continue
			lods[float(step[0])] = step[1]; last = size
		out.add_surface(Mesh.PRIMITIVE_TRIANGLES, lighter, [], lods, material, source.get_surface_name(s))
		print("    surface %d (%s): %d -> %d triangles near, %d distance versions down to %d" % [s, "lining" if lining else ("shell" if shell else "part"), full.size() / 3, near.size() / 3, lods.size(), last / 3])
	return out


## The simplifier's versions of one surface: [[error, indices]], fewest triangles last. welded: on its shape alone,
## with vertices that share a position joined (UV and normal seams no longer hold it back); the indices returned
## still point at the surface's own vertices.
func _chain(arrays: Array, welded: bool) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var input := []
	var back := PackedInt32Array()
	if welded:
		input.resize(Mesh.ARRAY_MAX)
		var first := {}
		var points := PackedVector3Array()
		var remap := PackedInt32Array(); remap.resize(vertices.size())
		for i in vertices.size():
			var at := vertices[i].snapped(Vector3.ONE * 0.00001)
			if not first.has(at): first[at] = points.size(); points.append(vertices[i]); back.append(i)
			remap[i] = first[at]
		var joined := PackedInt32Array()
		for i in indices: joined.append(remap[i])
		input[Mesh.ARRAY_VERTEX] = points
		input[Mesh.ARRAY_INDEX] = joined
	else:
		input = arrays
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, input)
	importer.generate_lods(60.0, 25.0, [])
	var out := []
	for lod in importer.get_surface_lod_count(0):
		var picked := importer.get_surface_lod_indices(0, lod)
		if welded:
			var mapped := PackedInt32Array()
			for i in picked: mapped.append(back[i])
			picked = mapped
		out.append([importer.get_surface_lod_size(0, lod) * (TOWN_SCALE if welded else 1.0), picked])
	return out


## One material for every copy with the same settings (textures and shaders by identity), as
## window_batcher.gd matches them.
func _shared(material: Material) -> Material:
	if material == null: return null
	var parts: Array[String] = [material.get_class()]
	for property in material.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE): continue
		if str(property.name) in ["resource_name", "resource_path", "resource_local_to_scene", "resource_scene_unique_id"]: continue
		var value: Variant = material.get(property.name)
		parts.append(str(property.name) + "=" + (str(value.get_instance_id()) if value is Object else var_to_str(value)))
	var key := "|".join(parts)
	if not _by_signature.has(key): _by_signature[key] = material
	return _by_signature[key]


## A node's transform relative to the house root, from its parents' own transforms (the scene is not in a tree).
func _to_house(node: Node3D, house: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != house:
		if n is Node3D: xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _visible(node: Node, house: Node) -> bool:
	var n := node
	while n != null and n != house:
		if n is Node3D and not (n as Node3D).visible: return false
		n = n.get_parent()
	return true
