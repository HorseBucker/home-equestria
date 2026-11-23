extends SceneTree
## Take named props out of the baked town scenery (world/props/ponyville/rnl_scenery.scn; the tool that bakes
## it from rnl_scenery.json is not in the source release, so both are edited).
##   godot --headless --xr-mode off --path <project> --script res://tools/town_planner/build/remove_scenery.gd -- id1 id2 ...
const SCENE := "res://world/props/ponyville/rnl_scenery.scn"

func _init() -> void:
	var ids := OS.get_cmdline_user_args()
	var packed: PackedScene = load(SCENE)
	var root: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var removed := []
	for id in ids:
		for n in root.find_children(id, "", true, false):
			if n.name == id:
				removed.append(str(root.get_path_to(n)))
				n.get_parent().remove_child(n)
				n.free()
	var out := PackedScene.new()
	var err := out.pack(root)
	if err == OK:
		err = ResourceSaver.save(out, SCENE, ResourceSaver.FLAG_COMPRESS)   # as the original
	print("REMOVED ", removed.size(), " of ", ids.size(), ": ", removed, " save ", err)
	quit()
