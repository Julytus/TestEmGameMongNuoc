class_name HealthComponent
extends Node
## Máu + bất tử tạm thời (i-frames). Gắn vào bất kỳ thực thể nào có thể nhận sát thương.

signal health_changed(current: int, max_health: int)
signal damaged(amount: int)
signal healed(amount: int)
signal died

@export var max_health: int = 3
## Thời gian bất tử sau khi trúng đòn (giây).
@export var invulnerability_time: float = 0.0

var current_health: int = 0
## Bất tử cưỡng bức từ bên ngoài (đang né, cutscene...). Không gây nhấp nháy.
var invulnerable: bool = false

var _iframes_left: float = 0.0


func _ready() -> void:
	current_health = max_health


func _physics_process(delta: float) -> void:
	if _iframes_left > 0.0:
		_iframes_left -= delta


func is_dead() -> bool:
	return current_health <= 0


func is_in_iframes() -> bool:
	return _iframes_left > 0.0


func can_take_damage() -> bool:
	return not is_dead() and not invulnerable and _iframes_left <= 0.0


## Trả về true nếu thực sự nhận sát thương.
func take_damage(amount: int) -> bool:
	if amount <= 0 or not can_take_damage():
		return false
	current_health = maxi(current_health - amount, 0)
	_iframes_left = invulnerability_time
	damaged.emit(amount)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		died.emit()
	return true


func heal(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	var before := current_health
	current_health = mini(current_health + amount, max_health)
	if current_health != before:
		healed.emit(current_health - before)
		health_changed.emit(current_health, max_health)


func reset() -> void:
	current_health = max_health
	_iframes_left = 0.0
	health_changed.emit(current_health, max_health)
