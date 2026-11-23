extends SceneTree
## Every mesh in a hair scene and its surfaces' materials (albedo, texture, shader colour params). Prints HAIR lines.
## Run: godot --headless --script res://tools/town_planner/build/qc/probe_hair_colors.gd -- <scene path>
func _init() -> void:
	var path := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "res://world/characters/background/cherry_berry_hair.scn"
	var root: Node = (load(path) as PackedScene).instantiate()
	for mesh: Node in root.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		for s in (m.mesh.get_surface_count() if m.mesh else 0):
			var mat: Material = m.get_active_material(s)
			var text := "none"
			if mat is StandardMaterial3D:
				text = "standard albedo %s tex %s" % [(mat as StandardMaterial3D).albedo_color, (mat as StandardMaterial3D).albedo_texture.resource_path if (mat as StandardMaterial3D).albedo_texture else "-"]
			elif mat is ShaderMaterial:
				var bits: Array = []
				for p: Dictionary in (mat as ShaderMaterial).shader.get_shader_uniform_list():
					var v: Variant = (mat as ShaderMaterial).get_shader_parameter(p.name)
					if v is Color or v is Texture2D: bits.append("%s=%s" % [p.name, v.resource_path if v is Texture2D else str(v)])
				text = "shader %s %s" % [(mat as ShaderMaterial).shader.resource_path.get_file(), ", ".join(bits)]
			print("HAIR %s surface %d [%s]: %s" % [root.get_path_to(m), s, mat.resource_name if mat else "", text])
	quit()
