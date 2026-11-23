extends Node
## Street lamps stay outside (2026-11-19 play test: "Street lamps bleed through buildings ... the light comes into the
## house, making it not as enjoyable to watch movies ... in the dark at night"). The lamps cast no shadows (one shadow
## map per lamp would cost too much), so their light went through walls. They already leave out render layer 17
## (street_lamps.gd, kit_lamp.gd, zone_processor.gd: "House interiors use their own light sources"), but only the
## floors and window frames were on it. Here everything that belongs to a house's room joins it: whatever is drawn
## under a HouseInterior node, and the room surfaces marked house_lighting_shell "room"; furniture set out at home
## joins it in home_furnishing.gd configure. The room's own lamps, the sun and the sky still light it.
## (Ponies standing in a room are not on it: near a window one may still catch a little lamplight.)

const LAYER := 1 << 16
const NAME := "InteriorLightLayer"


static func attach(town: Node) -> void:
	if town.get_node_or_null(NAME) != null: return
	var node: Node = (load("res://world/towns/ponyville/interior_light_layer.gd") as GDScript).new()
	node.name = NAME
	town.add_child(node)


func _ready() -> void:
	get_tree().node_added.connect(_added)
	_sweep.call_deferred()


## Everything already built.
func _sweep() -> void:
	var count := 0
	for interior: Node in get_tree().get_nodes_in_group("house_interiors"):
		for node: Node in interior.find_children("*", "GeometryInstance3D", true, false):
			if _put(node as GeometryInstance3D): count += 1
		if interior.get_parent() != null:
			for node: Node in interior.get_parent().find_children("*", "GeometryInstance3D", true, false):
				if str(node.get_meta("house_lighting_shell", "")) == "room" and _put(node as GeometryInstance3D): count += 1
	print("[town] %d indoor surfaces kept out of the street lamps' light" % count)


## Each piece as it is built: in a room, or a room surface.
func _added(node: Node) -> void:
	if not node is GeometryInstance3D: return
	if str(node.get_meta("house_lighting_shell", "")) == "room":
		_put(node as GeometryInstance3D); return
	var at: Node = node.get_parent()
	for i in 14:
		if at == null: return
		if str(at.name) == "HouseInterior" and at.is_in_group("house_interiors"):
			_put(node as GeometryInstance3D); return
		at = at.get_parent()


static func _put(node: GeometryInstance3D) -> bool:
	if node == null or node.layers == LAYER: return false
	node.layers = LAYER
	return true
