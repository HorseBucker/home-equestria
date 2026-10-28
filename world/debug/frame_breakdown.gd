extends RefCounted
## F4 "total breakdown" (dev 2026-10-14: "what % is walking, what % is buildings, trees, what percent
## is tris, what percent is draw calls and then what ARE each of those 3000 draw calls ... a TOTAL
## BREAKDOWN start to finish"). Four parts, all from where the player stands:
##  1. The frame as 100%: physics steps, process (game logic + engine idle work), render submission
##     on the CPU, and an unattributed remainder; the GPU's own time beside it.
##  2. CPU by category from the game's own timers (tools/crowd_cpu_profile.gd labels, sampled for
##     CPU_SECONDS). These inclusive scopes overlap and cannot be added to find an untimed total.
##  3. Per group (ponies, houses, kit props, foliage, terrain, sky...): visible and shadow draws,
##     triangles and GPU ms, measured by hiding that group for a few frames (exact engine counts).
##  4. Inside each group, the items making its draws: every visible mesh in view counted by its
##     surfaces (MultiMesh = one draw per surface), with shadow casting, grouped by asset.
## Writes <stem>-breakdown.txt and .json; the caller shows the text.
const CPU := preload("res://tools/crowd_cpu_profile.gd")
const ENGINE_PHASES := preload("res://world/debug/frame_phase_probe.gd")
const CPU_SECONDS := 3.0
## Game timer label -> category. Physics-tick labels are scaled by steps per frame.
const CATEGORIES := {
	"Ponies: bodies and walking": ["hybrid_physics_tier0", "hybrid_physics_tier1", "hybrid_physics_tier2", "actor_physics",
		"mare_process", "solve_batch", "crowd_process", "clip_head", "tail_springs", "hair_link", "neck_link",
		"terrain_modifier", "eye_motion", "mouth", "head_process", "touch_body", "touch_body_sync", "flank_touch",
		"boop_physics", "boop_process", "clothes"],
	"Ponies: pathfinding": ["navigators", "population"],
	"Ponies: life, AI and plans": ["living_world", "day_runner", "director", "action_executor", "social_groups",
		"relationship", "affection", "kisser", "arrival", "home", "eat", "gift", "dream", "heard_speech",
		"missed_plan", "cancelled_plan", "shared_nap_surface", "shared_player_activity", "physical_contact"],
	"Foliage, trees and grass": ["biome_foliage", "vegetation_color_field", "painted_tree_batches", "ground_grass"],
	"Player (body, hands, inventory)": ["anon_body", "anon_ik", "head_guard", "inventory", "interaction_hints",
		"interactor", "grabber", "vr_rig", "briefcase", "stash"],
	"World services (rail, zones)": ["rail_network", "zone_proxies"],
	"UI and map": ["world_map_hud"],
}

static func _category(label: String) -> String:
	for category: String in CATEGORIES:
		if label in CATEGORIES[category]: return category
	if label.begins_with("hybrid_physics"): return "Ponies: bodies and walking"
	return "Other timed systems"

## Runs all four parts; returns {"text", "data"}. Hold still: groups flicker off for a few frames.
static func run(host: Node, camera: Camera3D, toast: Callable) -> Dictionary:
	var tree := host.get_tree()
	var vp := host.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	toast.call("F4: measuring CPU for %d s, hold still…" % int(CPU_SECONDS))
	var cpu := await _cpu(tree, vp)
	toast.call("F4: measuring what each group costs to draw…")
	var groups := await _groups_cost(host, vp)
	toast.call("F4: listing every draw in view…")
	var items := _items(tree, camera)
	var data := {"frame": cpu.frame, "cpu": cpu.categories, "cpu_labels": cpu.labels, "groups": groups.rows,
		"draw_total": groups.total, "items": items, "camera": [camera.global_position.x, camera.global_position.y, camera.global_position.z] if camera else []}
	return {"text": _text(data), "data": data}

# ------------------------------------------------------------------ 1 + 2: frame and CPU
## Brackets every per-tick and per-frame callback: the first node to run starts the clock, the last
## stops it (process_priority), so physics and process time are measured, not inferred.
class Stopwatch extends Node:
	var last := false
	var partner: Node
	var physics_start := 0
	var process_start := 0
	var physics_us := 0
	var process_us := 0
	var steps := 0
	func _physics_process(_delta: float) -> void:
		if not last: physics_start = Time.get_ticks_usec(); return
		physics_us += Time.get_ticks_usec() - partner.physics_start
		steps += 1
	func _process(_delta: float) -> void:
		if not last: process_start = Time.get_ticks_usec(); return
		process_us += Time.get_ticks_usec() - partner.process_start

static func _cpu(tree: SceneTree, vp: RID) -> Dictionary:
	var was := CPU.enabled
	var first := Stopwatch.new(); first.process_priority = -100000; first.process_physics_priority = -100000
	var final := Stopwatch.new(); final.last = true; final.partner = first; final.process_priority = 100000; final.process_physics_priority = 100000
	var phases := ENGINE_PHASES.new()
	tree.root.add_child(first); tree.root.add_child(final); tree.root.add_child(phases)
	# Performance TIME_* monitors publish the preceding second's maximum, not a frame average.
	await tree.create_timer(2.0).timeout
	final.physics_us = 0; final.process_us = 0; final.steps = 0
	phases.reset()
	CPU.enabled = true
	CPU.reset()
	var frames := 0; var wall := 0.0; var render_cpu := 0.0; var render_setup := 0.0; var gpu := 0.0
	var physics_peak := 0.0; var process_peak := 0.0; var navigation_peak := 0.0
	var frame_times: Array[float] = []
	var ticks_start := Engine.get_physics_frames()
	var start := Time.get_ticks_usec(); var last := start
	while Time.get_ticks_usec() - start < int(CPU_SECONDS * 1e6):
		await tree.process_frame
		var now := Time.get_ticks_usec()
		frames += 1
		var elapsed := (now - last) / 1000.0
		wall += elapsed; frame_times.append(elapsed); last = now
		physics_peak = maxf(physics_peak, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		process_peak = maxf(process_peak, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		navigation_peak = maxf(navigation_peak, Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0)
		render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		render_setup += RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var phase_report: Dictionary = phases.report(frames)
	var monitors: Dictionary = phases.monitors()
	var report := CPU.report()
	CPU.enabled = was
	var n := maxf(frames, 1.0)
	var ticks_per_frame := float(Engine.get_physics_frames() - ticks_start) / n
	var physics_callbacks := final.physics_us / 1000.0 / n
	var process_callbacks := final.process_us / 1000.0 / n
	var steps: int = maxi(final.steps, 1)
	frame_times.sort()
	var frame := {"frames": frames, "fps": 1000.0 / maxf(wall / n, .001), "wall_ms": wall / n,
		"slowest_5_percent_fps": 1000.0 / maxf(frame_times[int(frame_times.size() * .95)], .001),
		"physics_ms": physics_callbacks, "physics_step_ms": final.physics_us / 1000.0 / steps, "steps_per_frame": ticks_per_frame,
		"process_ms": process_callbacks, "render_cpu_ms": render_cpu / n, "render_setup_ms": render_setup / n, "gpu_ms": gpu / n,
		"engine_physics_peak_ms": physics_peak, "engine_process_peak_ms": process_peak, "engine_navigation_peak_ms": navigation_peak,
		"phases_ms": phase_report, "monitors": monitors,
		"timing_note": "TIME_* are last-second peaks, never subtract from callback averages. Inclusive CPU labels overlap. Residual does not identify Jolt, audio, or presentation waiting."}
	first.queue_free(); final.queue_free(); phases.queue_free()
	# This residual includes deferred skeleton/transform work, physics server, renderer setup,
	# other viewports, and waits. Separate phase spans below narrow it without inventing a cause.
	frame.unattributed_ms = frame.wall_ms - frame.physics_ms - frame.process_ms - frame.render_cpu_ms
	var labels := {}
	var categories := {}
	for label: String in report:
		if not report[label] is Dictionary: continue
		var ms: float = float(report[label].total_ms) / n
		labels[label] = {"ms": ms, "calls_per_frame": float(report[label].calls) / n, "us_per_call": float(report[label].us_per_call), "category": _category(label)}
		categories[_category(label)] = float(categories.get(_category(label), 0.0)) + ms
	var cpu_main: float = frame.physics_ms + frame.process_ms + frame.render_cpu_ms
	return {"frame": frame, "categories": categories, "labels": labels, "cpu_main_ms": cpu_main}

# ------------------------------------------------------------------ 3: draws by group (hide and measure)
static func _sample(vp: RID, frames := 4) -> Dictionary:
	var out := {"visible_draws": 0.0, "shadow_draws": 0.0, "triangles": 0.0, "gpu_ms": 0.0}
	for i in 3: await RenderingServer.frame_post_draw
	for i in frames:
		await RenderingServer.frame_post_draw
		out.visible_draws += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		out.shadow_draws += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		out.triangles += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) \
			+ RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		out.gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	for key: String in out: out[key] = float(out[key]) / frames
	return out

## Every big group the world is made of, as [name, nodes]. A node in two groups is counted once.
static func group_nodes(tree: SceneTree) -> Array:
	var out := []
	var houses: Array = []; var foundations: Array = []
	for town in tree.root.find_children("PonyvilleTown", "", true, false):
		for c in town.get_children():
			if not (c is Node3D): continue
			var n := str(c.name)
			if n.begins_with("plot_"): houses.append(c)
			elif n.begins_with("Foundation_"): foundations.append(c)
			else: out.append(["Town: " + n, [c]])
	if not houses.is_empty(): out.append(["Houses (%d)" % houses.size(), houses])
	if not foundations.is_empty(): out.append(["House foundations", foundations])
	var terrain := tree.get_first_node_in_group("world_terrain")
	if terrain != null:
		for c in terrain.get_children():
			if c is Node3D and c != terrain.get("terrain"): out.append(["Terrain: " + str(c.name), [c]])
		if terrain.get("terrain") is Node3D: out.append(["Terrain3D ground", [terrain.terrain]])
	var ponies := tree.get_nodes_in_group("sim_ponies")
	if not ponies.is_empty(): out.append(["Ponies (%d)" % ponies.size(), ponies])
	for name in ["DistantZones", "Weather", "Player", "XRPlayer", "Water", "Ocean"]:
		for n in tree.root.find_children(name, "", true, false):
			if n is Node3D: out.append([name, [n]])
	return out

static func _groups_cost(host: Node, vp: RID) -> Dictionary:
	var tree := host.get_tree()
	var base := await _sample(vp, 8)
	var before := base
	var rows := []
	for g in group_nodes(tree):
		var nodes: Array = g[1]
		var was := nodes.map(func(n): return n.visible if is_instance_valid(n) else false)
		for n in nodes: if is_instance_valid(n): n.visible = false
		var without := await _sample(vp, 8)
		for i in nodes.size(): if is_instance_valid(nodes[i]): nodes[i].visible = was[i]
		var after := await _sample(vp, 8)
		rows.append(_draw_delta(g[0], before, without, after))
		before = after
	var sky := tree.get_first_node_in_group("sky_controller")
	var sky_mat: ShaderMaterial = sky.get("_sky_material") if sky != null else null
	if sky_mat != null and sky_mat.get_shader_parameter("volume_clouds") == true:
		sky_mat.set_shader_parameter("volume_clouds", false)
		var clear := await _sample(vp, 8)
		sky_mat.set_shader_parameter("volume_clouds", true)
		var after := await _sample(vp, 8)
		rows.append(_draw_delta("Sky: volumetric clouds", before, clear, after))
	# Live-world ablations overlap and can change culling/LOD. They are not additive;
	# subtracting their sum from one baseline invents an "everything else" category.
	rows.sort_custom(func(a, b): return a.visible_draws + a.shadow_draws > b.visible_draws + b.shadow_draws)
	return {"total": base, "rows": rows}

## Adjacent A/B/A samples remove linear baseline drift, not arbitrary simulation
## changes. Keep signed estimates and raw samples so noise is visible and auditable.
static func _draw_delta(label: String, before: Dictionary, without: Dictionary, after: Dictionary) -> Dictionary:
	var row := {"group": label, "baseline_drift": {}, "unstable_metrics": [],
		"before": before, "without": without, "after": after}
	for key: String in ["visible_draws", "shadow_draws", "triangles", "gpu_ms"]:
		var delta := (float(before[key]) + float(after[key])) * 0.5 - float(without[key])
		var drift := absf(float(after[key]) - float(before[key]))
		row[key] = delta
		row.baseline_drift[key] = drift
		# Heuristic warning, not a confidence interval. A transient confined to B
		# can still evade it; a frozen diagnostic or GPU capture must confirm a hotspot.
		var floor_noise := 0.1 if key == "gpu_ms" else 1.0
		if delta < 0.0 or drift > maxf(floor_noise, absf(delta) * 0.5):
			(row.unstable_metrics as Array).append(key)
	return row

# ------------------------------------------------------------------ 4: the draws themselves
## Group label for a mesh node: the first known ancestor, else the top-level branch name.
static func _owner_group(node: Node, ponies: Dictionary) -> String:
	var n := node
	var below: Node = null
	while n != null:
		if ponies.has(n): return "Ponies"
		var name := str(n.name)
		if name.begins_with("plot_"): return "Houses"
		if name.begins_with("Foundation_"): return "House foundations"
		if name == "PonyvilleKit": return "Town: PonyvilleKit"
		if n.is_in_group("world_terrain"): return "Terrain: " + str(below.name) if below != null else "Terrain3D ground"
		if name in ["DistantZones", "Weather", "Player", "XRPlayer"]: return name
		if n.get_parent() != null and str(n.get_parent().name) == "PonyvilleTown": return "Town: " + name
		below = n
		n = n.get_parent()
	var path := str(node.get_path())
	return path.get_slice("/", 3) if path.get_slice_count("/") > 3 else path

static func _asset_key(node: GeometryInstance3D) -> String:
	var mesh: Mesh = null
	if node is MeshInstance3D: mesh = (node as MeshInstance3D).mesh
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null: mesh = (node as MultiMeshInstance3D).multimesh.mesh
	var source := mesh.resource_path.get_file() if mesh != null and not mesh.resource_path.is_empty() else ""
	if source.is_empty():
		var owner := node.owner
		source = owner.scene_file_path.get_file() if owner != null and not owner.scene_file_path.is_empty() else ""
	var name := str(node.name).rstrip("0123456789@_")
	return (source + " · " if not source.is_empty() else "") + name + (" (MultiMesh)" if node is MultiMeshInstance3D else "")

static func _items(tree: SceneTree, camera: Camera3D) -> Dictionary:
	if camera == null: return {}
	var planes := camera.get_frustum()
	var ponies := {}
	for p in tree.get_nodes_in_group("sim_ponies"): ponies[p] = true
	var shadow_reach := 0.0
	var sun := tree.root.find_children("*", "DirectionalLight3D", true, false)
	for light: DirectionalLight3D in sun:
		if light.visible and light.shadow_enabled: shadow_reach = maxf(shadow_reach, light.directional_shadow_max_distance)
	var groups := {}
	for node: Node in tree.root.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if not g.is_visible_in_tree() or (g.layers & camera.cull_mask) == 0: continue
		var surfaces := 0
		var tris := 0
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			surfaces = (g as MeshInstance3D).mesh.get_surface_count()
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null and (g as MultiMeshInstance3D).multimesh.mesh != null:
			if (g as MultiMeshInstance3D).multimesh.visible_instance_count == 0: continue
			surfaces = (g as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
		else: continue
		var box := g.global_transform * g.get_aabb()
		var distance := camera.global_position.distance_to(box.get_center())
		if g.visibility_range_end > 0.0 and distance > g.visibility_range_end + g.visibility_range_end_margin: continue
		if distance < g.visibility_range_begin - g.visibility_range_begin_margin: continue
		var shadows := g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and distance < shadow_reach + box.size.length()
		var in_view := g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and _in_frustum(box, planes)
		if not in_view and not shadows: continue
		var group := _owner_group(g, ponies)
		var key := _asset_key(g)
		if not groups.has(group): groups[group] = {}
		var entry: Dictionary = groups[group].get(key, {"nodes": 0, "visible_draws": 0, "shadow_draws": 0})
		entry.nodes += 1
		if in_view: entry.visible_draws += surfaces
		if shadows: entry.shadow_draws += surfaces
		groups[group][key] = entry
	var out := {}
	for group: String in groups:
		var rows := []
		var total := 0
		for key: String in groups[group]:
			var e: Dictionary = groups[group][key]
			rows.append({"item": key, "nodes": e.nodes, "visible_draws": e.visible_draws, "shadow_draws": e.shadow_draws})
			total += int(e.visible_draws) + int(e.shadow_draws)
		rows.sort_custom(func(a, b): return a.visible_draws + a.shadow_draws > b.visible_draws + b.shadow_draws)
		out[group] = {"draws": total, "items": rows}
	return out

static func _in_frustum(box: AABB, planes: Array[Plane]) -> bool:
	for plane: Plane in planes:
		# Fully outside one plane (normal points out of the frustum in Godot's get_frustum).
		var far_corner := Vector3(box.end.x if plane.normal.x < 0.0 else box.position.x,
			box.end.y if plane.normal.y < 0.0 else box.position.y, box.end.z if plane.normal.z < 0.0 else box.position.z)
		if plane.is_point_over(far_corner): return false
	return true

# ------------------------------------------------------------------ text
static func _text(data: Dictionary) -> String:
	var f: Dictionary = data.frame
	var lines := PackedStringArray()
	var wall: float = maxf(float(f.wall_ms), 0.001)
	lines.append("FRAME %.1f ms = %.0f FPS (slowest 5%% %.0f FPS, over %d frames)   ·   GPU %.1f ms per frame (runs alongside the CPU)" % [f.wall_ms, f.fps, f.slowest_5_percent_fps, int(f.frames), f.gpu_ms])
	lines.append("  %5.1f%%  physics callbacks  %.1f ms  (%.2f steps per frame x %.1f ms per step)" % [100.0 * f.physics_ms / wall, f.physics_ms, f.steps_per_frame, f.physics_step_ms])
	lines.append("  %5.1f%%  frame callbacks    %.1f ms  (every _process and per-frame engine node work)" % [100.0 * f.process_ms / wall, f.process_ms])
	lines.append("  %5.1f%%  render submission  %.1f ms  (CPU preparing draw calls)" % [100.0 * f.render_cpu_ms / wall, f.render_cpu_ms])
	lines.append("  %5.1f%%  unattributed       %.1f ms  (includes deferred work, physics server, render setup and waits; cause not inferred)" % [100.0 * f.unattributed_ms / wall, f.unattributed_ms])
	lines.append("ENGINE PEAKS (last-second maxima observed; not additive): physics %.2f ms, process including render %.2f ms, navigation %.2f ms" % [f.engine_physics_peak_ms, f.engine_process_peak_ms, f.engine_navigation_peak_ms])
	lines.append("Render scene/canvas setup %.2f ms/frame (inside render phase); physics active/pairs/islands %d/%d/%d" % [f.render_setup_ms, f.monitors.active_physics_objects, f.monitors.collision_pairs, f.monitors.physics_islands])
	lines.append(str(f.monitors.physics_counter_note))
	lines.append("PHASE SPANS (wall time between engine signals/callback boundaries):")
	for phase: String in f.phases_ms:
		lines.append("  %6.2f ms  %s" % [f.phases_ms[phase], phase])
	lines.append("After-physics includes deferred skeletons/transforms, navigation, physics step and interpolation. Render includes all viewports and driver work; asynchronous render mode can cross frame boundaries.")
	lines.append("")
	lines.append("CPU INCLUSIVE SCOPES BY CATEGORY (ms per frame; nested scopes overlap, DO NOT ADD)")
	var cats: Array = []
	for c: String in data.cpu: cats.append([float(data.cpu[c]), c])
	cats.sort_custom(func(a, b): return a[0] > b[0])
	for c: Array in cats:
		lines.append("  %6.2f ms  %s (inclusive scope sum)" % [c[0], c[1]])
		var subs: Array = []
		for label: String in data.cpu_labels:
			if data.cpu_labels[label].category == c[1]: subs.append([float(data.cpu_labels[label].ms), label, data.cpu_labels[label]])
		subs.sort_custom(func(a, b): return a[0] > b[0])
		for s: Array in subs.slice(0, 8):
			if s[0] < 0.005: continue
			lines.append("            %6.3f ms  %-26s %5.1f calls/frame  %6.0f us each" % [s[0], s[1], s[2].calls_per_frame, s[2].us_per_call])
	lines.append("")
	var t: Dictionary = data.draw_total
	lines.append("DRAWS %d (visible %d + shadow %d) · triangles %.2f M · GPU %.2f ms — by group (each hidden in turn)" % [t.visible_draws + t.shadow_draws, t.visible_draws, t.shadow_draws, t.triangles / 1e6, t.gpu_ms])
	lines.append("Live simulation; adjacent before/hidden/after samples. Signed estimates are not additive; UNSTABLE means baseline drift or a negative delta. Even unflagged rows need confirmation.")
	for r: Dictionary in data.groups:
		var drift: Dictionary = r.baseline_drift
		var unstable: Array = r.unstable_metrics
		lines.append("  %5d vis %5d shadow  %7.0f k tris  GPU %5.2f ms  %s%s" % [
			r.visible_draws, r.shadow_draws, r.triangles / 1000.0, r.gpu_ms, r.group,
			"  UNSTABLE: " + ", ".join(unstable) if not unstable.is_empty() else ""])
		lines.append("       baseline drift: %.1f vis / %.1f shadow / %.0f tris / %.2f GPU ms" % [
			drift.visible_draws, drift.shadow_draws, drift.triangles, drift.gpu_ms])
	lines.append("")
	lines.append("WHAT THE DRAWS ARE (meshes in view or casting shadows here, per group, biggest first)")
	var groups: Array = []
	for g: String in data.items: groups.append([int(data.items[g].draws), g])
	groups.sort_custom(func(a, b): return a[0] > b[0])
	for g: Array in groups:
		lines.append("  %s: about %d draws" % [g[1], g[0]])
		for item: Dictionary in (data.items[g[1]].items as Array).slice(0, 12):
			lines.append("      %4d vis %4d shadow  ×%-4d %s" % [item.visible_draws, item.shadow_draws, item.nodes, item.item])
	return "\n".join(lines) + "\n"
