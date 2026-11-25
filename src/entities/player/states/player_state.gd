class_name PlayerState
extends State
## Lớp cơ sở cho các state của Player.

@onready var player: Player = owner as Player


## Bấm nhảy khi đang đứng trên sàn → state Jump. Trả về true nếu đã chuyển state.
func try_jump(event: InputEvent) -> bool:
	if event.is_action_pressed(&"jump") and player.is_on_floor():
		state_machine.transition_to(&"Jump")
		return true
	return false


## Không còn chạm sàn (rơi khỏi mép) → state Jump ở pha rơi. Trả về true nếu đã chuyển state.
func try_fall() -> bool:
	if not player.is_on_floor() and player.velocity.y < -player.fall_speed_threshold:
		state_machine.transition_to(&"Jump", {"fall": true})
		return true
	return false


## Xử lý các hành động chung khi đang đứng/đi. Trả về true nếu đã chuyển state.
func try_combat_actions(event: InputEvent) -> bool:
	if event.is_action_pressed(&"attack"):
		state_machine.transition_to(&"Attack")
		return true
	if event.is_action_pressed(&"dodge") and player.can_dodge():
		state_machine.transition_to(&"Dodge")
		return true
	return false
