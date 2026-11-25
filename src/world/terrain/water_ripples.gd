class_name WaterRipples
extends Node
## Gợn sóng bước chân trên mặt nước. Mỗi EventBus.player_footstep trong nước → một vòng sóng: Sprite2D phát
## flipbook bake sẵn (gen_water.py → water_ripple_ring.png) cộng dồn vào một SubViewport nhỏ đi theo người chơi.
## water.gdshader đọc viewport qua global uniform water_ripple_* (R = độ cao → đỉnh sáng theo nấc, G = bọt).
## Chi phí: vài quad 2D vào target 256² + 3 lần đọc texture trong nhánh của shader nước. Khi không còn vòng nào:
## render thêm MỘT khung trống (xóa texture) rồi ngừng cập nhật, water_ripple_strength = 0 → shader bỏ hẳn nhánh.
## Bake-first: không mô phỏng sóng, không vòng lặp trong shader – vòng sóng là ảnh vẽ sẵn.
## Low: ½ số vòng, không có vòng khi đứng yên. Độ phân giải giữ nguyên: thấp hơn 16 px/m làm vòng mảnh răng cưa / lấm tấm.

## Khớp RING_FRAMES trong tools/art/gen_water.py.
const RING_FRAMES := 12
const RING_TEXTURE := preload("res://assets/art/environment/water/water_ripple_ring.png")
## Chân phải vào trong mép nước ít nhất ngần này (m, theo water field – cùng dữ liệu shader cắt mép) mới sinh vòng.
const SHORE_MARGIN := 0.15
## Người chơi cao hơn mặt đất quá mức này (đang nhảy) thì không sinh vòng.
const MAX_FOOT_HEIGHT := 0.25

@export var layout: TerrainLayout
## Vùng (m) viewport gợn sóng phủ quanh người chơi. Vòng sống ring_lifetime giây → đủ cho chạy 4,5 m/s.
@export var area_meters: float = 16.0
## Độ phân giải viewport: 256 / 16 m = 16 px/m = đúng lưới pixel của nước (terrain_snap) → 1 texel = 1 pixel game.
@export var resolution: int = 256
## Số vòng tối đa theo mức (index = Settings.Quality); đầy → tái dùng vòng cũ nhất.
@export var max_rings: PackedInt32Array = [8, 16, 16]
@export var ring_lifetime: float = 1.2
## Đường kính (m) vòng bước chân thường (strength = 1) khi loang hết.
@export var ring_diameter: float = 2.0
## Đứng yên trên nước: cứ ngần này giây sinh một vòng nhẹ quanh chân.
@export var idle_interval: float = 1.6
@export var idle_strength: float = 0.55

var _viewport: SubViewport
var _material: CanvasItemMaterial
var _rings: Array[Sprite2D] = []
var _ring_pos: PackedVector2Array = []
var _ring_life: PackedFloat32Array = []
var _active: bool = false
var _quality: int = -1
var _player: Node3D
var _idle_time: float = 0.0
var _player_xz: Vector2 = Vector2.ZERO
## Góc thế giới XZ của vùng gợn sóng (= water_ripple_rect.xy) – sprite định vị theo gốc này.
var _corner: Vector2 = Vector2.ZERO


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Project bật physics_interpolation: sprite vòng định vị trong _process, nếu để nội suy thì vòng mới / vòng tái dùng
	# bị vẽ ở vị trí trung gian giữa chỗ cũ và chỗ mới 1 khung → lóe sai chỗ (nháy khi đi trên nước).
	_viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_viewport)
	_material = CanvasItemMaterial.new()
	_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_apply_quality()
	RenderingServer.global_shader_parameter_set(&"water_ripple_texture", _viewport.get_texture())
	RenderingServer.global_shader_parameter_set(&"water_ripple_strength", 0.0)
	EventBus.player_footstep.connect(_on_player_footstep)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"water_ripple_strength", 0.0)


## Đổi mức đồ họa → đổi số vòng (gọi lười khi có vòng mới, không cần Settings biết node này).
func _apply_quality() -> void:
	var q := clampi(Settings.graphics_quality, 0, max_rings.size() - 1)
	if q == _quality:
		return
	_quality = q
	_viewport.size = Vector2i(resolution, resolution)
	var count := max_rings[q]
	for ring in _rings:
		ring.queue_free()
	_rings.clear()
	_ring_pos.resize(count)
	_ring_life.resize(count)
	_ring_life.fill(INF)
	for i in count:
		var ring := Sprite2D.new()
		ring.texture = RING_TEXTURE
		ring.hframes = RING_FRAMES
		ring.material = _material
		ring.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ring.visible = false
		_viewport.add_child(ring)
		_rings.append(ring)


func is_water_at(world_xz: Vector2) -> bool:
	return layout != null and layout.get_water_field().distance_at(world_xz) > SHORE_MARGIN


func _on_player_footstep(foot: Vector3, strength: float) -> void:
	if foot.y > MAX_FOOT_HEIGHT or not is_water_at(Vector2(foot.x, foot.z)):
		return
	_idle_time = 0.0
	spawn_ring(Vector2(foot.x, foot.z), strength)


## Sinh một vòng tại world_xz; strength 1 = bước chân, > 1 = vòng to hơn (đáp đất sau nhảy).
func spawn_ring(world_xz: Vector2, strength: float) -> void:
	_apply_quality()
	var slot := 0
	for i in _ring_life.size():
		if _ring_life[i] >= ring_lifetime:
			slot = i
			break
		if _ring_life[i] > _ring_life[slot]:
			slot = i
	var ring := _rings[slot]
	_ring_pos[slot] = world_xz
	_ring_life[slot] = 0.0
	var texels_per_meter := float(resolution) / area_meters
	var diameter := ring_diameter * sqrt(maxf(strength, 0.1)) * randf_range(0.92, 1.08)
	ring.scale = Vector2.ONE * (diameter * texels_per_meter / RING_TEXTURE.get_height())
	ring.modulate = Color(1, 1, 1, clampf(strength, 0.0, 1.0))
	ring.frame = 0
	if not _active:
		_active = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_update_rect()
	# Định vị NGAY (bước chân có thể phát sau _process của node này trong cùng khung) – nếu không, sprite tái dùng
	# được vẽ 1 khung ở vị trí cũ / góc (0,0) → vòng lóe sai chỗ.
	ring.position = (world_xz - _corner) / (area_meters / float(resolution))
	ring.visible = true


func _process(delta: float) -> void:
	_track_player(delta)
	if not _active:
		return
	var alive := false
	for i in _ring_life.size():
		if _ring_life[i] >= ring_lifetime:
			continue
		_ring_life[i] += delta
		if _ring_life[i] >= ring_lifetime:
			_rings[i].visible = false
		else:
			_rings[i].frame = mini(int(_ring_life[i] / ring_lifetime * RING_FRAMES), RING_FRAMES - 1)
			alive = true
	if not alive:
		# Render một khung trống để texture sạch → lần bật sau không lộ vòng cũ ở chỗ khác.
		_active = false
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		RenderingServer.global_shader_parameter_set(&"water_ripple_strength", 0.0)
		return
	_update_rect()
	var texel := area_meters / float(resolution)
	for i in _ring_life.size():
		if _ring_life[i] < ring_lifetime:
			_rings[i].position = (_ring_pos[i] - _corner) / texel
	RenderingServer.global_shader_parameter_set(&"water_ripple_strength", 1.0)


## Vùng gợn sóng đi theo người chơi, gốc snap lưới texel → vòng không trượt / nháy khi camera đi.
func _update_rect() -> void:
	var texel := area_meters / float(resolution)
	_corner = (_player_xz / texel).round() * texel - Vector2.ONE * area_meters * 0.5
	RenderingServer.global_shader_parameter_set(
		&"water_ripple_rect", Vector4(_corner.x, _corner.y, area_meters, area_meters)
	)


## Theo dõi người chơi (tâm vùng gợn sóng) + vòng nhẹ khi đứng yên trên nước (không có ở Low).
func _track_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
		if _player == null:
			return
	var pos := _player.global_position
	var xz := Vector2(pos.x, pos.z)
	var moved := xz.distance_squared_to(_player_xz) > 1e-6
	_player_xz = xz
	if _quality == Settings.Quality.LOW or moved or pos.y > MAX_FOOT_HEIGHT or not is_water_at(xz):
		_idle_time = 0.0
		return
	_idle_time += delta
	if _idle_time >= idle_interval:
		_idle_time = 0.0
		spawn_ring(xz, idle_strength)
