extends Node
## Chuyển level có fade + load bất đồng bộ (không đứng hình khi map lớn).
##
## Kiến trúc: Main giữ một node "World" cố định; level được thay bên trong World,
## còn HUD/menu nằm ngoài nên tồn tại xuyên suốt game.
## Nếu chạy thẳng một level (F6 trong editor) thì World chưa đăng ký → fallback đổi cả scene.

signal level_changed(level: Node)

const FADE_TIME := 0.35

## Né lỗi engine godotengine/godot#120661 (OPEN; PR #121025 chưa merge; regression 4.7 từ #118824):
## resource bị nạp LỒNG trong lúc load_threaded_request (đích preload của script, file #include của shader)
## rò ObjectDB lúc thoát. Nạp sẵn ("warm") chúng bằng chính load_threaded_request trước lần nạp level đầu
## và GIỮ tham chiếu suốt phiên trong _warm_pins — cache của ResourceLoader là weak, bỏ tham chiếu là rò lại.
## Quy tắc: thêm preload("res://…") vào src/**/*.gd hoặc #include "res://…" vào shader → thêm path vào đây;
## bước `warm manifest` của tools/dev/check.py kiểm (thiếu/thừa → FAIL).
## Giới hạn của lint: preload lồng bên trong một preload target, `static var … = load()` không bị quét
## (bước `run` của check.py vẫn bắt nếu level meadow dùng tới).
## Giới hạn (RT-11): mọi preload của cả game bị nạp ở lần change_level đầu và ghim suốt phiên → preload
## scene/texture lớn (kẻ địch, VFX — Mốc 2/3) làm lần nạp đầu + VRAM tăng theo cả game, trái hướng streaming
## Mốc 4; khi đó dùng load() lười ở chỗ dùng hoặc gỡ warm nếu engine đã sửa. Lint in tổng kích thước để thấy khi phình.
## TODO(#120661): xóa warm khi engine có bản sửa — kiểm bằng cách bỏ warm rồi chạy check.py.
const _WARM_INCLUDES: Array[String] = [
	"res://src/world/terrain/terrain_common.gdshaderinc",
	"res://src/world/terrain/terrain_noise.gdshaderinc",
	"res://src/world/grass/foliage_wind.gdshaderinc",
]
const _WARM_PRELOADS: Array[String] = [
	"res://src/entities/player/player.tscn",
	"res://src/world/props/rock/rock_material.tres",
	"res://src/world/props/tree/bark_material.tres",
	"res://src/world/props/tree/leaves_material.tres",
	"res://src/world/props/tree/pine_leaves_material.tres",
]

var current_level: Node = null

var _warm_pins: Array[Resource] = []
var _warm_done := false

var _world_root: Node = null
var _is_transitioning := false
var _fade_rect: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade_rect)


func register_world_root(root: Node) -> void:
	_world_root = root


func is_transitioning() -> bool:
	return _is_transitioning


func change_level(path: String, spawn_id: StringName = &"default") -> void:
	if _is_transitioning:
		return
	if not ResourceLoader.exists(path):
		push_error("Level không tồn tại: %s" % path)
		return
	_is_transitioning = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	if current_level == null:
		_fade_rect.color.a = 1.0 # lần đầu: đen ngay, không cần fade-out
	else:
		await _fade(1.0)

	if not _warm_done:
		await _warm_once()
	var packed := await _load_async(path)
	if packed == null:
		push_error("Không load được level: %s" % path)
		await _fade(0.0)
		_finish_transition()
		return

	GameState.current_level = path
	GameState.spawn_id = spawn_id

	if _world_root == null:
		get_tree().change_scene_to_packed(packed)
		await get_tree().scene_changed
		current_level = get_tree().current_scene
	else:
		if current_level != null:
			_world_root.remove_child(current_level)
			current_level.queue_free()
		current_level = packed.instantiate()
		_world_root.add_child(current_level)

	level_changed.emit(current_level)
	await _fade(0.0)
	_finish_transition()


func _load_async(path: String) -> PackedScene:
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		return null
	while true:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return null
		await get_tree().process_frame
	return ResourceLoader.load_threaded_get(path) as PackedScene


func _warm_once() -> void:
	_warm_done = true
	await _warm_stage(_WARM_INCLUDES) # include trước: shader của preload target có thể #include
	await _warm_stage(_WARM_PRELOADS)


## Request song song cả nhóm (use_sub_threads = false — true rò nhiều hơn), poll mỗi khung.
## Mọi path đều được load_threaded_get để claim request, kể cả khi FAILED (tránh rò kiểu godot#102476).
func _warm_stage(paths: Array[String]) -> void:
	for p in paths:
		ResourceLoader.load_threaded_request(p)
	for p in paths:
		while ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		var res := ResourceLoader.load_threaded_get(p)
		if res != null:
			_warm_pins.append(res)
		else:
			push_warning("[SceneManager] warm thất bại: %s" % p)


func _fade(to_alpha: float, duration: float = FADE_TIME) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", to_alpha, duration)
	await tween.finished


func _finish_transition() -> void:
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false
