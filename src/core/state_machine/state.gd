class_name State
extends Node
## Lớp cơ sở cho một trạng thái. Ghi đè các hàm cần dùng.

var state_machine: StateMachine


## msg: dữ liệu tùy chọn từ state trước (vd: {"knockback": Vector3}).
func enter(_msg: Dictionary) -> void:
	pass


func exit() -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass
