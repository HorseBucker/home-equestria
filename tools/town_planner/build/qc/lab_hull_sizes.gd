extends Node
## The render budget's statistics and, per real house design, its exterior's triangles against its occluder hull's.
## Prints HULL lines.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(40.0).timeout
	var budget: Node = null
	for n: Node in get_tree().root.find_children("*", "Node", true, false):
		if n.get_script() != null and str((n.get_script() as Script).resource_path).ends_with("town_render_budget.gd"): budget = n; break
	print("HULL statistics ", budget.get("statistics") if budget else "no budget")
	var seen := {}
	var town: Node = budget.get("town")
	for plot: Node in town.get_children():
		if not str(plot.name).begins_with("plot_"): continue
		var ext := plot.find_child("Exterior", true, false) as MeshInstance3D
		if ext == null or ext.mesh == null or seen.has(ext.mesh): continue
		seen[ext.mesh] = true
		var full := 0
		for s in ext.mesh.get_surface_count(): full += maxi(ext.mesh.surface_get_array_index_len(s), ext.mesh.surface_get_array_len(s)) / 3
		var occ: OccluderInstance3D = ext.find_child("HouseOccluder", false, false) as OccluderInstance3D
		var hull := (occ.occluder as ArrayOccluder3D).indices.size() / 3 if occ and occ.occluder is ArrayOccluder3D else -1
		var up: Node = ext
		while up != null and up.scene_file_path.is_empty(): up = up.get_parent()
		print("HULL %s exterior %d tris, %d surfaces, hull %d tris" % [up.scene_file_path.get_file() if up else "?", full, ext.mesh.get_surface_count(), hull])
	get_tree().quit()
