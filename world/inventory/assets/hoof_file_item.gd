extends Node3D
## The spa's hoof file as a briefcase item ("hoof-file", world/inventory/item_catalog.gd). The model
## is hoof_file.glb: grip at the origin, blade toward -Z (spa_hands.gd BLADE_A/BLADE_B).
const MODEL := "res://world/props/spa/hoof_file.glb"


func _ready() -> void:
	var packed := load(MODEL) as PackedScene
	if packed != null: add_child(packed.instantiate())


func configure_body(_body: RigidBody3D, collision: CollisionShape3D) -> void:
	var shape := BoxShape3D.new(); shape.size = Vector3(0.035, 0.02, 0.24); collision.shape = shape
	collision.position = Vector3(0, 0, -0.09)
