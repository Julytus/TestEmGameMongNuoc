extends PlayerState
## Bị đẩy lùi ngắn sau khi trúng đòn; không điều khiển được trong lúc này.

const DURATION := 0.22

var _time_left: float = 0.0


func enter(msg: Dictionary) -> void:
	var knockback: Vector3 = msg.get("knockback", Vector3.ZERO)
	player.velocity.x = knockback.x
	player.velocity.z = knockback.z
	_time_left = DURATION
	player.play_animation(&"hurt")


func physics_update(delta: float) -> void:
	_time_left -= delta
	player.move_toward_velocity(Vector3.ZERO, player.friction * 0.5, delta)
	if _time_left <= 0.0:
		state_machine.transition_to(&"Idle")
