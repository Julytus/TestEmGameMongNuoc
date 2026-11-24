extends Node
## Chuyển level có fade + load bất đồng bộ (không đứng hình khi map lớn).
##
## Kiến trúc: Main giữ một node "World" cố định; level được thay bên trong World,
## còn HUD/menu nằm ngoài nên tồn tại xuyên suốt game.
## Nếu chạy thẳng một level (F6 trong editor) thì World chưa đăng ký → fallback đổi cả scene.

signal level_changed(level: Node)

const FADE_TIME := 0.35

var current_level: Node = null

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


func _fade(to_alpha: float, duration: float = FADE_TIME) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", to_alpha, duration)
	await tween.finished


func _finish_transition() -> void:
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false
