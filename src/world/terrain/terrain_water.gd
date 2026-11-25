@tool
class_name TerrainWater
extends MeshInstance3D
## Mặt nước cho các ô nước (kênh B) của TerrainLayout. Tạo một PlaneMesh phủ đúng vùng water field
## (WaterField do TerrainLayout dựng + cache), đặt thấp hơn mặt đất một chút; water.gdshader cắt đúng hình hồ
## theo field – cùng texture mà terrain_ground.gdshader dùng để khoét lỗ → mép khớp tuyệt đối.

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
	var field := layout.get_water_field()
	visible = field.has_water()
	if not field.has_water():
		return
	var plane := PlaneMesh.new()
	plane.size = field.rect.size
	mesh = plane
	var center := field.rect.get_center()
	position = Vector3(center.x, water_level, center.y)
	var mat := material_override as ShaderMaterial
	layout.apply_to_material(mat)
	if mat:
		# Nước đọc field tại giao điểm tia nhìn với mặt đất (cao hơn mặt nước -water_level) → không hở viền.
		mat.set_shader_parameter(&"ground_offset", -water_level)
