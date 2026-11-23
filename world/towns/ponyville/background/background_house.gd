extends Node3D
## A background house (tools/town_planner/build/make_background_houses.gd): the outside of a house and nothing more.
## The show draws Ponyville's houses a little askew; `lean` is how far this one's walls lean, as a sideways shift
## per unit of height in the house's own space (tools/town_planner/plan_geometry.py house_leans; build_town.py
## writes each house its own). It is a shear of what is drawn: the foot of the house stays flat on its ground and
## where it was, the collision stays upright.
@export var lean := Vector2.ZERO

func _ready() -> void:
	if lean == Vector2.ZERO: return
	var shear := Transform3D(Basis(Vector3.RIGHT, Vector3(lean.x, 1.0, lean.y), Vector3.BACK), Vector3.ZERO)
	for child in get_children():
		if child is Node3D and not (child is CollisionObject3D): (child as Node3D).transform = shear * (child as Node3D).transform
