extends PlayerState


func enter(_msg: Dictionary) -> void:
	player.play_animation(&"idle")


func handle_input(event: InputEvent) -> void:
	if not try_jump(event):
		try_combat_actions(event)


func physics_update(delta: float) -> void:
	player.move_toward_velocity(Vector3.ZERO, player.friction, delta)
	if try_fall():
		return
	if player.input_vector != Vector2.ZERO:
		state_machine.transition_to(&"Move")
