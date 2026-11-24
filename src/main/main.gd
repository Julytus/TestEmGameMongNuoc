extends Node
## Điểm vào của game. Giữ World (chứa level hiện tại) + UI tồn tại xuyên suốt.
##
## Tham số dòng lệnh cho dev/CI (đặt sau "--"):
##   --level=res://...tscn        vào thẳng một level
##   --screenshot=C:/path.png     chụp màn hình sau vài giây rồi thoát
##   --pos=x,z                    đặt người chơi tại tọa độ world (Level đọc)

@export_file("*.tscn") var start_level: String = "res://src/world/levels/meadow_road/meadow_road.tscn"
@export var start_spawn: StringName = &"default"
@export var quick_save_slot: int = 0

@onready var world: Node3D = $World


func _ready() -> void:
	SceneManager.register_world_root(world)
	EventBus.player_died.connect(_on_player_died)
	var args := _parse_user_args()
	SceneManager.change_level(args.get("level", start_level), start_spawn)
	if args.has("screenshot"):
		_take_screenshot_and_quit(args["screenshot"], float(args.get("delay", "2.5")))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_tree().paused = not get_tree().paused
	elif event.is_action_pressed(&"quick_save") and not get_tree().paused:
		SaveManager.save_game(quick_save_slot)
	elif event.is_action_pressed(&"quick_load") and SaveManager.has_save(quick_save_slot):
		get_tree().paused = false
		SaveManager.load_game(quick_save_slot)


func _on_player_died() -> void:
	await get_tree().create_timer(1.5).timeout
	GameState.player_health = GameState.player_max_health
	SceneManager.change_level(GameState.current_level, GameState.spawn_id)


func _parse_user_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var parts := arg.trim_prefix("--").split("=", true, 1)
			result[parts[0]] = parts[1]
	return result


func _take_screenshot_and_quit(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("[Main] Screenshot → %s (%s)" % [path, error_string(err)])
	# Deferred: để coroutine này kết thúc hẳn trước khi thoát (tránh leak lúc exit)
	get_tree().quit.call_deferred()
