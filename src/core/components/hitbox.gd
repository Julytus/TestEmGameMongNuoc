class_name Hitbox
extends Area3D
## Vùng GÂY sát thương (đòn chém, thân quái chạm vào...).
## Phe được quyết định bằng collision layer: player_hitbox (4) hoặc enemy_hitbox (5).

@export var damage: int = 1
@export var knockback: float = 6.0
@export var active: bool = true:
	set = set_active


func _ready() -> void:
	monitoring = false
	monitorable = active


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if is_inside_tree():
		set_deferred(&"monitorable", value)
