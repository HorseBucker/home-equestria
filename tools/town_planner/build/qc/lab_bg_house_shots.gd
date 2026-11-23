extends Node
## Pictures of street-side background houses (B at (45.2, -188.8), C at (71.6, -203.4)) from fixed views, for before /
## after comparisons of their meshes: --shots DIR, --tag NAME. Prints BGSHOT lines.
const HOUSES := {"a": Vector2(58.76, -163.02), "b": Vector2(45.21, -188.81), "c": Vector2(71.59, -203.43), "e": Vector2(-10.4, -140.85),
	"f": Vector2(-4.19, -147.55), "g": Vector2(74, -164.97), "h": Vector2(54.21, -231.05)}

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
	game.get("player").global_position = Vector3(55, -10, -190)
	await get_tree().create_timer(20.0).timeout
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	if tod != null: tod.set("hours", 11.0)
	var weather: Node = get_node_or_null("/root/Weather")
	if weather != null and weather.has_method("set_clear"): weather.call("set_clear")
	var cam := Camera3D.new(); get_tree().current_scene.add_child(cam); cam.fov = 60.0
	print("BGSHOT mesh_lod_threshold ", get_viewport().mesh_lod_threshold)
	if "--lod0" in OS.get_cmdline_user_args(): get_viewport().mesh_lod_threshold = 0.0
	var shots := _arg("--shots", ""); var tag := _arg("--tag", "x")
	for key: String in HOUSES:
		var want: Vector2 = HOUSES[key]
		var house: Node3D = null; var best := 1e9
		for n: Node in get_tree().root.find_children("*", "Node3D", true, false):
			if not n.has_meta("background_house"): continue
			var d := Vector2((n as Node3D).global_position.x - want.x, (n as Node3D).global_position.z - want.y).length()
			if d < best: best = d; house = n
		if house == null or best > 3.0: print("BGSHOT no house near ", want); continue
		var c := house.global_position
		var z := house.global_basis.z.normalized(); var x := house.global_basis.x.normalized()
		var views := {"front7": [c + z * 7.0 + Vector3.UP * 2.0, c + Vector3.UP * 3.0], "back7": [c - z * 7.0 + Vector3.UP * 2.0, c + Vector3.UP * 3.0],
			"left7": [c + x * 7.0 + Vector3.UP * 2.0, c + Vector3.UP * 3.0], "right7": [c - x * 7.0 + Vector3.UP * 2.0, c + Vector3.UP * 3.0],
			"oblique20": [c + (z + x).normalized() * 20.0 + Vector3.UP * 3.0, c + Vector3.UP * 3.5],
			"above": [c + z * 6.0 + Vector3.UP * 11.0, c + Vector3.UP * 5.0]}
		for v: String in views:
			game.get("player").global_position = views[v][0] + Vector3(0, -1.5, 0)
			cam.global_position = views[v][0]; cam.look_at(views[v][1], Vector3.UP); cam.make_current()
			await get_tree().create_timer(1.5).timeout
			get_viewport().get_texture().get_image().save_png(shots.path_join("bg_%s_%s_%s.png" % [key, v, tag]))
		print("BGSHOT %s house %s at %s" % [key, house.name, c.round()])
	get_tree().quit()
