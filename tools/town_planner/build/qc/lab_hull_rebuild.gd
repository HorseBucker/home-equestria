extends Node
## house_shadow_hulls.gd: how long one hull cell takes to rebuild (it rebuilds when a house crosses NEAR_FULL), on the
## largest cell, and an update() walking the camera along a street. Prints HULLTIME lines.
func _ready() -> void:
	_go.call_deferred()

func _go() -> void:
	var game: Node
	for i in 2400:
		var scene := get_tree().current_scene
		game = scene if scene != null and "player" in scene else null
		if is_instance_valid(game) and is_instance_valid(game.get("player")) and is_instance_valid(WorldTerrain.instance): break
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(30.0).timeout
	var budget: Node = null
	for n: Node in get_tree().root.find_children("*", "Node", true, false):
		if n.get_script() != null and str((n.get_script() as Script).resource_path).ends_with("town_render_budget.gd"): budget = n; break
	var hulls: RefCounted = budget.get("_hulls")
	var cells: Dictionary = hulls.get("_cells")
	var biggest: Array = []; var most := 0
	for key: Array in cells:
		if (cells[key].entries as Array).size() > most: most = (cells[key].entries as Array).size(); biggest = key
	var t0 := Time.get_ticks_usec()
	for i in 10: hulls.call("_fill", biggest)
	print("HULLTIME largest cell (%d houses): %.2f ms per rebuild" % [most, (Time.get_ticks_usec() - t0) / 10000.0])
	var worst := 0.0
	hulls.call("update", Vector3(-44, -10, -180), null)   # (the jump there is not a walk)
	var times: Array = []
	for x in range(-40, 220, 4):
		var t1 := Time.get_ticks_usec()
		hulls.call("update", Vector3(x, -10, -180), null)
		var ms := (Time.get_ticks_usec() - t1) / 1000.0
		worst = maxf(worst, ms); times.append(ms)
	times.sort()
	print("HULLTIME update() walking 4 m steps along z=-180: worst %.2f ms, median %.3f ms, steps over 3 ms: %d of %d" % [worst, times[times.size() / 2], times.filter(func(v): return v > 3.0).size(), times.size()])
	get_tree().quit()
