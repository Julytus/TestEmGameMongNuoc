class_name PerfSampler
extends RefCounted
## Lấy mẫu thời gian khung (GPU / CPU / wall) — một nguồn số dùng chung cho bench (BenchRunner) và overlay F4.
##
## - GPU = viewport_get_measured_render_time_gpu; CPU = logic (process_frame → frame_pre_draw) + render CPU
##   của viewport + frame setup. Số render trễ 2 khung so với logic — vô hại khi cảnh đứng yên (điểm bench).
## - Không dùng Performance.TIME_PROCESS (là max của 1 s và gồm cả thời gian chờ GPU).
## - Ghi vào bộ đệm vòng PackedFloat32Array cấp sẵn: callback mỗi khung không cấp phát.
## - stop() ngắt signal → khi tắt chi phí = 0. Đo render time của viewport bật lại một lần và để luôn bật
##   (tắt lại có thể làm hỏng một bench/overlay khác đang dùng cùng viewport).

enum Kind { GPU, CPU, WALL }


class Stats:
	var avg: float = 0.0
	var p50: float = 0.0
	var p95: float = 0.0
	var p99: float = 0.0
	var max: float = 0.0
	var count: int = 0


class Counters:
	var draw_calls: int = 0
	var primitives: int = 0
	var nodes: int = 0
	var vram_mb: float = 0.0
	## Max thời gian physics trong 1 s gần nhất (ms).
	var physics_ms: float = 0.0


var _capacity: int
var _gpu := PackedFloat32Array()
var _cpu := PackedFloat32Array()
var _wall := PackedFloat32Array()
var _written: int = 0
var _last_usec: int = -1
var _logic_ms: float = 0.0
var _viewport: RID


func _init(capacity: int = 256) -> void:
	_capacity = maxi(capacity, 1)
	_gpu.resize(_capacity)
	_cpu.resize(_capacity)
	_wall.resize(_capacity)


func start(viewport_rid: RID) -> void:
	_viewport = viewport_rid
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	var tree := Engine.get_main_loop() as SceneTree
	if not tree.process_frame.is_connected(_on_process_frame):
		tree.process_frame.connect(_on_process_frame)
	if not RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	clear()


func stop() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree.process_frame.is_connected(_on_process_frame):
		tree.process_frame.disconnect(_on_process_frame)
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)


func clear() -> void:
	_written = 0
	_last_usec = -1


## Số mẫu hợp lệ trong bộ đệm (≤ capacity).
func sample_count() -> int:
	return mini(_written, _capacity)


## Đã ghi nhiều mẫu hơn capacity kể từ clear() (mẫu cũ bị ghi đè).
func overflowed() -> bool:
	return _written > _capacity


func _on_process_frame() -> void:
	var now := Time.get_ticks_usec()
	if _last_usec >= 0:
		var i := _written % _capacity
		_wall[i] = (now - _last_usec) / 1000.0
		_gpu[i] = RenderingServer.viewport_get_measured_render_time_gpu(_viewport)
		_cpu[i] = (_logic_ms + RenderingServer.viewport_get_measured_render_time_cpu(_viewport)
				+ RenderingServer.get_frame_setup_time_cpu())
		_written += 1
	_last_usec = now


func _on_pre_draw() -> void:
	if _last_usec >= 0:
		_logic_ms = (Time.get_ticks_usec() - _last_usec) / 1000.0


## Thống kê một loại mẫu. window_ms > 0: chỉ lấy các mẫu mới nhất có tổng wall ≤ window_ms.
## Sort một bản sao → chỉ gọi vài lần/giây (overlay 4 Hz) hoặc cuối điểm đo (bench).
func stats(kind: Kind, window_ms: float = 0.0) -> Stats:
	var src: PackedFloat32Array = _gpu if kind == Kind.GPU else (_cpu if kind == Kind.CPU else _wall)
	var n := sample_count()
	var picked := PackedFloat32Array()
	var acc := 0.0
	for k in n:
		var i := (_written - 1 - k) % _capacity
		if window_ms > 0.0:
			acc += _wall[i]
			if acc > window_ms and picked.size() > 0:
				break
		picked.append(src[i])
	var s := Stats.new()
	s.count = picked.size()
	if s.count == 0:
		return s
	picked.sort()
	var total := 0.0
	for v in picked:
		total += v
	s.avg = total / s.count
	s.p50 = _rank(picked, 0.50)
	s.p95 = _rank(picked, 0.95)
	s.p99 = _rank(picked, 0.99)
	s.max = picked[s.count - 1]
	return s


static func read_counters() -> Counters:
	var c := Counters.new()
	c.draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	c.primitives = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	c.nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	c.vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	c.physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return c


## Percentile nearest-rank trên mảng đã sort.
static func _rank(sorted: PackedFloat32Array, p: float) -> float:
	var n := sorted.size()
	return sorted[clampi(ceili(p * n) - 1, 0, n - 1)]
