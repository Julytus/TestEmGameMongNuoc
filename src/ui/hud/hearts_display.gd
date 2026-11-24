class_name HeartsDisplay
extends Control
## Vẽ thanh trái tim từ spritesheet 3 ô: [đầy | nửa | rỗng]. 1 trái tim = 2 máu.

const HEART_SIZE := Vector2i(11, 10)

@export var texture: Texture2D
@export_range(1, 8) var pixel_scale: int = 4
@export var spacing: int = 1

var _current: int = 6
var _max: int = 6


func set_health(current: int, max_health: int) -> void:
	_current = current
	_max = max_health
	var hearts := ceili(_max / 2.0)
	custom_minimum_size = Vector2(hearts * (HEART_SIZE.x + spacing), HEART_SIZE.y) * pixel_scale
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	var hearts := ceili(_max / 2.0)
	for i in hearts:
		var hp_in_heart := clampi(_current - i * 2, 0, 2)
		var frame := 0 if hp_in_heart == 2 else (1 if hp_in_heart == 1 else 2)
		var src := Rect2(frame * HEART_SIZE.x, 0, HEART_SIZE.x, HEART_SIZE.y)
		var dst := Rect2(
			Vector2(i * (HEART_SIZE.x + spacing), 0) * pixel_scale,
			Vector2(HEART_SIZE) * pixel_scale
		)
		draw_texture_rect_region(texture, dst, src)
