extends Node
## The wrist watch's text in a new world (watch_day.gd): shows the wrist, prints WATCH lines, quits.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	for i in 2400:
		var scene := get_tree().current_scene
		if scene != null and "player" in scene and is_instance_valid(scene.get("player")) and get_tree().root.get_node_or_null("WatchDay"): break
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(8.0).timeout
	for node: Node in get_tree().get_nodes_in_group("interaction_hint_sources"):
		if node.get("_watch") is Label3D:
			var wrist: Node3D = node.get("wrist")
			if wrist != null: wrist.show()
			for k in 5: await get_tree().process_frame
			var wd := get_tree().root.get_node_or_null("WatchDay")
			print("WATCH found case %s, watch visible %s, processing %s" % [wd.get("_case").get_ref() if wd else null, (node.get("_watch") as Label3D).is_visible_in_tree(), wd.is_processing() if wd else false])
			print("WATCH clock day %d: %s" % [int(TimeOfDay.day), (node.get("_watch") as Label3D).text])
	get_tree().quit()
