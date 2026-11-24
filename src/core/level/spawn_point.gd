class_name SpawnPoint
extends Marker3D
## Điểm xuất hiện của người chơi trong level. Cửa/lối đi giữa các map trỏ tới id này.

@export var id: StringName = &"default"


func _enter_tree() -> void:
	add_to_group(&"spawn_points")
