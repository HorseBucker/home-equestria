extends Node
## Background houses' front doors beside a real house's (2026-11-18 play test: background E and G houses showed
## through round the door). For each design given, the nearest real house and the nearest background one are
## pictured at their front door from straight on and from an angle.
##   godot --xr-mode off --resolution 1280x720 --path <project> -- --new-game --skip-title --weather clear --lab res://tools/town_planner/build/qc/lab_bgdoor.gd [--designs e,g]
## Pictures: tools/town_planner/build/out/lab/bgdoor_<design>_<real|bg>_<view>.png. Prints BGDOOR lines. Quits.
var game: Node
var cam: Camera3D


func _ready() -> void:
	_go.call_deferred()


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var idle_menu: Variant = game.get("pause_menu") if is_instance_valid(game) else null
		if is_instance_valid(idle_menu): (idle_menu as Object).set("_last_input_msec", Time.get_ticks_msec())
		if get_tree().paused: get_tree().paused = false
		if is_instance_valid(cam) and not cam.current: cam.make_current()
		await get_tree().process_frame


func _go() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void: print("BGDOOR watchdog"); get_tree().quit())
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Node and (arrival as Node).has_method("skip_to_free_home"): await (arrival as Node).skip_to_free_home()
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.hours = 12.0; tod.paused = true
	var args := OS.get_cmdline_user_args()
	var designs := (args[args.find("--designs") + 1] if "--designs" in args else "e,g").split(",")
	var town := game.get_node("Zones/PonyvilleTown")
	var suffix := ""
	if "--no-lod" in args: get_viewport().mesh_lod_threshold = 0.0; suffix = "_nolod"
	var player: Node3D = game.get("player")
	cam = Camera3D.new(); cam.fov = 55.0; game.add_child(cam)
	for d: String in designs:
		var real: Node3D = null; var bg: Node3D = null
		for child: Node in town.get_children():
			if real == null and str(child.name).begins_with("plot_") and str(child.get_meta("building_design", "")) == d: real = child
		for child: Node in town.get_node("BackgroundHouses").get_children():
			if bg == null and (child as Node3D).scene_file_path.ends_with("house_%s_bg.scn" % d): bg = child
		if real == null or bg == null: print("BGDOOR ", d, " missing"); continue
		var door := real.get_node_or_null("FrontDoor") as Node3D
		if door == null: print("BGDOOR ", d, " real has no FrontDoor"); continue
		# the door's spot in the house's own frame, unscaled (the two are scaled 0.95 and 0.9 of the design)
		var local := real.to_local(door.global_position) * (real.global_basis.get_scale().x)
		var out := (real.global_basis.orthonormalized().inverse() * door.global_basis.z).normalized()
		for pair: Array in [["real", real], ["bg", bg]]:
			var house: Node3D = pair[1]
			var frame := Transform3D(house.global_basis.orthonormalized(), house.global_position)
			var k := house.global_basis.get_scale().x / real.global_basis.get_scale().x
			var at := frame * (local * k / real.global_basis.get_scale().x * real.global_basis.get_scale().x)
			at = frame * (local * k)
			var facing := frame.basis * out
			player.global_position = at + facing * 6.0 + Vector3.UP * 0.3
			await _wait(4.0)
			var side := frame.basis.x.normalized()
			for view: Array in [["front", facing * 3.4 + Vector3.UP * 1.2], ["angle", facing * 2.0 + side * 2.2 + Vector3.UP * 1.0], ["low", facing * 2.0 - side * 2.2 + Vector3.UP * 1.0]]:
				cam.look_at_from_position(at + Vector3(view[1]), at + Vector3.UP * 1.0, Vector3.UP)
				await _wait(1.5)
				get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tools/town_planner/build/out/lab/bgdoor_%s_%s_%s%s.png" % [d, pair[0], view[0], suffix]))
			print("BGDOOR %s %s %s door at %s" % [d, pair[0], house.name, at])
	print("BGDOOR done")
	get_tree().quit()
