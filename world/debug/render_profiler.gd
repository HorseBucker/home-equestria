extends CanvasLayer
## F11: snapshot inspector. F4: performance snapshot (FPS, GPU, physics, draws, triangles, pony
## tiers, full scene inventory) saved as frame-*.txt + .scene.json; requests one GPU frame; then the
## total breakdown (frame_breakdown.gd: CPU by category, draws/triangles/GPU by group, the draws
## themselves) shown here and saved as frame-*-breakdown.txt/.json.
## Shift+F11: "what costs in this view": hides each big group in turn for a few frames and
## reports the draws, triangles and GPU ms each one costs from where you stand (volumetric
## clouds included), sorted, on screen and saved as view-*.json next to the other reports.
const INVENTORY = preload("res://world/debug/render_inventory.gd")
const BREAKDOWN = preload("res://world/debug/frame_breakdown.gd")
var report: TextEdit
var _breaking_down := false
var panel: PanelContainer
var summary: Label
var listing: Tree
var camera: Camera3D
var saved_mouse := Input.MOUSE_MODE_VISIBLE
var latest := {}
var message := ""
var capture_pending := false
var folder := "user://performance/render"

func _ready() -> void:
	layer = 110
	if not OS.get_environment("EQ_RENDER_PROFILE_DIR").is_empty(): folder = OS.get_environment("EQ_RENDER_PROFILE_DIR")
	panel = PanelContainer.new(); panel.position = Vector2(30,90); panel.size = Vector2(1250,660); panel.visible = false; add_child(panel)
	var column := VBoxContainer.new(); panel.add_child(column)
	summary = Label.new(); column.add_child(summary)
	var buttons := HBoxContainer.new(); column.add_child(buttons)
	for entry in [["Measure this view · Shift+F11",measure_view],["Refresh inventory",refresh],["Capture GPU frame · F4",capture],["Open reports",open_reports],["Close · F11",toggle]]:
		var button := Button.new(); button.text = entry[0]; button.pressed.connect(entry[1]); buttons.add_child(button)
	report = TextEdit.new(); report.editable = false; report.visible = false; report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report.add_theme_font_override("font", SystemFont.new()); report.add_theme_font_size_override("font_size", 13)
	(report.get_theme_font("font") as SystemFont).font_names = PackedStringArray(["Monospace", "DejaVu Sans Mono"])
	column.add_child(report)
	listing = Tree.new(); listing.columns = 4; listing.column_titles_visible = true; listing.hide_root = true; listing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in 4: listing.set_column_title(i,["Node / surface","Base tris × instances","Visible in tree","Material"][i])
	listing.set_column_expand(0,true); listing.set_column_custom_minimum_width(0,550)
	column.add_child(listing)
	var timer := Timer.new(); timer.wait_time = 1.0; timer.timeout.connect(check_capture); add_child(timer); timer.start()
	print("[render profiler] F11 inventory; F4 capture; reports ",ProjectSettings.globalize_path(folder))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_F11 and event.shift_pressed: measure_view(); get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F11: toggle(); get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F4: capture(); get_viewport().set_input_as_handled()

func toggle() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		saved_mouse = Input.mouse_mode; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; refresh()
	elif Input.mouse_mode == Input.MOUSE_MODE_VISIBLE: Input.mouse_mode = saved_mouse

func refresh() -> void:
	camera = get_viewport().get_camera_3d()
	latest = INVENTORY.snapshot(get_tree().root,camera)
	if not latest.has("rows"): summary.text = "Inventory snapshot failed; see the game log."; return
	listing.clear(); var base := listing.create_item()
	for row: Dictionary in latest.rows:
		var item := listing.create_item(base)
		item.set_text(0,row.node+" / "+str(row.surface))
		item.set_text(1,"%d × %d = %d"%[row.base_triangles,row.instances,row.instanced_base_triangles])
		item.set_text(2,"yes" if row.visible_in_tree else "hidden")
		item.set_text(3,JSON.stringify(row.material))
		var tooltip := JSON.stringify(row,"  ")
		for i in 4: item.set_tooltip_text(i,tooltip)
	var totals: Dictionary = latest.engine_totals
	summary.text = "ENGINE FRAME: visible %d draws / %d primitives · shadows %d draws / %d primitives\nScene inventory below is BASE topology, not submitted GPU cost. %d geometry nodes require GPU capture.\n%s"%[totals.visible.draw_calls,totals.visible.primitives,totals.shadow.draw_calls,totals.shadow.primitives,latest.unexposed_geometry.size(),message]

func capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var request := folder.path_join("request.json")
	if FileAccess.file_exists(request):
		message = "A capture request is already pending."; if panel.visible: refresh()
		return
	camera = get_viewport().get_camera_3d()
	var stats := _stats()  # before the inventory walk, which itself takes a frame's worth of time
	var snapshot := INVENTORY.snapshot(get_tree().root,camera,true)
	snapshot["stats"] = stats
	var stem := "frame-%d-%d"%[int(Time.get_unix_time_from_system()),Engine.get_process_frames()]
	var path := folder.path_join(stem+".scene.json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: message = "Could not write report: "+str(FileAccess.get_open_error()); return
	file.store_string(JSON.stringify(snapshot)); file.close()
	var text := _stats_text(stats, snapshot.get("engine_totals", {}))
	var summary_file := FileAccess.open(folder.path_join(stem+".txt"),FileAccess.WRITE)
	if summary_file != null: summary_file.store_string(text); summary_file.close()
	print("[render profiler] snapshot ",ProjectSettings.globalize_path(folder.path_join(stem+".txt")),"\n",text)
	_toast("Performance snapshot saved: "+stem)
	if OS.get_environment("EQ_RENDER_PROFILE_ACTIVE") == "1":
		var pending := FileAccess.open(request+".tmp",FileAccess.WRITE)
		pending.store_string(JSON.stringify({"scene":ProjectSettings.globalize_path(path),"stem":stem})); pending.close()
		DirAccess.rename_absolute(ProjectSettings.globalize_path(request+".tmp"),ProjectSettings.globalize_path(request))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join("status.json")))
		capture_pending = true
		message = "GPU capture requested. Report will appear in "+ProjectSettings.globalize_path(folder)
	else: message = "Scene inventory saved. Exact GPU capture needs ./run.sh --gpu-profile at launch."
	print("[render profiler] ",message)
	if panel.visible: refresh()
	_breakdown(stem)

## The total breakdown (frame_breakdown.gd), shown in the panel and saved beside the snapshot.
func _breakdown(stem: String) -> void:
	if _breaking_down: return
	_breaking_down = true
	var result: Dictionary = await BREAKDOWN.run(self, get_viewport().get_camera_3d(), _toast)
	_breaking_down = false
	var text: String = result.text
	var base := folder.path_join(stem + "-breakdown")
	var out := FileAccess.open(base + ".txt", FileAccess.WRITE)
	if out != null: out.store_string(text); out.close()
	var json := FileAccess.open(base + ".json", FileAccess.WRITE)
	if json != null: json.store_string(JSON.stringify(result.data, "\t")); json.close()
	print("[render profiler] breakdown ", ProjectSettings.globalize_path(base + ".txt"), "\n", text)
	report.text = text; report.visible = true; listing.visible = false
	summary.text = "TOTAL BREAKDOWN · saved " + ProjectSettings.globalize_path(base + ".txt") + "   (F11 closes)"
	if not panel.visible: toggle()
	_toast("Breakdown ready (F11 to close)")

## Everything the F10 counter shows (its rolling FPS/p95 too) plus the pony tiers, at the
## moment F4 was pressed (dev 2026-09-25: a performance "screenshot").
func _stats() -> Dictionary:
	var out := {}
	var hud := get_tree().root.find_child("DebugFPS", true, false)
	if hud != null and "summary" in hud: out = (hud.summary as Dictionary).duplicate()
	else:
		out = {"fps": Engine.get_frames_per_second(),
			"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
			"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"triangles": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0}
	out["objects"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var crowd := get_tree().get_first_node_in_group(&"pony_crowd")
	if crowd != null and "statistics" in crowd: out["ponies"] = (crowd.statistics as Dictionary).duplicate()
	return out

func _stats_text(stats: Dictionary, totals: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("%s" % Time.get_datetime_string_from_system(false, true))
	lines.append("FPS %d  (frame %.1f ms, slowest 5%% %.1f ms = %d fps)" % [int(stats.get("fps", 0)), float(stats.get("frame_ms", 0.0)),
		float(stats.get("p95_ms", 0.0)), int(1000.0 / maxf(float(stats.get("p95_ms", 0.0)), 0.001)) if float(stats.get("p95_ms", 0.0)) > 0.0 else 0])
	lines.append("GPU %.1f ms · render CPU %.1f ms · physics step %.1f ms · process %.1f ms" % [float(stats.get("gpu_ms", 0.0)),
		float(stats.get("render_cpu_ms", 0.0)), float(stats.get("physics_ms", 0.0)), float(stats.get("process_ms", 0.0))])
	var shadow: Dictionary = totals.get("shadow", {})
	lines.append("Draws %d (shadow pass %d) · triangles %.2f M (shadow pass %.2f M) · objects %d · VRAM %d MB" % [int(stats.get("draw_calls", 0)),
		int(shadow.get("draw_calls", 0)), float(stats.get("triangles", 0)) / 1e6, float(shadow.get("primitives", 0)) / 1e6,
		int(stats.get("objects", 0)), int(stats.get("vram_mb", 0.0))])
	var ponies: Dictionary = stats.get("ponies", {})
	if not ponies.is_empty():
		lines.append("Ponies: full detail %d (pinned %d) · animated %d · far %d · sitting/lying/asleep on clips %d · hidden in range %d" % [int(ponies.get("hero", 0)),
			int(ponies.get("pinned", 0)), int(ponies.get("near", 0)), int(ponies.get("far", 0)), int(ponies.get("resting", 0)), int(ponies.get("hidden", 0))])
	var at: Array = stats.get("position", [])
	if at.size() == 3: lines.append("Camera at (%.1f, %.1f, %.1f), world hour %.1f" % [at[0], at[1], at[2], float(stats.get("world_hour", 0.0))])
	return "\n".join(lines) + "\n"

var _toast_label: Label
func _toast(text: String) -> void:
	if _toast_label == null:
		_toast_label = Label.new(); _toast_label.position = Vector2(30, 40)
		_toast_label.add_theme_font_size_override("font_size", 22)
		_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_toast_label.add_theme_constant_override("outline_size", 6)
		add_child(_toast_label)
	_toast_label.text = text; _toast_label.visible = true
	get_tree().create_timer(2.5).timeout.connect(func(): if is_instance_valid(_toast_label) and _toast_label.text == text: _toast_label.visible = false)

func open_reports() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	OS.shell_open(ProjectSettings.globalize_path(folder))

func check_capture() -> void:
	if not capture_pending: return
	var path := folder.path_join("status.json")
	if not FileAccess.file_exists(path): return
	var state: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not state is Dictionary or state.get("status", "") == "capturing": return
	capture_pending = false
	message = "Capture " + str(state.get("status")) + ": " + str(state.get("report", state.get("error", "see status.json")))
	print("[render profiler] ", message)
	if panel.visible: summary.text += "\n" + message


# ------------------------------------------------------------------ view cost
var _measuring := false

func _sample(frames := 4) -> Vector3:
	var vp := get_viewport().get_viewport_rid()
	var draws := 0.0; var prims := 0.0; var gpu := 0.0
	for i in 3: await RenderingServer.frame_post_draw   # let visibility settle
	for i in frames:
		await RenderingServer.frame_post_draw
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	return Vector3(draws, prims, gpu) / frames

## Big groups: town parts (houses and foundations pooled), terrain layers, ponies, the rest.
func _groups() -> Array:
	var out := []
	var houses: Array = []; var foundations: Array = []
	for town in get_tree().root.find_children("PonyvilleTown", "", true, false):
		for c in town.get_children():
			if not (c is Node3D): continue
			var n := str(c.name)
			if n.begins_with("plot_"): houses.append(c)
			elif n.begins_with("Foundation_"): foundations.append(c)
			else: out.append([n, [c]])
	if not houses.is_empty(): out.append(["Houses (%d)" % houses.size(), houses])
	if not foundations.is_empty(): out.append(["House foundations", foundations])
	var terrain := get_tree().get_first_node_in_group("world_terrain")
	if terrain != null:
		for c in terrain.get_children():
			if c is Node3D and c != terrain.get("terrain"): out.append([str(c.name), [c]])
		if terrain.get("terrain") is Node3D: out.append(["Terrain3D ground", [terrain.terrain]])
	var ponies := get_tree().get_nodes_in_group("sim_ponies")
	if not ponies.is_empty(): out.append(["Ponies (%d)" % ponies.size(), ponies])
	for name in ["DistantZones", "Weather", "Player", "XRPlayer"]:
		for n in get_tree().root.find_children(name, "", true, false):
			if n is Node3D: out.append([name, [n]])
	return out

func measure_view() -> void:
	if _measuring: return
	_measuring = true
	panel.visible = true
	report.visible = false; listing.visible = true
	summary.text = "Measuring this view: hold still for a few seconds…"
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var base: Vector3 = await _sample(6)
	var rows := []
	for g in _groups():
		var nodes: Array = g[1]
		var was := nodes.map(func(n): return n.visible)
		for n in nodes: n.visible = false
		var without: Vector3 = await _sample()
		for i in nodes.size(): if is_instance_valid(nodes[i]): nodes[i].visible = was[i]
		rows.append({"group": g[0], "draws": base.x - without.x, "triangles": base.y - without.y, "gpu_ms": base.z - without.z})
	var sky := get_tree().get_first_node_in_group("sky_controller")
	var sky_mat: ShaderMaterial = sky.get("_sky_material") if sky != null else null
	if sky_mat != null and sky_mat.get_shader_parameter("volume_clouds") == true:
		sky_mat.set_shader_parameter("volume_clouds", false)
		var clear: Vector3 = await _sample()
		sky_mat.set_shader_parameter("volume_clouds", true)
		rows.append({"group": "Volumetric clouds (sky)", "draws": base.x - clear.x, "triangles": base.y - clear.y, "gpu_ms": base.z - clear.z})
	rows.sort_custom(func(a, b): return a.gpu_ms > b.gpu_ms if absf(a.gpu_ms - b.gpu_ms) > 0.05 else a.draws > b.draws)
	listing.clear(); var root_item := listing.create_item()
	for i in 4: listing.set_column_title(i, ["Group (hidden in turn)", "Draws", "Triangles", "GPU ms"][i])
	for r in rows:
		var item := listing.create_item(root_item)
		item.set_text(0, r.group); item.set_text(1, "%d" % r.draws); item.set_text(2, "%.0f k" % (r.triangles / 1000.0)); item.set_text(3, "%.2f" % r.gpu_ms)
	var cam := get_viewport().get_camera_3d()
	summary.text = "THIS VIEW: %d draws · %.2f M triangles · GPU %.2f ms (%.0f fps GPU-bound)\nEach row = what disappears when that group is hidden (Shift+F11 again to re-measure). Saved view-*.json." % [base.x, base.y / 1e6, base.z, 1000.0 / maxf(base.z, 0.01)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var f := FileAccess.open(folder.path_join("view-%d.json" % Time.get_unix_time_from_system()), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"camera": [cam.global_position.x, cam.global_position.y, cam.global_position.z] if cam else [], "facing": [-cam.global_basis.z.x, -cam.global_basis.z.y, -cam.global_basis.z.z] if cam else [],
			"total": {"draws": base.x, "triangles": base.y, "gpu_ms": base.z}, "groups": rows}, "\t"))
	print("[render profiler] view: ", summary.text.get_slice("\n", 0))
	for r in rows.slice(0, 12): print("   %-32s draws %6d  tris %8.0f  gpu %.2f ms" % [r.group, r.draws, r.triangles, r.gpu_ms])
	_measuring = false
