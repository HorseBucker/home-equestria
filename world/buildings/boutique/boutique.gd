extends Node3D
const SHELL := preload("res://world/buildings/boutique/shell.gd")
const INTERIOR := preload("res://world/buildings/boutique/interior.gd")
const HOME := preload("res://world/buildings/boutique/home.gd")
const STATIC_MERGE := preload("res://world/buildings/static_mesh_merge.gd")
const MERGE_STATIC := true
const RANGE_KIT_PIECES := true
const KIT_RANGE := 45.0
var home: Node3D
var interior: Node3D
static func attach(existing: Node3D) -> Node3D:
	var installed:=existing.get_node_or_null("BoutiqueRoomFrame/UsableBoutique") as Node3D
	if installed!=null:return installed
	var prepared:=SHELL.prepare(existing)
	var runtime:=load("res://world/buildings/boutique/boutique.gd").new() as Node3D
	runtime.name="UsableBoutique";prepared.frame.add_child(runtime)
	runtime.interior=INTERIOR.new();runtime.interior.name="BoutiqueInterior";runtime.add_child(runtime.interior)
	runtime.interior.build(prepared.layout)
	# Perf 0.1.0 (geometry): the room's structure, props, shelves and dress form stop at 45 m
	# (architecture.gd, props.gd, shelves.gd); the kit pieces beside them (rugs, pendants, vanity,
	# chest, plush) had no range and drew through the windows from anywhere in town. They stop at
	# the same 45 m now, so nothing floats past the walls' own range. false = no range on them.
	if RANGE_KIT_PIECES:
		for node: Node in runtime.interior.find_children("*", "GeometryInstance3D", true, false):
			var visual := node as GeometryInstance3D
			if visual.visibility_range_end <= 0.0: visual.visibility_range_end = KIT_RANGE
	# Perf 0.1.0 (geometry): rugs (36 petals), pendants, vanity, chest, plush and the lining's
	# still pieces as one mesh per look (static_mesh_merge.gd). false = every piece on its own.
	if MERGE_STATIC:
		STATIC_MERGE.merge(runtime.interior, ["house_furniture"], [], "MergedDecoration", STATIC_MERGE.town_shadow_floor(existing))
	runtime.home=HOME.new();runtime.home.name="HouseInterior";runtime.add_child(runtime.home)
	runtime.home.configure(prepared.layout,runtime.interior,prepared.door)
	existing.set_meta("boutique_interior",true)
	return runtime
