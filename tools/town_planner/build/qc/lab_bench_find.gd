extends Node
## Benches near a point (--at x,z, default the Hayburger): where each stands, what it belongs to, the ground under its
## feet (terrain height and a physics ray down from above, the bench itself excluded). Prints BENCH lines.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	var arrival: Variant = game.get("arrival")
	if arrival is Object and (arrival as Object).has_method("skip_to_free_home"): (arrival as Object).call("skip_to_free_home")
	var args := OS.get_cmdline_user_args()
	var at := Vector2(-9.84, -188.96)
	if "--at" in args: var parts: PackedStringArray = args[args.find("--at") + 1].split(","); at = Vector2(float(parts[0]), float(parts[1]))
	var joint := get_tree().root.find_child("burger_joint_01", true, false) as Node3D
	if joint != null and not "--at" in args:
		at = Vector2(joint.global_position.x, joint.global_position.z)
		print("BENCH burger_joint_01 at ", joint.global_position, " path ", get_tree().root.get_path_to(joint))
	game.get("player").global_position = Vector3(at.x, -8, at.y + 8)
	await get_tree().create_timer(30.0).timeout
	for n: Node in get_tree().root.find_children("*", "Node3D", true, false):
		var label := (str(n.name) + " " + n.scene_file_path).to_lower()
		if not ("bench" in label or "table" in label or "picnic" in label): continue
		var p := (n as Node3D).global_position
		if Vector2(p.x, p.z).distance_to(at) > 25.0: continue
		var parent := n.get_parent()
		if parent != null and ("table" in (str(parent.name) + parent.scene_file_path).to_lower() or "bench" in (str(parent.name) + parent.scene_file_path).to_lower()): continue
		if "HouseInterior" in str(get_tree().root.get_path_to(n)) or "Hayburger" in str(get_tree().root.get_path_to(n)): continue
		var aabb := AABB()
		var first := true
		for m: Node in n.find_children("*", "VisualInstance3D", true, false):
			var b: AABB = (m as VisualInstance3D).global_transform * (m as VisualInstance3D).get_aabb()
			aabb = b if first else aabb.merge(b); first = false
		var ground := WorldTerrain.instance.height_at(p)
		var corners := []
		for c in [Vector2(aabb.position.x, aabb.position.z), Vector2(aabb.end.x, aabb.position.z), Vector2(aabb.position.x, aabb.end.z), Vector2(aabb.end.x, aabb.end.z)]:
			corners.append(snappedf(WorldTerrain.instance.height_at(Vector3(c.x, 0, c.y)), 0.001))
		print("BENCH %s scene %s path %s at %s bottom %.3f terrain %.3f corners %s" % [n.name, n.scene_file_path, get_tree().root.get_path_to(n), p.snapped(Vector3.ONE * 0.01), aabb.position.y, ground, corners])
	get_tree().quit()
