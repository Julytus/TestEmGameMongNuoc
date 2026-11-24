extends PlayerState


func enter(_msg: Dictionary) -> void:
	player.play_animation(&"walk")


func handle_input(event: InputEvent) -> void:
	try_combat_actions(event)


func physics_update(delta: float) -> void:
	var direction := player.get_move_direction()
	if direction == Vector3.ZERO:
		state_machine.transition_to(&"Idle")
		return
	player.set_facing(direction)
	player.move_toward_velocity(direction * player.move_speed, player.acceleration, delta)
