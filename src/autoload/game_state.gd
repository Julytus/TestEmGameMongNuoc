extends Node
## Trạng thái thế giới & cốt truyện trong lúc chạy. SaveManager tuần tự hóa toàn bộ dữ liệu ở đây.
##
## Quy ước:
##  - Chỉ chứa dữ liệu thuần (bool/int/float/String/Array/Dictionary) để JSON hóa an toàn.
##  - Mọi tiến trình cốt truyện (đã nói chuyện NPC, đã mở rương, đã hạ boss...) lưu dưới dạng FLAG.
##    Đặt tên flag dạng snake_case có tiền tố: "quest_", "npc_", "chest_", "boss_defeated_"...

signal flag_changed(flag: StringName, value: Variant)

const DEFAULT_PLAYER_MAX_HEALTH := 6 # 2 máu = 1 trái tim

var flags: Dictionary = {}
var current_level: String = ""
var spawn_id: StringName = &"default"
var player_max_health: int = DEFAULT_PLAYER_MAX_HEALTH
var player_health: int = DEFAULT_PLAYER_MAX_HEALTH
var play_time: float = 0.0


func _process(delta: float) -> void:
	play_time += delta


func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[String(flag)] = value
	flag_changed.emit(flag, value)


func get_flag(flag: StringName, default: Variant = null) -> Variant:
	return flags.get(String(flag), default)


func has_flag(flag: StringName) -> bool:
	return flags.has(String(flag))


func clear_flag(flag: StringName) -> void:
	if flags.erase(String(flag)):
		flag_changed.emit(flag, null)


func reset() -> void:
	flags.clear()
	current_level = ""
	spawn_id = &"default"
	player_max_health = DEFAULT_PLAYER_MAX_HEALTH
	player_health = DEFAULT_PLAYER_MAX_HEALTH
	play_time = 0.0


func to_dict() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"current_level": current_level,
		"spawn_id": String(spawn_id),
		"player_max_health": player_max_health,
		"player_health": player_health,
		"play_time": play_time,
	}


func from_dict(data: Dictionary) -> void:
	reset()
	var loaded_flags: Variant = data.get("flags", {})
	if loaded_flags is Dictionary:
		flags = loaded_flags
	current_level = str(data.get("current_level", ""))
	spawn_id = StringName(str(data.get("spawn_id", "default")))
	# JSON lưu số dưới dạng float → ép kiểu lại
	player_max_health = int(data.get("player_max_health", DEFAULT_PLAYER_MAX_HEALTH))
	player_health = clampi(int(data.get("player_health", player_max_health)), 1, player_max_health)
	play_time = float(data.get("play_time", 0.0))
