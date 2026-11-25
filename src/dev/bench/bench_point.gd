class_name BenchPoint
extends Marker3D
## Điểm đo cố định của chế độ bench (`-- --bench=N`): BenchRunner dời người chơi tới đây, đứng yên, đo N giây.
## Thứ tự đo = thứ tự trong cây. Đặt y = 0,1 như SpawnPoint. `id` phải duy nhất trong level.

@export var id: StringName = &""


func _enter_tree() -> void:
	add_to_group(&"bench_points")
