extends SceneTree
## Quality control: a baked title vista's cubemap (world/ui/baked_vistas/<view>.res): size, format, layers.
func _init() -> void:
	var cube := load("res://world/ui/baked_vistas/above_ponyville.res")
	print("VISTA class ", cube.get_class() if cube != null else "null")
	if cube is Cubemap:
		print("VISTA %dx%d layers %d format %s mipmaps %s" % [cube.get_width(), cube.get_height(), cube.get_layers(), cube.get_format(), cube.has_mipmaps()])
	quit()
