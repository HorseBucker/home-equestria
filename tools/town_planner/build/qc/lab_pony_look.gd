extends Node
## A loaded pony (--pony ID, default cherry_berry) from the side and behind, to --shots, plus every hair-ish mesh on
## her and its material colour. Prints LOOK lines.
func _ready() -> void:
	_go.call_deferred()

func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	return args[args.find(name) + 1] if name in args else fallback

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	var id := _arg("--pony", "cherry_berry")
	var pony: Node3D = null
	for i in 120:
		var population: Node = get_tree().get_first_node_in_group("pony_populations")
		var live: Dictionary = population.get("live")
		pony = live.get(id, {}).get("actor") if live.has(id) else null
		if is_instance_valid(pony): break
		game.get("player").global_position = Vector3(-29, -10, -240)
		await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(pony): print("LOOK no ", id); get_tree().quit(); return
	game.get("player").global_position = pony.global_position + Vector3(4, 1, 4)
	pony.get_node("Navigator").set("command_owner", "lab")
	pony.get_node("Navigator").call("stay")
	await get_tree().create_timer(3.0).timeout
	for m: Node in pony.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.mesh == null: continue
		var name := str(mi.name).to_lower()
		if not (name.contains("tail") or name.contains("mane") or name.contains("hair")): continue
		var mat: Material = mi.material_override if mi.material_override else mi.get_active_material(0)
		var text := ""
		if mat is StandardMaterial3D: text = "albedo %s tex %s" % [(mat as StandardMaterial3D).albedo_color, (mat as StandardMaterial3D).albedo_texture.resource_path if (mat as StandardMaterial3D).albedo_texture else "-"]
		elif mat is ShaderMaterial:
			for p: Dictionary in (mat as ShaderMaterial).shader.get_shader_uniform_list():
				var v: Variant = (mat as ShaderMaterial).get_shader_parameter(p.name)
				if v is Color: text += "%s=%s " % [p.name, v]
			text = "shader %s %s" % [(mat as ShaderMaterial).shader.resource_path.get_file(), text]
		print("LOOK %s (%s) %s" % [pony.get_path_to(mi), mi.mesh.resource_path.get_file(), text])
	var cam := Camera3D.new(); get_tree().current_scene.add_child(cam)
	var shots := _arg("--shots", "")
	var forward := -pony.global_basis.z.normalized()
	for view: String in ["side", "behind"]:
		var dir: Vector3 = pony.global_basis.x.normalized() if view == "side" else -forward
		cam.global_position = pony.global_position + dir * 2.6 + Vector3.UP * 1.2
		cam.look_at(pony.global_position + Vector3.UP * 0.8, Vector3.UP); cam.fov = 50.0; cam.make_current()
		await get_tree().create_timer(0.4).timeout
		if not shots.is_empty(): get_viewport().get_texture().get_image().save_png(shots.path_join("look_%s_%s.png" % [id, view]))
	get_tree().quit()
