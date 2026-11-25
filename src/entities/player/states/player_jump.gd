extends PlayerState
## Trên không: bật lên (hoặc rơi khỏi mép khi msg.fall), điều khiển hướng bằng air_acceleration.
## Trọng lực do Player._physics_process cộng. Chạm sàn → Idle/Move. Chưa có attack/dodge trên không.

## Khung trong anim jump_<dir>: 0 = đang lên, 1 = đang rơi.
const FRAME_RISE := 0
const FRAME_FALL := 1


func enter(msg: Dictionary) -> void:
	if not msg.get("fall", false):
		player.emit_footstep(0.8)
		player.velocity.y = player.jump_velocity
	player.play_animation(&"jump")
	player.sprite.pause()
	_update_frame()


func physics_update(delta: float) -> void:
	var direction := player.get_move_direction()
	if direction != Vector3.ZERO:
		player.set_facing(direction)
	player.move_toward_velocity(direction * player.move_speed, player.air_acceleration, delta)
	_update_frame()
	if player.is_on_floor():
		player.emit_footstep(1.6)
		state_machine.transition_to(&"Move" if player.input_vector != Vector2.ZERO else &"Idle")


func _update_frame() -> void:
	# set_facing có thể đổi hướng sprite (play lại anim) → luôn pause + đặt khung theo vận tốc
	player.sprite.pause()
	player.sprite.frame = FRAME_RISE if player.velocity.y > 0.0 else FRAME_FALL
