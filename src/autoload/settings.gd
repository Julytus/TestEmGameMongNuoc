extends Node
## Cài đặt người dùng (âm lượng, màn hình, đồ họa), lưu ở user://settings.cfg – tách biệt với save game.
##
## Mức đồ họa (F3 / action "cycle_quality" để đổi vòng; dev/CI: "-- --quality=low|medium|high"):
## - HIGH: đúng như level thiết kế (SSR, SSAO, volumetric fog, DOF, MSAA 2x).
## - MEDIUM: tắt SSAO + MSAA; giữ DOF (low), SSR (ít bước), sương thể tích (thô hơn).
## - LOW: tắt SSR / SSAO / volumetric fog / DOF / MSAA, bóng đổ nhỏ hơn và ngắn hơn (×0,75); nước: đáy phẳng (không parallax), bỏ caustic
##   (global shader uniform water_detail). Giữ fog thường, glow, post-process.
## Cỏ/hoa (GrassField, group "grass_field"): Low vẽ ½ số instance và co ngọn ở xa (global foliage_fade_end).
## Render 3D theo tỉ lệ (SCALE_3D: Low 0,6 · Medium 0,77 · High 1,0) rồi upscale; UI (canvas_items) vẫn ở độ phân giải gốc.
## Upscale bilinear: FSR1 tạo quầng tối quanh viền sprite pixel và đắt hơn ~0,2 ms (RTX) / ~0,9 ms (iGPU) – A/B Mốc 1.
## Dev A/B: "-- --scale-mode=fsr|bilinear" đổi bộ upscale (mặc định SCALE_3D_MODE).
## (Đo GPU ở meadow_road, 1280x720: HIGH ~6.5ms, MEDIUM ~6ms, LOW ~2.7ms. Không hiệu ứng đơn lẻ nào
## chiếm phần lớn – tiết kiệm đến từ tắt cả cụm; DOF chỉ ~0.4ms.)
## Level chỉ cần bật hiệu ứng trong Environment như bình thường; Settings chỉ TẮT/GIẢM bớt,
## không bao giờ bật thứ level không dùng (trạng thái gốc nhớ trong meta của resource).

enum Quality { LOW, MEDIUM, HIGH }

const SETTINGS_PATH := "user://settings.cfg"
## FPS khi cửa sổ mất focus (alt-tab) – game vẫn chạy nhưng gần như không tốn GPU.
const BACKGROUND_FPS := 10
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]
## Tỉ lệ độ phân giải render 3D theo mức (index = Quality).
const SCALE_3D: Array[float] = [0.6, 0.77, 1.0]
const SCALE_3D_MODE := Viewport.SCALING_3D_MODE_BILINEAR
## Tỉ lệ instance cỏ/hoa được vẽ theo mức (rừng giữ nguyên).
const GRASS_DENSITY: Array[float] = [0.5, 1.0, 1.0]
## Khoảng cách (m, tới camera) cỏ/hoa co hết theo mức; 0 = không co. Mép xa khung ≈ 28 m (giữa) – 31 m (góc).
const GRASS_FADE_END: Array[float] = [30.0, 0.0, 0.0]
## Hệ số directional_shadow_max_distance của mặt trời theo mức (level đặt vừa tầm camera, ~30 m).
const SHADOW_DISTANCE: Array[float] = [0.75, 1.0, 1.0]

var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var fullscreen: bool = false
var vsync: bool = true
## Giới hạn FPS (0 = không giới hạn). 60 đủ mượt và giữ GPU mát trên màn hình 120/144Hz.
var max_fps: int = 60
var graphics_quality: Quality = Quality.HIGH

var _graphics_pending: bool = false
var _bench_mode: bool = false
var _scale_mode: Viewport.Scaling3DMode = SCALE_3D_MODE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			var index := QUALITY_NAMES.find(arg.trim_prefix("--quality=").capitalize())
			if index >= 0:
				graphics_quality = index as Quality
		elif arg == "--scale-mode=bilinear":
			_scale_mode = Viewport.SCALING_3D_MODE_BILINEAR
		elif arg == "--scale-mode=fsr":
			_scale_mode = Viewport.SCALING_3D_MODE_FSR
	apply()
	# Level mới (WorldEnvironment / Camera3D / đèn) → áp lại mức đồ họa sau khi các _ready() chạy xong
	# (LightingDirector nhân bản Environment trong _ready nên phải đợi deferred).
	get_tree().node_added.connect(_on_node_added)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			Engine.max_fps = BACKGROUND_FPS
		NOTIFICATION_APPLICATION_FOCUS_IN:
			Engine.max_fps = max_fps


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		fullscreen = not fullscreen
		apply()
		save_settings()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"cycle_quality"):
		set_graphics_quality(((graphics_quality + 1) % QUALITY_NAMES.size()) as Quality)
		get_viewport().set_input_as_handled()


func apply() -> void:
	_set_bus_volume(&"Master", master_volume)
	_set_bus_volume(&"Music", music_volume)
	_set_bus_volume(&"SFX", sfx_volume)

	if not _bench_mode:
		var is_fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if fullscreen != is_fullscreen:
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
			)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	Engine.max_fps = max_fps
	apply_graphics()


## BenchRunner gọi: không đụng chế độ cửa sổ, không ghi settings.cfg, vsync bật + 60 FPS như mặc định
## để số đo so được với baseline.
func begin_bench() -> void:
	_bench_mode = true
	vsync = true
	max_fps = 60
	apply()


func set_graphics_quality(quality: Quality) -> void:
	graphics_quality = quality
	apply_graphics()
	save_settings()
	EventBus.toast_requested.emit("Graphics: %s" % QUALITY_NAMES[quality])


## Áp mức đồ họa lên cài đặt render toàn cục + môi trường / camera / mặt trời đang có trong scene.
func apply_graphics() -> void:
	_graphics_pending = false
	var q := graphics_quality
	var viewport := get_viewport()

	# --- Toàn cục ---
	var scale_3d := SCALE_3D[q]
	viewport.scaling_3d_scale = scale_3d
	# Scale 1,0: bilinear = không thêm pass upscale.
	viewport.scaling_3d_mode = _scale_mode if scale_3d < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.msaa_3d = Viewport.MSAA_2X if q == Quality.HIGH else Viewport.MSAA_DISABLED
	RenderingServer.environment_set_ssao_quality(
		RenderingServer.ENV_SSAO_QUALITY_MEDIUM if q == Quality.HIGH else RenderingServer.ENV_SSAO_QUALITY_LOW,
		true, 0.5, 2 if q == Quality.HIGH else 1, 50.0, 300.0
	)
	var fog_size := 64 if q == Quality.HIGH else 48
	RenderingServer.environment_set_volumetric_fog_volume_size(fog_size, fog_size)
	RenderingServer.environment_set_volumetric_fog_filter_active(q == Quality.HIGH)
	RenderingServer.directional_shadow_atlas_set_size(4096 if q != Quality.LOW else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW if q != Quality.LOW else RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW
	)
	RenderingServer.camera_attributes_set_dof_blur_quality(
		RenderingServer.DOF_BLUR_QUALITY_MEDIUM if q == Quality.HIGH else RenderingServer.DOF_BLUR_QUALITY_LOW,
		false
	)
	RenderingServer.global_shader_parameter_set(&"water_detail", 0.0 if q == Quality.LOW else 1.0)
	RenderingServer.global_shader_parameter_set(&"foliage_fade_end", GRASS_FADE_END[q])

	# --- Theo scene ---
	var env := viewport.world_3d.environment if viewport.world_3d else null
	if env:
		_apply_environment(env, q)
	var camera := viewport.get_camera_3d()
	if camera and camera.attributes is CameraAttributesPractical:
		_apply_camera_attributes(camera.attributes as CameraAttributesPractical, q)
	for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var sun := node as DirectionalLight3D
		_remember(sun, &"shadow_mode", sun.directional_shadow_mode)
		sun.directional_shadow_mode = (
			sun.get_meta(&"shadow_mode") if q == Quality.HIGH else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		)
		_remember(sun, &"shadow_max_distance", sun.directional_shadow_max_distance)
		sun.directional_shadow_max_distance = float(sun.get_meta(&"shadow_max_distance")) * SHADOW_DISTANCE[q]
	for node in get_tree().get_nodes_in_group(GrassField.GROUP):
		_apply_grass_field(node as GrassField, q)


func _apply_environment(env: Environment, q: Quality) -> void:
	_remember(env, &"ssr", env.ssr_enabled)
	_remember(env, &"ssr_steps", env.ssr_max_steps)
	_remember(env, &"ssao", env.ssao_enabled)
	_remember(env, &"volumetric_fog", env.volumetric_fog_enabled)
	env.ssr_enabled = env.get_meta(&"ssr") and q != Quality.LOW
	env.ssr_max_steps = env.get_meta(&"ssr_steps") if q == Quality.HIGH else maxi(int(env.get_meta(&"ssr_steps")) >> 1, 8)
	env.ssao_enabled = env.get_meta(&"ssao") and q == Quality.HIGH
	env.volumetric_fog_enabled = env.get_meta(&"volumetric_fog") and q != Quality.LOW


func _apply_grass_field(field: GrassField, q: Quality) -> void:
	if field.mesh_type != GrassField.MeshType.TREE:
		_remember(field, &"range_end", field.visibility_range_end)
		var range_end: float = field.get_meta(&"range_end")
		var fade_end := GRASS_FADE_END[q]
		if fade_end > 0.0 and field.chunk_size > 0.0:
			# Ô bị cắt theo khoảng cách tới TÂM ô → cộng nửa đường chéo ô để chỉ cắt khi cỏ trong ô đã co hết.
			var cut := fade_end + field.chunk_size * 0.7072 + 1.0
			range_end = cut if range_end <= 0.0 else minf(range_end, cut)
		field.visibility_range_end = range_end
		field.sync_chunks()
	field.set_density_scale(GRASS_DENSITY[q])


func _apply_camera_attributes(attributes: CameraAttributesPractical, q: Quality) -> void:
	_remember(attributes, &"dof_far", attributes.dof_blur_far_enabled)
	_remember(attributes, &"dof_near", attributes.dof_blur_near_enabled)
	attributes.dof_blur_far_enabled = attributes.get_meta(&"dof_far") and q != Quality.LOW
	attributes.dof_blur_near_enabled = attributes.get_meta(&"dof_near") and q != Quality.LOW


## Lưu giá trị gốc (do level thiết kế) lần đầu gặp, để mức HIGH khôi phục đúng.
func _remember(obj: Object, key: StringName, value: Variant) -> void:
	if not obj.has_meta(key):
		obj.set_meta(key, value)


func _on_node_added(node: Node) -> void:
	if _graphics_pending:
		return
	if node is WorldEnvironment or node is Camera3D or node is DirectionalLight3D or node is GrassField:
		_graphics_pending = true
		apply_graphics.call_deferred()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	vsync = cfg.get_value("video", "vsync", vsync)
	max_fps = cfg.get_value("video", "max_fps", max_fps)
	graphics_quality = clampi(cfg.get_value("video", "graphics_quality", graphics_quality), 0, Quality.HIGH) as Quality


func save_settings() -> void:
	if _bench_mode:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("video", "graphics_quality", graphics_quality)
	cfg.save(SETTINGS_PATH)


func _set_bus_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
