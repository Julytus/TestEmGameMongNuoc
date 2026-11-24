class_name TerrainCollision
extends StaticBody3D
## Sinh tường va chạm cho các ô chặn đường của TerrainLayout (mặc định: nước + rừng).
## Các ô liền nhau trên cùng một hàng được gộp thành một BoxShape3D để giảm số shape.

@export var layout: TerrainLayout
@export_flags("Dirt", "Tall grass", "Water", "Forest") var blocking_mask: int = \
		TerrainLayout.FLAG_WATER | TerrainLayout.FLAG_FOREST
@export var wall_height: float = 2.0


func _ready() -> void:
	build()


func build() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			child.queue_free()
	var img := layout.get_image() if layout else null
	if img == null:
		return
	var cs := layout.cell_size
	for y in img.get_height():
		var run_start := -1
		for x in img.get_width() + 1:
			var blocked := x < img.get_width() \
					and TerrainLayout.matches_mask(img.get_pixel(x, y), blocking_mask)
			if blocked and run_start < 0:
				run_start = x
			elif not blocked and run_start >= 0:
				_add_box(run_start, x - run_start, y, cs)
				run_start = -1


func _add_box(x: int, length: int, y: int, cs: float) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(length * cs, wall_height, cs)
	var shape := CollisionShape3D.new()
	shape.shape = box
	var start := layout.cell_to_world(Vector2i(x, y))
	shape.position = Vector3(start.x + (length - 1) * cs * 0.5, wall_height * 0.5, start.y)
	add_child(shape)
