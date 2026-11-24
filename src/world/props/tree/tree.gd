@tool
class_name StylizedTree
extends StaticBody3D
## Cây đặt lẻ: mesh 3D stylized do TreeMeshBuilder sinh (thân + tán thẻ lá) + va chạm thân cây.
## Rừng dày quanh map dùng GrassField (mesh_type = Tree) với cùng bộ mesh, rẻ hơn nhiều.

@export var variant: TreeMeshBuilder.Variant = TreeMeshBuilder.Variant.OAK:
	set(value):
		variant = value
		_apply()
## Đổi seed để có hình dáng khác cùng loài.
@export var tree_seed: int = 0:
	set(value):
		tree_seed = value
		_apply()

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	_apply()


func _notification(what: int) -> void:
	# Mesh sinh bằng code – không lưu vào .tscn
	if what == NOTIFICATION_EDITOR_PRE_SAVE and _mesh:
		_mesh.mesh = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	_mesh.mesh = TreeMeshBuilder.get_mesh(variant, tree_seed)
