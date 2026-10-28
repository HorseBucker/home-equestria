extends Node
## Dinnerbone: the example mod. Every pony is drawn upside down, standing on her ears with her
## hooves in the air, and walks, sits, flies and talks like that. Her body, collision and AI are
## untouched; only her model node (the visual under her ModelPivot) is turned over.

const PONY := "res://world/characters/locomotion/pony_locomotion.gd"

## pony -> [model node already turned over, its transform before], so a rebuilt model gets
## turned too and switching the mod off turns them back.
var _turned: Dictionary = {}


func _ready() -> void:
	Mods.on_node(PONY, _turn)


func _process(_delta: float) -> void:
	# A pony's model is rebuilt when she changes clothes or her rig reloads.
	for pony: Variant in _turned.keys():
		if not is_instance_valid(pony): _turned.erase(pony); continue
		if pony.get("_model") != _turned[pony][0]: _turn(pony)


func _turn(pony: Node) -> void:
	var model: Variant = pony.get("_model")
	var skeleton: Variant = pony.get("skeleton")
	if not model is Node3D or not skeleton is Skeleton3D or not is_instance_valid(model): return
	if _turned.has(pony) and _turned[pony][0] == model: return
	var before := (model as Node3D).transform
	# Her height in model space, from the highest bone at rest (the ear tips).
	var to_model: Transform3D = (model as Node3D).global_transform.affine_inverse() * (skeleton as Skeleton3D).global_transform
	var height := 0.0
	for bone in (skeleton as Skeleton3D).get_bone_count():
		height = maxf(height, (to_model * (skeleton as Skeleton3D).get_bone_global_rest(bone).origin).y)
	# Turn over about her forward axis, then lift so the ears touch the ground.
	(model as Node3D).transform = Transform3D(Basis(Vector3.BACK, PI), Vector3(0, height, 0)) * (model as Node3D).transform
	_turned[pony] = [model, before]


## Switched off in Settings → Mods: every pony stands on her hooves again.
func _exit_tree() -> void:
	for pony: Variant in _turned:
		var entry: Array = _turned[pony]
		if is_instance_valid(pony) and is_instance_valid(entry[0]) and pony.get("_model") == entry[0]:
			(entry[0] as Node3D).transform = entry[1]
	_turned.clear()
