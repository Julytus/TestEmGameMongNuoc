extends Node
## Điểm vào của game. Giữ World (chứa level hiện tại) + UI tồn tại xuyên suốt.
##
## Tham số dòng lệnh cho dev/CI (đặt sau "--"):
##   --level=res://...tscn        vào thẳng một level
##   --screenshot=C:/path.png     chụp màn hình sau vài giây rồi thoát
##   --pos=x,z                    đặt người chơi tại tọa độ world (Level đọc; bị bỏ qua khi bench)
##   --bench=N                    chế độ bench (BenchRunner): exclusive fullscreen, đo N giây MỖI BenchPoint
##                                (sau khởi động), ghi JSON rồi thoát; --screenshot bị bỏ qua
##   --bench-out=C:/path.json     nơi ghi JSON bench (mặc định user://bench/bench-<thời gian>.json)
##   --debug-draw=overdraw|wireframe|unshaded   chế độ debug draw của viewport (soi overdraw cỏ/lá/nước)

@export_file("*.tscn") var start_level: String = "res://src/world/levels/meadow_road/meadow_road.tscn"
@export var start_spawn: StringName = &"default"
@export var quick_save_slot: int = 0

const DEBUG_DRAW_MODES: Dictionary[String, Viewport.DebugDraw] = {
	"overdraw": Viewport.DEBUG_DRAW_OVERDRAW,
	"wireframe": Viewport.DEBUG_DRAW_WIREFRAME,
	"unshaded": Viewport.DEBUG_DRAW_UNSHADED,
}

@onready var world: Node3D = $World


func _ready() -> void:
	SceneManager.register_world_root(world)
	EventBus.player_died.connect(_on_player_died)
	var args := _parse_user_args()
	if args.has("debug-draw"):
		_set_debug_draw(args["debug-draw"])
	if args.has("bench"):
		_start_bench(args)
		return
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


func _start_bench(args: Dictionary) -> void:
	var seconds := float(args["bench"])
	if seconds <= 0.0:
		push_error("[Bench] --bench=N cần N > 0 (nhận '%s')" % args["bench"])
		get_tree().quit(2)
		return
	var runner := BenchRunner.new()
	runner.name = "BenchRunner"
	runner.seconds_per_point = seconds
	runner.out_path = args.get("bench-out", "")
	runner.level_path = args.get("level", start_level)
	runner.spawn_id = start_spawn
	add_child(runner)


func _on_player_died() -> void:
	await get_tree().create_timer(1.5).timeout
	GameState.player_health = GameState.player_max_health
	SceneManager.change_level(GameState.current_level, GameState.spawn_id)


func _set_debug_draw(mode: String) -> void:
	if not DEBUG_DRAW_MODES.has(mode):
		push_warning("[Main] --debug-draw cần %s: %s" % ["|".join(DEBUG_DRAW_MODES.keys()), mode])
		return
	if mode == "wireframe":
		RenderingServer.set_debug_generate_wireframes(true)
	get_viewport().debug_draw = DEBUG_DRAW_MODES[mode]


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
