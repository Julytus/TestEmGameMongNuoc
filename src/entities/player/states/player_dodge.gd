extends PlayerState
## Lướt né: tốc độ cao, bất tử trong suốt thời gian lướt.

var _time_left: float = 0.0
var _direction: Vector3 = Vector3.ZERO


func enter(_msg: Dictionary) -> void:
	var input_direction := player.get_move_direction()
	_direction = input_direction.normalized() if input_direction != Vector3.ZERO else player.facing
	player.set_facing(_direction)
	_time_left = player.dodge_duration
	player.health.invulnerable = true
	player.play_animation(&"dodge")


func exit() -> void:
	player.health.invulnerable = false
	player.dodge_cooldown_left = player.dodge_cooldown


func physics_update(delta: float) -> void:
	_time_left -= delta
	player.velocity.x = _direction.x * player.dodge_speed
	player.velocity.z = _direction.z * player.dodge_speed
	player.move_and_slide()
	if _time_left <= 0.0:
		state_machine.transition_to(&"Move" if player.input_vector != Vector2.ZERO else &"Idle")
