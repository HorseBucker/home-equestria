extends SceneTree
## Mirror a baked title vista's faces (capture_vistas.gd, when its check picked the other way): -- <view>...
func _init() -> void:
	for view: String in OS.get_cmdline_user_args():
		var path := "res://world/ui/baked_vistas/%s.res" % view
		var cube := load(path) as Cubemap
		var layers: Array[Image] = []
		for i in cube.get_layers():
			var image := cube.get_layer_data(i)
			image.decompress()
			image.clear_mipmaps()
			image.flip_x()
			image.generate_mipmaps()
			image.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
			layers.append(image)
		var out := Cubemap.new(); out.create_from_images(layers)
		print("FLIP %s save %s" % [view, ResourceSaver.save(out, path, ResourceSaver.FLAG_COMPRESS)])
	quit()
