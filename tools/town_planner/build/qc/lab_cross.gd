extends Node
## A pony walked across a bridge: --a x,z to --b x,z (beyond each end). Logs each second where she is, her navigator's
## state and target; then the walk grid's cells along the line (height, walkable). Prints CROSS lines; quits.
var game: Node
func _ready() -> void:
	_go.call_deferred()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _go() -> void:
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await _wait(0.25)
	var args := OS.get_cmdline_user_args()
	var f := args[args.find("--a") + 1].split(","); var t := args[args.find("--b") + 1].split(",")
	var a := Vector3(float(f[0]), 0, float(f[1])); var b := Vector3(float(t[0]), 0, float(t[1]))
	a.y = WorldTerrain.instance.height_at(a); b.y = WorldTerrain.instance.height_at(b)
	game.get("player").global_position = a.lerp(b, 0.5) + Vector3(0, 2, 8)
	await _wait(25.0)
	var director: Node = get_tree().get_first_node_in_group("conversation_director")
	var executors: Dictionary = (director.get("actions") as Object).get("executors")
	var id := "golden_harvest" if executors.has("golden_harvest") else str(executors.keys()[0])
	var actor: Node3D = executors[id].get("actor")
	if actor.has_method("reset_motion"): actor.call("reset_motion", Transform3D(Basis.IDENTITY, a + Vector3.UP * 0.3))
	await _wait(3.0)
	var nav: Node = actor.get_node("Navigator")
	nav.set("command_owner", "lab"); nav.set("wander_enabled", false)
	if "--place" in args:
		b = nav.call("command_location", args[args.find("--place") + 1])
		print("CROSS destination ", b)
	if "--scale" in args: actor.set("body_scale", float(args[args.find("--scale") + 1]))
	nav.call("go_to", b, 1)
	var last := Vector3.INF
	for i in 90:
		await _wait(1.0)
		var p := actor.global_position
		var pts: PackedVector3Array = nav.get("path")
		print("CROSS %2ds at (%.1f, %.2f, %.1f) state %s has_target %s %.1f m to go; path %d points, waypoint %s, last %s; fps %d physics %.1f ms" % [i, p.x, p.y, p.z, nav.get("state"), nav.get("_has_target"), Vector2(p.x - b.x, p.z - b.z).length(), pts.size(), nav.get("_waypoint"), nav.get("last_failure"), Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
		if Vector2(p.x - b.x, p.z - b.z).length() < 1.0: print("CROSS arrived"); break
	get_tree().quit()
