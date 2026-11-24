@tool
class_name TerrainWater
extends MeshInstance3D
## Mặt nước cho các ô nước (kênh B) của TerrainLayout. Tạo một PlaneMesh vừa khít vùng nước,
## đặt thấp hơn mặt đất một chút; water.gdshader tự cắt đúng hình hồ theo layout.
## Tính sẵn bản đồ khoảng cách tới bờ (shore_sdf) cho độ sâu mượt và sóng chạy vào bờ.

## Độ phân giải bản đồ khoảng cách tới bờ (pixel / m).
const SDF_RESOLUTION := 8

@export var layout: TerrainLayout:
	set(value):
		if layout and layout.changed.is_connected(_rebuild):
			layout.changed.disconnect(_rebuild)
		layout = value
		if layout:
			layout.changed.connect(_rebuild)
		_rebuild()
## Độ cao mặt nước so với mặt đất (âm = thấp hơn).
@export var water_level: float = -0.06:
	set(value):
		water_level = value
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_node_ready() or layout == null:
		return
	var img := layout.get_image()
	if img == null:
		return
	var bounds := Rect2i()
	var found := false
	for y in img.get_height():
		for x in img.get_width():
			if TerrainLayout.matches_mask(img.get_pixel(x, y), TerrainLayout.FLAG_WATER):
				var cell := Rect2i(x, y, 1, 1)
				bounds = cell if not found else bounds.merge(cell)
				found = true
	visible = found
	if not found:
		return
	bounds = bounds.grow(1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(bounds.size) * layout.cell_size
	mesh = plane
	var center := layout.cell_to_world(bounds.position) + (Vector2(bounds.size) - Vector2.ONE) * 0.5 * layout.cell_size
	position = Vector3(center.x, water_level, center.y)
	var mat := material_override as ShaderMaterial
	layout.apply_to_material(mat)
	if mat:
		var origin := center - plane.size * 0.5
		mat.set_shader_parameter(&"shore_sdf", _build_sdf(origin, plane.size))
		mat.set_shader_parameter(&"shore_sdf_rect", Vector4(origin.x, origin.y, plane.size.x, plane.size.y))


## Khoảng cách (m) từ mỗi điểm nước tới bờ gần nhất – biến đổi khoảng cách chamfer 2 lượt.
func _build_sdf(origin: Vector2, size: Vector2) -> ImageTexture:
	var w := int(size.x * SDF_RESOLUTION)
	var h := int(size.y * SDF_RESOLUTION)
	const BIG := 1e6
	const D := 1.0
	const DD := 1.41421
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	for y in h:
		for x in w:
			var world := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) / SDF_RESOLUTION
			dist[y * w + x] = BIG if layout.sample(world).b > 0.5 else 0.0
	for y in h:
		for x in w:
			var i := y * w + x
			var d := dist[i]
			if x > 0:
				d = minf(d, dist[i - 1] + D)
			if y > 0:
				d = minf(d, dist[i - w] + D)
				if x > 0:
					d = minf(d, dist[i - w - 1] + DD)
				if x < w - 1:
					d = minf(d, dist[i - w + 1] + DD)
			dist[i] = d
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			var d := dist[i]
			if x < w - 1:
				d = minf(d, dist[i + 1] + D)
			if y < h - 1:
				d = minf(d, dist[i + w] + D)
				if x < w - 1:
					d = minf(d, dist[i + w + 1] + DD)
				if x > 0:
					d = minf(d, dist[i + w - 1] + DD)
			dist[i] = d
	var img := Image.create(w, h, false, Image.FORMAT_RF)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(dist[y * w + x] / SDF_RESOLUTION, 0.0, 0.0))
	return ImageTexture.create_from_image(img)
