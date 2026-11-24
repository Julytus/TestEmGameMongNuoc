@tool
class_name StylizedRock
extends StaticBody3D
## Tảng đá 3D kiểu pixel art: mesh do RockMeshBuilder sinh + rock_material (bậc sáng, hue-shift, viền tối)
## + va chạm trụ.

@export var variant: RockMeshBuilder.Variant = RockMeshBuilder.Variant.BOULDER:
	set(value):
		variant = value
		_apply()
## Đổi seed để có hình dáng khác cùng kiểu.
@export var rock_seed: int = 0:
	set(value):
		rock_seed = value
		_apply()

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_apply()


## GrassField gọi để bỏ cỏ mọc xuyên qua đá (rock.tscn nằm trong group grass_blocker).
func grass_clear_radius() -> float:
	return RockMeshBuilder.footprint_radius(variant) * global_basis.get_scale().x


func _notification(what: int) -> void:
	# Mesh sinh bằng code – không lưu vào .tscn
	if what == NOTIFICATION_EDITOR_PRE_SAVE and _mesh:
		_mesh.mesh = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	_mesh.mesh = RockMeshBuilder.get_mesh(variant, rock_seed)
	var size := RockMeshBuilder.collision_size(variant)
	var shape := CylinderShape3D.new()
	shape.radius = size.x
	shape.height = size.y
	_collision.shape = shape
	_collision.position = Vector3(0.0, size.y * 0.5, 0.0)
