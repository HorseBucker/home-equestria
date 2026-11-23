extends Node
## Round 11 checks (2026-11-19): the town density's own ground (--at x,z: the terrain's height there), and the log
## lines of the round's runtime pieces. Prints R11 lines; quits.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var args := OS.get_cmdline_user_args()
	var at := args[args.find("--at") + 1].split(",") if "--at" in args else PackedStringArray(["0", "0"])
	var spot := Vector3(float(at[0]), 0, float(at[1]))
	game.get("player").global_position = spot + Vector3(0, 30, 0)
	await get_tree().create_timer(20.0).timeout
	print("R11 density %s; terrain at %s: %.2f" % [preload("res://world/towns/ponyville/town_density.gd").current(), spot, WorldTerrain.instance.height_at(spot)])
	get_tree().quit()
