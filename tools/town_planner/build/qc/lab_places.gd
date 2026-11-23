extends Node
## The place directory's entries whose id or label holds --find (place_directory.gd), and the scenery node's metas.
## Prints PLACE lines; quits.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(20.0).timeout
	var args := OS.get_cmdline_user_args()
	var find := args[args.find("--find") + 1].to_lower()
	var dir := preload("res://world/navigation/place_directory.gd")
	var all: Array = dir.entries(get_tree())
	print("PLACE %d entries" % all.size())
	for e: Dictionary in all:
		if str(e.id).to_lower().contains(find) or str(e.label).to_lower().contains(find): print("PLACE ", e.id, " | ", e.label, " | ", e.position)
	for n: Node in get_tree().root.find_children("*" + find + "*", "", true, false):
		print("NODE %s groups %s ai_id '%s' ai_label '%s'" % [n.get_path(), n.get_groups(), n.get_meta("ai_id", ""), n.get_meta("ai_label", "")])
	if "--from" in args:
		var xz := args[args.find("--from") + 1].split(",")
		for line: String in dir.prompt_lines(get_tree(), Vector3(float(xz[0]), -12, float(xz[1])), 20): if " of you" in line: print("LINE ", line)
	get_tree().quit()
