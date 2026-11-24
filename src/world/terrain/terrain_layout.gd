@tool
class_name TerrainLayout
extends Resource
## Bản đồ bố cục địa hình: ảnh RGBA nhỏ, 1 pixel = 1 ô (cell_size mét), tâm ảnh trùng gốc tọa độ thế giới.
## Vẽ/sửa trực tiếp bằng Pixelorama. Quy ước:
##   R = đường đất · G = cỏ cao · B = nước · A = 0 (ô trong suốt, dùng tẩy) = rừng
## TerrainGround, TerrainWater, TerrainCollision và GrassField cùng đọc layout này → luôn khớp nhau.
## Lưu ý: file .import của ảnh layout phải tắt process/fix_alpha_border.

enum Field { NONE = -1, DIRT = 0, TALL_GRASS = 1, WATER = 2, FOREST = 3 }

## Bit cho @export_flags("Dirt", "Tall grass", "Water", "Forest")
const FLAG_DIRT := 1
const FLAG_TALL_GRASS := 2
const FLAG_WATER := 4
const FLAG_FOREST := 8

@export var texture: Texture2D:
	set(value):
		texture = value
		_image = null
		emit_changed()
@export var cell_size: float = 1.0

var _image: Image


func get_world_size() -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return Vector2(texture.get_size()) * cell_size


func get_image() -> Image:
	if _image == null and texture != null:
		_image = texture.get_image()
		if _image != null and _image.is_compressed():
			_image.decompress()
	return _image


## Giá trị layout (nội suy song tuyến, giống filter_linear trong shader) tại tọa độ thế giới XZ.
func sample(world_xz: Vector2) -> Color:
	var img := get_image()
	if img == null:
		return Color(0, 0, 0, 1)
	var size := img.get_size()
	var p := world_xz / cell_size + Vector2(size) * 0.5 - Vector2(0.5, 0.5)
	var x0 := floori(p.x)
	var y0 := floori(p.y)
	var t := p - Vector2(x0, y0)
	var a := _pixel(img, x0, y0).lerp(_pixel(img, x0 + 1, y0), t.x)
	var b := _pixel(img, x0, y0 + 1).lerp(_pixel(img, x0 + 1, y0 + 1), t.x)
	return a.lerp(b, t.y)


## Tâm ô (x, y) của ảnh → tọa độ thế giới XZ.
func cell_to_world(cell: Vector2i) -> Vector2:
	var img := get_image()
	var size := Vector2(img.get_size()) if img else Vector2.ZERO
	return (Vector2(cell) + Vector2(0.5, 0.5) - size * 0.5) * cell_size


static func field_value(c: Color, field: Field) -> float:
	match field:
		Field.DIRT:
			return c.r
		Field.TALL_GRASS:
			return c.g
		Field.WATER:
			return c.b
		Field.FOREST:
			return 1.0 - c.a
	return 1.0


## Ô có thuộc một trong các field trong mask (bit FLAG_*) không – dùng giá trị pixel gốc, không nội suy.
static func matches_mask(c: Color, mask: int) -> bool:
	for field: int in 4:
		if mask & (1 << field) and field_value(c, field as Field) > 0.5:
			return true
	return false


static func _pixel(img: Image, x: int, y: int) -> Color:
	return img.get_pixel(clampi(x, 0, img.get_width() - 1), clampi(y, 0, img.get_height() - 1))


## Đẩy layout vào các shader dùng terrain_common.gdshaderinc.
func apply_to_material(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter(&"layout_map", texture)
	mat.set_shader_parameter(&"layout_size", get_world_size())
