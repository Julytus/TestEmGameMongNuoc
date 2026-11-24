class_name PlayerState
extends State
## Lớp cơ sở cho các state của Player.

@onready var player: Player = owner as Player


## Xử lý các hành động chung khi đang đứng/đi. Trả về true nếu đã chuyển state.
func try_combat_actions(event: InputEvent) -> bool:
	if event.is_action_pressed(&"attack"):
		state_machine.transition_to(&"Attack")
		return true
	if event.is_action_pressed(&"dodge") and player.can_dodge():
		state_machine.transition_to(&"Dodge")
		return true
	return false
