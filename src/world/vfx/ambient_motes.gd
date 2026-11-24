class_name AmbientMotes
extends GPUParticles3D
## Hạt bụi phấn (ban ngày) / đom đóm (ban đêm) lơ lửng, phát sáng để ăn bloom.
## LightingDirector gọi set_intensity() theo preset.

@export var base_color: Color = Color(1.0, 0.85, 0.45)

var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"ambient_motes")
	if draw_pass_1 and draw_pass_1.surface_get_material(0):
		# Nhân bản material để mỗi instance chỉnh độ sáng riêng
		_material = draw_pass_1.surface_get_material(0).duplicate() as StandardMaterial3D
		draw_pass_1 = draw_pass_1.duplicate()
		draw_pass_1.surface_set_material(0, _material)


func set_intensity(value: float) -> void:
	if _material:
		_material.albedo_color = Color(base_color.r * value, base_color.g * value, base_color.b * value, 1.0)
	visible = value > 0.01
