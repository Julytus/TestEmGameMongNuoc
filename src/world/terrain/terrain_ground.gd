@tool
class_name TerrainGround
extends MeshInstance3D
## Mặt đất phẳng phủ texture pixel art theo TerrainLayout: cỏ / đường đất / bờ nước / nền rừng.
## Tự tạo PlaneMesh bằng kích thước layout + padding (phần ngoài layout lặp lại mép → rừng kéo dài
## ra ngoài tầm camera) và đẩy layout vào terrain_ground.gdshader.

@export var layout: TerrainLayout:
	set(value):
		if layout and layout.changed.is_connected(_rebuild):
			layout.changed.disconnect(_rebuild)
		layout = value
		if layout:
			layout.changed.connect(_rebuild)
		_rebuild()
## Phần mặt đất kéo dài thêm ra ngoài layout mỗi phía (m).
@export var padding: float = 16.0:
	set(value):
		padding = value
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_node_ready() or layout == null or layout.texture == null:
		return
	var plane := PlaneMesh.new()
	plane.size = layout.get_world_size() + Vector2.ONE * padding * 2.0
	mesh = plane
	layout.apply_to_material(material_override as ShaderMaterial)
