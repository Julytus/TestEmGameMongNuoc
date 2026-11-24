extends PlayerState
## Chém thường. Hitbox chỉ bật trong attack_active_window để timing rõ ràng.
## Mở rộng combo: thêm state Attack2/Attack3 và cho phép buffer input trong cửa sổ cuối đòn.

var _elapsed: float = 0.0


func enter(_msg: Dictionary) -> void:
	_elapsed = 0.0
	var direction := player.get_move_direction()
	if direction != Vector3.ZERO:
		player.set_facing(direction)
	player.play_animation(&"attack")


func exit() -> void:
	player.attack_hitbox.active = false


func physics_update(delta: float) -> void:
	_elapsed += delta
	var window := player.attack_active_window
	player.attack_hitbox.active = _elapsed >= window.x and _elapsed <= window.y
	player.move_toward_velocity(Vector3.ZERO, player.friction, delta)
	if _elapsed >= player.attack_duration:
		state_machine.transition_to(&"Idle")
