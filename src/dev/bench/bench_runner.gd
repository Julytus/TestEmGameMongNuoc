class_name BenchRunner
extends Node
## Chế độ bench (`-- --bench=N`, Main tạo): exclusive fullscreen → nạp level → đưa người chơi lần lượt qua các
## BenchPoint (đứng yên), khởi động rồi đo N giây mỗi điểm bằng PerfSampler → ghi JSON (schema 1) → thoát.
## Exit code: 0 xong · 2 lỗi (level không tồn tại, không có người chơi, id trùng, ghi file lỗi, quá watchdog).
##
## Input: nuốt MỌI sự kiện trong _unhandled_input — Runner là con thêm sau cùng của Main nên nhận trước level,
## Main và mọi autoload → F5/F9/F2/F3/F11/F4/Esc/tấn công/né đều vô hiệu khi bench.
## Giới hạn: di chuyển đọc bằng polling Input (player.gd) không chặn được → `drift_m` trong JSON phát hiện.

const SCHEMA := 1
const WARMUP_MIN_FRAMES := 60
const WARMUP_MIN_S := 1.0
const LEVEL_TIMEOUT_S := 120.0
## Bộ đệm mẫu = seconds_per_point × SAMPLER_FPS_CAP (tràn → `sample_overflow`).
const SAMPLER_FPS_CAP := 500

## Số giây đo MỖI điểm (không tính khởi động).
var seconds_per_point: float = 10.0
## Rỗng → user://bench/bench-<thời gian>.json
var out_path: String = ""
var level_path: String = ""
var spawn_id: StringName = &"default"

var _level: Node = null
var _t0_msec: int = 0
var _load_ms: int = 0
var _deadline_msec: int = 0
## Mất focus lúc khởi động/đo (Settings hạ max_fps về 10) → điểm bị đánh dấu `focus_lost`.
var _focus_lost: bool = false


func _ready() -> void:
	if not ResourceLoader.exists(level_path):
		_fail("level không tồn tại: %s" % level_path)
		return
	SceneManager.level_changed.connect(_on_level_changed, CONNECT_ONE_SHOT)
	_run()


func _unhandled_input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func _on_level_changed(level: Node) -> void:
	_level = level
	_load_ms = Time.get_ticks_msec() - _t0_msec


func _run() -> void:
	var tree := get_tree()
	Settings.begin_bench()
	await tree.process_frame
	await tree.process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	for i in 3:
		await tree.process_frame
	_t0_msec = Time.get_ticks_msec()
	SceneManager.change_level(level_path, spawn_id)
	while _level == null:
		if Time.get_ticks_msec() - _t0_msec > LEVEL_TIMEOUT_S * 1000.0:
			_fail("không có level sau %d s: %s" % [int(LEVEL_TIMEOUT_S), level_path])
			return
		await tree.process_frame
	while SceneManager.is_transitioning():
		await tree.process_frame

	var level := _level as Level
	if level == null or level.player == null:
		_fail("level không có người chơi: %s" % level_path)
		return
	var screen := DisplayServer.screen_get_size()
	if tree.root.size != screen:
		_fail("độ phân giải %s ≠ màn hình %s (fullscreen không ăn)" % [tree.root.size, screen])
		return

	var points := _collect_points(level)
	if points.is_empty():
		return # _collect_points đã _fail
	_deadline_msec = _t0_msec + int((LEVEL_TIMEOUT_S + points.size() * (seconds_per_point + 30.0)) * 1000.0)

	var sampler := PerfSampler.new(ceili(seconds_per_point * SAMPLER_FPS_CAP))
	sampler.start(get_viewport().get_viewport_rid())
	var results: Array[Dictionary] = []
	for i in points.size():
		var r := await _measure_point(level, points[i], i, sampler)
		if r.is_empty():
			sampler.stop()
			return # đã _fail
		results.append(r)
	sampler.stop()
	_write_json(level, results)


## Mỗi phần tử: {id: StringName, pos: Vector3}. Level không có BenchPoint → 1 điểm ngầm "start" tại người chơi.
func _collect_points(level: Level) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for node in get_tree().get_nodes_in_group(&"bench_points"):
		var bp := node as BenchPoint
		if bp == null or not level.is_ancestor_of(bp):
			continue
		if bp.id == &"" or seen.has(bp.id):
			_fail("BenchPoint id rỗng hoặc trùng: '%s' (%s)" % [bp.id, bp.get_path()])
			return []
		seen[bp.id] = true
		out.append({"id": bp.id, "pos": bp.global_position})
	if out.is_empty():
		print("[Bench] level không có BenchPoint → đo 1 điểm 'start'")
		out.append({"id": &"start", "pos": level.player.global_position})
	return out


func _measure_point(level: Level, point: Dictionary, index: int, sampler: PerfSampler) -> Dictionary:
	var tree := get_tree()
	var player := level.player
	var id: StringName = point["id"]
	player.global_position = point["pos"]
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	if level.follow_camera:
		level.follow_camera.snap_to_target()
	EventBus.bench_point_entered.emit(id)

	_focus_lost = not get_window().has_focus()
	var start_usec := Time.get_ticks_usec()
	var frames := 0
	while frames < WARMUP_MIN_FRAMES or (Time.get_ticks_usec() - start_usec) < WARMUP_MIN_S * 1e6:
		await tree.process_frame
		frames += 1
		if not _tick_ok():
			return {}

	sampler.clear()
	var pos0 := player.global_position
	var quality := Settings.QUALITY_NAMES[Settings.graphics_quality].to_lower()
	var lighting := _lighting_name(level)
	start_usec = Time.get_ticks_usec()
	while (Time.get_ticks_usec() - start_usec) < seconds_per_point * 1e6:
		await tree.process_frame
		if not _tick_ok():
			return {}

	var gpu := sampler.stats(PerfSampler.Kind.GPU)
	var cpu := sampler.stats(PerfSampler.Kind.CPU)
	var wall := sampler.stats(PerfSampler.Kind.WALL)
	var c := PerfSampler.read_counters()
	var drift := pos0.distance_to(player.global_position)
	print("[Bench] %s gpu p50=%.3f p95=%.3f cpu p50=%.3f draw=%d prims=%d" % [
		id, gpu.p50, gpu.p95, cpu.p50, c.draw_calls, c.primitives])
	var pos: Vector3 = point["pos"]
	return {
		"id": String(id),
		"index": index,
		"pos": [pos.x, pos.z],
		"quality": quality,
		"lighting": lighting,
		"frames": gpu.count,
		"gpu_ms": _full(gpu),
		"cpu_ms": _full(cpu),
		"wall_ms": {"p50": wall.p50, "p99": wall.p99, "max": wall.max},
		"physics_ms_max_1s": c.physics_ms,
		"draw_calls": c.draw_calls,
		"primitives": c.primitives,
		"nodes": c.nodes,
		"vram_mb": c.vram_mb,
		"drift_m": drift,
		"focus_lost": _focus_lost,
		"sample_overflow": sampler.overflowed(),
	}


## Gọi mỗi khung trong khởi động/đo: ghi mất focus + watchdog tổng. false = đã _fail.
## Focus đọc trực tiếp mỗi khung (NOTIFICATION_APPLICATION_FOCUS_* báo sai sau khi đổi exclusive fullscreen — probe P2).
func _tick_ok() -> bool:
	if not get_window().has_focus():
		_focus_lost = true
	if Time.get_ticks_msec() > _deadline_msec:
		_fail("quá watchdog tổng (%d s)" % ((_deadline_msec - _t0_msec) / 1000))
		return false
	return true


func _write_json(level: Level, points: Array[Dictionary]) -> void:
	var path := out_path
	if path == "":
		path = "user://bench/bench-%s.json" % Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "-")
	path = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var data := {
		"meta": {
			"schema": SCHEMA,
			"godot": Engine.get_version_info().string,
			"driver": OS.get_video_adapter_driver_info(),
			"api_version": RenderingServer.get_video_adapter_api_version(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
			"adapter_type": RenderingServer.get_video_adapter_type(),
			"resolution": [get_tree().root.size.x, get_tree().root.size.y],
			"window_mode": DisplayServer.window_get_mode(),
			"quality": Settings.QUALITY_NAMES[Settings.graphics_quality].to_lower(),
			"lighting": _lighting_name(level),
			"level": level_path,
			"load_ms": _load_ms,
			"seconds_per_point": seconds_per_point,
			"warmup_min_frames": WARMUP_MIN_FRAMES,
			"warmup_min_s": WARMUP_MIN_S,
			"vsync_mode": DisplayServer.window_get_vsync_mode(),
			"max_fps": Engine.max_fps,
			"debug_build": OS.is_debug_build(),
			"timestamp": Time.get_datetime_string_from_system(),
			"args": OS.get_cmdline_user_args(),
		},
		"points": points,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("không ghi được %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("[Bench] JSON → %s" % path)
	get_tree().quit.call_deferred(0)


func _lighting_name(level: Node) -> String:
	for node in level.find_children("*", "", true, false):
		var director := node as LightingDirector
		if director and not director.presets.is_empty():
			return director.presets[director.current_index].display_name.to_lower()
	return ""


static func _full(s: PerfSampler.Stats) -> Dictionary:
	return {"avg": s.avg, "p50": s.p50, "p95": s.p95, "p99": s.p99, "max": s.max}


func _fail(msg: String) -> void:
	push_error("[Bench] " + msg)
	get_tree().quit(2)
