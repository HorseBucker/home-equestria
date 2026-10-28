extends RefCounted
## A scene inventory, not a reconstruction of renderer culling or GPU draws.
static func digest(bytes: PackedByteArray) -> String:
	if bytes.is_empty(): return ""
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	return hash.finish().hex_encode()

static func triangles(primitive: int, count: int) -> int:
	match primitive:
		Mesh.PRIMITIVE_TRIANGLES: return count / 3
		Mesh.PRIMITIVE_TRIANGLE_STRIP: return maxi(0, count - 2)
	return 0

static func material_info(material: Material) -> Dictionary:
	if material == null: return {}
	var passes: Array = []
	var seen := {}
	while material != null and not seen.has(material.get_instance_id()):
		seen[material.get_instance_id()] = true
		passes.append({"path":material.resource_path, "name":material.resource_name, "class":material.get_class(), "shader":material.shader.resource_path if material is ShaderMaterial and material.shader != null else ""})
		material = material.next_pass
	return {"passes":passes}

static func snapshot(top: Node, camera: Camera3D, fingerprints := false) -> Dictionary:
	var rows: Array = []
	var unknown: Array = []
	var meshes := {}
	var pending: Array[Node] = [top]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children(true))
		var mesh: Mesh
		var instances := 1
		if node is MeshInstance3D: mesh = node.mesh
		elif node is MultiMeshInstance3D and node.multimesh != null:
			mesh = node.multimesh.mesh
			instances = node.multimesh.instance_count if node.multimesh.visible_instance_count < 0 else mini(node.multimesh.instance_count, node.multimesh.visible_instance_count)
		elif node is VisualInstance3D or node.get_class() == "Terrain3D":
			unknown.append({"node":str(node.get_path()), "class":node.get_class(), "note":"GPU capture required; geometry is not exposed as a scene Mesh"})
		if mesh == null: continue
		var key := str(mesh.get_rid().get_id())
		if not meshes.has(key):
			var surfaces: Array = []
			for index in mesh.get_surface_count():
				var surface := RenderingServer.mesh_get_surface(mesh.get_rid(), index)
				# Non-indexed surfaces (and some procedural meshes) omit the index keys entirely.
				var indices := int(surface.get("index_count", 0)); var vertices := int(surface.get("vertex_count", 0))
				var primitive := int(surface.get("primitive", Mesh.PRIMITIVE_TRIANGLES))
				var elements := indices if indices > 0 else vertices
				var item := {"surface":index,"triangles":triangles(primitive, elements),"vertices":vertices,"indices":indices,"primitive":primitive}
				if fingerprints:
					var vertex_data: PackedByteArray = surface.get("vertex_data", PackedByteArray())
					var index_data: PackedByteArray = surface.get("index_data", PackedByteArray())
					item["vertex_sha256"] = digest(vertex_data)
					item["vertex_bytes"] = vertex_data.size()
					item["index_sha256"] = digest(index_data)
					item["index_bytes"] = index_data.size()
				surfaces.append(item)
			meshes[key] = {"resource":mesh.resource_path,"name":mesh.resource_name,"surfaces":surfaces}
		var source: Node = node
		while source != null and source.scene_file_path.is_empty(): source = source.get_parent()
		var visible: bool = node.is_visible_in_tree()
		var distance := camera.global_position.distance_to(node.global_position) if camera != null else -1.0
		for surface: Dictionary in meshes[key].surfaces:
			var mat: Material = node.get_active_material(surface.surface) if node is MeshInstance3D else (node.material_override if node.material_override != null else mesh.surface_get_material(surface.surface))
			rows.append({"node":str(node.get_path()),"scene":source.scene_file_path if source != null else "", "class":node.get_class(),"mesh_key":key,"surface":surface.surface,"base_triangles":surface.triangles,"instances":instances,"instanced_base_triangles":int(surface.triangles)*instances,"visible_in_tree":visible,"distance_m":distance,"layers":node.layers,"camera_layer_match":camera == null or (node.layers & camera.cull_mask)!=0,"visibility_begin":node.visibility_range_begin,"visibility_end":node.visibility_range_end,"shadow_mode":node.cast_shadow,"material":material_info(mat),"overlay":material_info(node.material_overlay)})
	rows.sort_custom(func(a: Dictionary,b: Dictionary):return a.instanced_base_triangles>b.instanced_base_triangles)
	var vp: Viewport = top.get_viewport()
	var totals := {}
	for pair in [["visible",Viewport.RENDER_INFO_TYPE_VISIBLE],["shadow",Viewport.RENDER_INFO_TYPE_SHADOW]]:
		totals[pair[0]] = {"draw_calls":vp.get_render_info(pair[1],Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives":vp.get_render_info(pair[1],Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"objects":vp.get_render_info(pair[1],Viewport.RENDER_INFO_OBJECTS_IN_FRAME)}
	return {"version":1,"captured_at":Time.get_datetime_string_from_system(true),"pid":OS.get_process_id(),"scene_frame":Engine.get_process_frames(),"engine_totals":totals,"rows":rows,"meshes":meshes,"unexposed_geometry":unknown,"scope":"Scene counts are base mesh topology times active instance count, not submitted GPU triangles. Visibility, LOD, occlusion, batching, shadows, particles, terrain, UI and multiview require the GPU capture. Inventory precedes that capture and can differ for animated/streaming content."}
