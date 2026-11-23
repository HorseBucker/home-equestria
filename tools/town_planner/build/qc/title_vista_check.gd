extends SceneTree
## Quality control: the title's backdrop as the game draws it (baked_vistas.gd): flat picture, then the cubemap sky
## alone, for each view given. Saves tools/town_planner/build/out/lab/title_<view>_<flat|sky>.png.
func _init() -> void:
	_go.call_deferred()

func _go() -> void:
	for view: String in OS.get_cmdline_user_args():
		var holder := Node3D.new(); root.add_child(holder)
		var cam := Camera3D.new(); cam.fov = 50.0; holder.add_child(cam); cam.current = true
		var scenery: Node3D = (load("res://world/ui/baked_vistas.gd") as GDScript).new()
		holder.add_child(scenery); scenery.call("setup", cam, view)
		for kind: String in ["flat", "sky"]:
			if kind == "sky": (scenery.get_node("FlatPicture") as CanvasLayer).visible = false
			for i in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tools/town_planner/build/out/lab/title_%s_%s.png" % [view, kind]))
		holder.queue_free()
		await process_frame
	print("TITLE done")
	quit()
