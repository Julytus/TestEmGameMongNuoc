extends CanvasLayer
## Overlay hiệu năng debug (F4 / action "toggle_perf_overlay"; dev: "-- --perf-overlay" bật sẵn).
## Số lấy từ PerfSampler — cùng thước đo với bench. Chỉ có ở debug build (release tự xóa).
## Tắt = không tốn khung: không có _process, sampler ngắt signal, Timer dừng. Bật: format chuỗi 4 Hz.

## Tổng ngân sách GPU mức High (docs/PERFORMANCE_ROADMAP.md §2) — dòng GPU đỏ khi TB vượt.
const GPU_BUDGET_MS := 10.0
const WINDOW_MS := 1000.0
const BUDGET_COLOR := Color(1.0, 0.35, 0.3)

var _sampler: PerfSampler = null
var _adapter: String = ""

@onready var _gpu_label: Label = %GpuLabel
@onready var _info_label: Label = %InfoLabel
@onready var _timer: Timer = %RefreshTimer


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	set_process(false)
	_timer.timeout.connect(_refresh)
	if "--perf-overlay" in OS.get_cmdline_user_args():
		_set_enabled(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_perf_overlay"):
		_set_enabled(not visible)
		get_viewport().set_input_as_handled()


func _set_enabled(on: bool) -> void:
	if on:
		if _sampler == null:
			_sampler = PerfSampler.new(256)
			_adapter = RenderingServer.get_video_adapter_name()
		_sampler.start(get_viewport().get_viewport_rid())
		show()
		_timer.start()
		_refresh()
	else:
		if _sampler:
			_sampler.stop()
		_timer.stop()
		hide()


func _refresh() -> void:
	var gpu := _sampler.stats(PerfSampler.Kind.GPU, WINDOW_MS)
	var cpu := _sampler.stats(PerfSampler.Kind.CPU, WINDOW_MS)
	var c := PerfSampler.read_counters()
	_gpu_label.text = "GPU %.2f ms  p95 %.2f" % [gpu.avg, gpu.p95]
	_gpu_label.modulate = BUDGET_COLOR if gpu.avg > GPU_BUDGET_MS else Color.WHITE

	var preset := "-"
	var pos := "-"
	var level := SceneManager.current_level as Level
	if is_instance_valid(level):
		for child in level.get_children():
			var director := child as LightingDirector
			if director and not director.presets.is_empty():
				preset = director.presets[director.current_index].display_name
				break
		if is_instance_valid(level.player):
			var p := level.player.global_position
			pos = "--pos=%.1f,%.1f" % [p.x, p.z]
	_info_label.text = "FPS %d   CPU %.2f ms (p95 %.2f)\ndraw %d   prim %.2f M   nodes %d   VRAM %d MB\n%s · %s · %s\n%s" % [
		Engine.get_frames_per_second(), cpu.avg, cpu.p95,
		c.draw_calls, c.primitives / 1e6, c.nodes, roundi(c.vram_mb),
		Settings.QUALITY_NAMES[Settings.graphics_quality], preset, _adapter,
		pos,
	]
