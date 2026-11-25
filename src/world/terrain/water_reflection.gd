class_name WaterReflection
extends MeshInstance3D
## Phản chiếu người chơi trên mặt nước: một quad lật ngược dưới chân, đọc khung sprite hiện tại (water_reflection.gdshader).
## Thay cho SSR (tắt trong meadow_environment.tres: ~0,5 ms GPU ở High 1080p mà gần như không thấy trên nước stylized).
## Chỉ hiện khi người chơi ở gần nước; shader cắt đúng mép nước theo water field. Chạy mọi mức (cả Low).

const SHADER := preload("res://src/world/terrain/water_reflection.gdshader")
## Chân cách mép nước quá ngần này (m, ra phía bờ) thì ẩn – phản chiếu vươn về phía camera ~1,5 m nên phải hiện sớm.
const SHOW_MARGIN := 2.5
## Nhảy cao quá ngần này (m) thì phản chiếu mờ hết.
const FADE_HEIGHT := 3.0

@export var layout: TerrainLayout
## Mặt nước (lấy water_level → độ cao mặt phản chiếu).
@export var water: TerrainWater
@export_range(0.0, 1.0) var opacity: float = 0.5

var _player: Player
var _material: ShaderMaterial
var _last_texture: Texture2D


func _ready() -> void:
	top_level = true
	# Định vị trong _process theo vị trí đã nội suy của người chơi → tắt nội suy của chính node này.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0.0, -0.5, 0.0)
	mesh = quad
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	if layout:
		layout.apply_to_material(_material)
	_material.set_shader_parameter(&"water_height", _water_height())
	material_override = _material
	visible = false


func _water_height() -> float:
	return water.global_position.y if water else -0.06


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player == null or layout == null:
		visible = false
		return
	var sprite := _player.sprite
	var foot := _player.get_global_transform_interpolated().origin
	var near_water := layout.get_water_field().distance_at(Vector2(foot.x, foot.z)) > -SHOW_MARGIN
	var water_y := _water_height()
	var height := foot.y - water_y
	visible = near_water and sprite.visible and height < FADE_HEIGHT
	if not visible:
		return
	var atlas := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame) as AtlasTexture
	if atlas == null:
		visible = false
		return
	var sheet := atlas.atlas
	if sheet != _last_texture:
		_last_texture = sheet
		_material.set_shader_parameter(&"sprite_sheet", sheet)
	var sheet_size := Vector2(sheet.get_size())
	var region := atlas.region
	_material.set_shader_parameter(
		&"frame_rect", Vector4(region.position.x, region.position.y, region.size.x, region.size.y)
			/ Vector4(sheet_size.x, sheet_size.y, sheet_size.x, sheet_size.y)
	)
	_material.set_shader_parameter(&"flip_h", sprite.flip_h)
	_material.set_shader_parameter(&"modulate", sprite.modulate)
	_material.set_shader_parameter(&"opacity", opacity * clampf(1.0 - height / FADE_HEIGHT, 0.0, 1.0))
	# Kích thước & chân sprite theo đúng sprite người chơi (pixel_size, offset, stretch của Visual).
	var stretch := (sprite.get_parent() as Node3D).scale
	var size := region.size * sprite.pixel_size
	var sprite_bottom := (sprite.offset.y - region.size.y * 0.5) * sprite.pixel_size * stretch.y
	# Gương qua mặt nước: điểm cao h trên mặt nước → sâu h dưới mặt nước.
	global_position = Vector3(foot.x, water_y - height - sprite_bottom, foot.z)
	scale = Vector3(size.x * stretch.x, size.y * stretch.y, 1.0)
