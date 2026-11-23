extends Node
## Quits the game once a world is in (to try quit_watch.gd: user://logs/quit_trace.txt). --hang adds a node that
## blocks its own _exit_tree for 30 s, so the watcher's forced close can be seen.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	for i in 2400:
		var scene := get_tree().current_scene
		if scene != null and "player" in scene and is_instance_valid(scene.get("player")) and get_tree().root.get_node_or_null("QuitWatch"): break
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(5.0).timeout
	if "--hang" in OS.get_cmdline_user_args():
		var stuck := Node.new(); stuck.name = "StuckOnExit"
		stuck.set_script(load("res://tools/town_planner/build/qc/stuck_on_exit.gd"))
		get_tree().current_scene.add_child(stuck)
	print("QUIT now")
	get_tree().quit()
