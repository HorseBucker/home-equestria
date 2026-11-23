extends RefCounted
## Shared Blender-authored shelves; stock mounts are part of the inspected model.
const MODEL := preload("res://world/buildings/boutique/shelves.scn")
const LAYOUT := preload("res://world/buildings/boutique/layout.gd")
## Play test 2026-11-16 ("push the shelves back against the walls"): they stood 1.2 m out from the wall,
## turned to face each other. Each now has its back to the wall either side of the door, centred under
## the 45 and 315 degree windows (the only wall the door, the stair foot at 80 degrees and the trim
## columns at 20/70 and 290/340 degrees leave wide enough for 2.43 m of shelf), its front toward the
## room's centre. The stock mounts are children of the model, so the shop's slots move with them.
const SPOTS := [["OutfitShelves", 315.0], ["AccessoryShelves", 45.0]]
static func install(room: Node3D) -> void:
	if room.has_node("BoutiqueShelves"): return
	var root := Node3D.new(); root.name = "BoutiqueShelves"; room.add_child(root)
	for spec: Array in SPOTS:
		var shelf: Node3D = MODEL.instantiate()
		shelf.name = spec[0]
		var visual := shelf.get_node("ShelfVisual") as MeshInstance3D
		# The model's front (stock side) is +Z; its back panel is the AABB's -Z face.
		var box := visual.get_aabb()
		var half_width := maxf(-box.position.x, box.end.x)
		var degrees: float = spec[1]
		shelf.position = LAYOUT.against_wall(LAYOUT.RADIUS, degrees, half_width, -box.position.z)
		shelf.rotation.y = deg_to_rad(degrees) + PI
		root.add_child(shelf)
		visual.visibility_range_end = 45.0
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
