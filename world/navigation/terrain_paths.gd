extends RefCounted
## Read the same Terrain3D controls that draw the road. Called only while deriving
## navigation columns, inside the service's existing time budget; no renderer readback.
var data: Object
var trail_ids := {}

func bind(source: Object, texture_rows: Array) -> void:
	data = source
	for row: Dictionary in texture_rows:
		if row.get("navigation_trail", false): trail_ids[int(row.id)] = true

func control_weight(control: int) -> float:
	var base := (control >> 27) & 31
	var overlay := (control >> 22) & 31
	var blend := float((control >> 14) & 255) / 255.0
	return lerpf(1.0 if trail_ids.has(base) else 0.0, 1.0 if trail_ids.has(overlay) else 0.0, blend)

const CORNERS := [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]
## Reused per call (main thread only); float32 storage keeps the old rounding.
var _weights := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

func weight_at(point: Vector3) -> float:
	if not is_instance_valid(data): return 0.0
	var corner := Vector2(point.x, point.z).floor()
	var f := Vector2(point.x, point.z) - corner
	for i in 4:
		var p: Vector2 = corner + CORNERS[i]
		_weights[i] = control_weight(int(data.get_control(Vector3(p.x, point.y, p.y))))
	return lerpf(lerpf(_weights[0], _weights[1], f.x), lerpf(_weights[2], _weights[3], f.x), f.y)
