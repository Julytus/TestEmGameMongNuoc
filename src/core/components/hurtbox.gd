class_name Hurtbox
extends Area3D
## Vùng NHẬN sát thương. Mask = layer hitbox của phe đối địch.
## Kiểm tra chồng lấn mỗi physics frame → đứng lì trong hitbox vẫn bị trúng lại sau khi hết i-frames.

signal hit(hitbox: Hitbox)

@export var health: HealthComponent


func _ready() -> void:
	monitorable = false
	monitoring = true


func _physics_process(_delta: float) -> void:
	if health == null or not health.can_take_damage():
		return
	for area in get_overlapping_areas():
		var hitbox := area as Hitbox
		if hitbox == null or not hitbox.active or hitbox.owner == owner:
			continue
		if health.take_damage(hitbox.damage):
			hit.emit(hitbox)
		return
