extends PlayerState
## Chết: dừng mọi điều khiển, mờ dần. Main sẽ hồi sinh tại spawn point.


func enter(_msg: Dictionary) -> void:
	player.attack_hitbox.active = false
	player.play_animation(&"hurt")
	var tween := player.create_tween()
	tween.tween_property(player.sprite, "modulate:a", 0.0, 0.8)


func physics_update(delta: float) -> void:
	player.move_toward_velocity(Vector3.ZERO, player.friction, delta)
