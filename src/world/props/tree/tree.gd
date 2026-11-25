@tool
class_name StylizedTree
extends StaticBody3D
## Cây đặt lẻ: mesh 3D stylized bake sẵn (TreeMeshBuilder.get_mesh nạp .res — thân + tán thẻ lá) + va chạm thân cây.
## Rừng dày quanh map dùng GrassField (mesh_type = Tree) với cùng bộ mesh, rẻ hơn nhiều.

@export var variant: TreeMeshBuilder.Variant = TreeMeshBuilder.Variant.OAK:
	set(value):
		variant = value
		_apply()
## Đổi seed để có hình dáng khác cùng loài (chỉ các seed đã bake: 0..BAKED_SEEDS-1).
@export_range(0, TreeMeshBuilder.BAKED_SEEDS - 1) var tree_seed: int = 0:
	set(value):
		tree_seed = value
		_apply()

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	_apply()


func _notification(what: int) -> void:
	# Mesh gán từ code (theo variant/seed) – không lưu vào .tscn
	if what == NOTIFICATION_EDITOR_PRE_SAVE and _mesh:
		_mesh.mesh = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	_mesh.mesh = TreeMeshBuilder.get_mesh(variant, tree_seed)
