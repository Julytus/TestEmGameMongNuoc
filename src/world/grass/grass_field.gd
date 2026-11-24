@tool
class_name GrassField
extends MultiMeshInstance3D
## Rải cỏ bằng MultiMesh: hàng chục nghìn ngọn cỏ chỉ tốn 1 draw call.
## Gió + tương tác người chơi xử lý trên GPU (grass.gdshader / grass_card.gdshader).
## Cũng dùng để rải hoa, bụi và cả rừng cây (mesh_type = Card + atlas cây).
##
## Map lớn: chia thành nhiều GrassField nhỏ (vd 16x16m) để frustum culling loại bớt phần ngoài màn hình,
## và đặt visibility_range_end để tắt cỏ ở xa.

const MAX_INSTANCES := 200000
const FLOATS_PER_INSTANCE := 16 # 12 (Transform3D) + 4 (custom data)
## Group của các vật thể cấm cỏ mọc bên dưới (đá...), xem _collect_blockers().
const GRASS_BLOCKER_GROUP := &"grass_blocker"

enum MeshType {
	BLADE, ## Ngọn cỏ 3D (grass.gdshader, grass_material.tres)
	CARD, ## Quad billboard dán texture pixel art (grass_card.gdshader)
	TREE, ## Cây 3D stylized từ TreeMeshBuilder (material nằm sẵn trong mesh, để trống material_override)
}

@export var mesh_type: MeshType = MeshType.BLADE
## Chỉ dùng khi mesh_type = Tree. height_range khi đó là hệ số scale của cây.
@export var tree_variant: TreeMeshBuilder.Variant = TreeMeshBuilder.Variant.OAK
@export var area_size: Vector2 = Vector2(20.0, 20.0)
## Số ngọn cỏ trên mỗi m².
@export_range(0.0, 200.0, 0.5) var density: float = 20.0
@export var height_range: Vector2 = Vector2(0.3, 0.65)
## Blade: bề rộng ngọn cỏ (m). Card: tỉ lệ rộng/cao của quad (32x24 px → 1.333).
@export var blade_width: float = 0.07
@export var random_seed: int = 1
## Vùng không mọc cỏ (đường đi, nhà...) theo tọa độ local XZ: Rect2(x, z, width, depth).
@export var exclude_rects: Array[Rect2] = []
## Độ "răng cưa" mép vùng loại trừ cho tự nhiên.
@export var edge_softness: float = 0.4

@export_group("Layout")
## Đọc bố cục từ ảnh layout (cùng ảnh với TerrainGround) thay vì / cùng với exclude_rects.
@export var layout: TerrainLayout
## Field quyết định mật độ (0..1). NONE = mọc đều.
@export var density_field: TerrainLayout.Field = TerrainLayout.Field.NONE
## Các field cấm mọc: bỏ instance nơi giá trị field > 0.5 (mép lượn theo edge_softness).
@export_flags("Dirt", "Tall grass", "Water", "Forest") var avoid_mask: int = TerrainLayout.FLAG_DIRT | TerrainLayout.FLAG_WATER
## Mức giảm chiều cao ở nơi mật độ thấp (0 = không đổi).
@export_range(0.0, 1.0) var height_by_density: float = 0.4
@export_group("")
@export_tool_button("Regenerate", "Reload") var regenerate_action: Callable = regenerate


func _ready() -> void:
	regenerate()


func _notification(what: int) -> void:
	# Không lưu buffer MultiMesh (rất nặng) vào file .tscn – luôn sinh lại khi load.
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		multimesh = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		regenerate()


func regenerate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var target_count := mini(int(area_size.x * area_size.y * density), MAX_INSTANCES)
	var half := area_size * 0.5

	var blockers := _collect_blockers()
	var buffer := PackedFloat32Array()
	buffer.resize(target_count * FLOATS_PER_INSTANCE)
	var count := 0
	for i in target_count:
		var pos := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
		if _is_excluded(pos, rng.randf() * edge_softness) or _is_blocked(pos, blockers):
			continue
		var accept := rng.randf()
		var jitter := (rng.randf() - 0.5) * edge_softness
		var dens := _layout_density(pos, jitter) if layout else 1.0
		if accept > dens:
			continue
		# Mép vùng (mật độ thấp) cây/cỏ thấp hơn → khối cỏ nhô cao dần vào giữa
		var height := rng.randf_range(height_range.x, height_range.y) * lerpf(1.0 - height_by_density, 1.0, dens)
		var basis: Basis
		if mesh_type == MeshType.CARD:
			basis = Basis.from_scale(Vector3(height * blade_width, height, height * blade_width))
		elif mesh_type == MeshType.TREE:
			basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * height)
		else:
			basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, height, 1.0))
		var o := count * FLOATS_PER_INSTANCE
		buffer[o + 0] = basis.x.x
		buffer[o + 1] = basis.y.x
		buffer[o + 2] = basis.z.x
		buffer[o + 3] = pos.x
		buffer[o + 4] = basis.x.y
		buffer[o + 5] = basis.y.y
		buffer[o + 6] = basis.z.y
		buffer[o + 7] = 0.0
		buffer[o + 8] = basis.x.z
		buffer[o + 9] = basis.y.z
		buffer[o + 10] = basis.z.z
		buffer[o + 11] = pos.y
		buffer[o + 12] = rng.randf() # INSTANCE_CUSTOM.x: biến thể màu/pha gió
		buffer[o + 13] = rng.randf() # INSTANCE_CUSTOM.y: lật ngang (Card)
		buffer[o + 14] = height
		buffer[o + 15] = 0.0
		count += 1
	buffer.resize(count * FLOATS_PER_INSTANCE)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	match mesh_type:
		MeshType.CARD:
			mm.mesh = _build_card_mesh()
		MeshType.TREE:
			mm.mesh = TreeMeshBuilder.get_mesh(tree_variant, random_seed % 3)
		_:
			mm.mesh = _build_blade_mesh(blade_width)
	mm.instance_count = count
	if count > 0:
		mm.buffer = buffer
	# AABB nới rộng để gió/rẽ cỏ không làm ngọn cỏ bị cull sai
	mm.custom_aabb = AABB(
		Vector3(-half.x - 1.0, -0.5, -half.y - 1.0),
		Vector3(area_size.x + 2.0, height_range.y * (7.0 if mesh_type == MeshType.TREE else 1.0) + 1.5, area_size.y + 2.0)
	)
	multimesh = mm


## Mật độ (0..1) tại điểm theo layout; 0 nếu thuộc vùng bị cấm (avoid_mask).
func _layout_density(local_pos: Vector2, jitter: float) -> float:
	var world := Vector2(local_pos)
	if is_inside_tree():
		var w := global_transform * Vector3(local_pos.x, 0.0, local_pos.y)
		world = Vector2(w.x, w.z)
	var value := layout.sample(world)
	for field: int in 4:
		if avoid_mask & (1 << field) and TerrainLayout.field_value(value, field as TerrainLayout.Field) + jitter > 0.5:
			return 0.0
	return TerrainLayout.field_value(value, density_field)


## Vật thể trong group GRASS_BLOCKER_GROUP (đá...) có hàm grass_clear_radius() -> float (m, world).
## Trả về [x, z, bán kính] theo tọa độ local của field.
func _collect_blockers() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not is_inside_tree():
		return out
	var inv := global_transform.affine_inverse()
	for node in get_tree().get_nodes_in_group(GRASS_BLOCKER_GROUP):
		var n3 := node as Node3D
		if n3 == null or not n3.has_method(&"grass_clear_radius"):
			continue
		var local := inv * n3.global_position
		var radius: float = n3.call(&"grass_clear_radius")
		out.append(Vector3(local.x, local.z, radius))
	return out


func _is_blocked(pos: Vector2, blockers: Array[Vector3]) -> bool:
	for b in blockers:
		if pos.distance_squared_to(Vector2(b.x, b.y)) < b.z * b.z:
			return true
	return false


func _is_excluded(pos: Vector2, margin: float) -> bool:
	for rect in exclude_rects:
		if rect.grow(margin).has_point(pos):
			return true
	return false


## Ngọn cỏ cao 1 đơn vị (được scale theo instance), thon dần, hơi cong. UV.y = độ cao (0 gốc → 1 ngọn).
static func _build_blade_mesh(width: float) -> ArrayMesh:
	const SEGMENTS := 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in SEGMENTS:
		var t := float(i) / SEGMENTS
		var w := width * (1.0 - t) * 0.5
		var curve := t * t * 0.12
		st.set_uv(Vector2(0.0, t))
		st.add_vertex(Vector3(-w, t, curve))
		st.set_uv(Vector2(1.0, t))
		st.add_vertex(Vector3(w, t, curve))
	st.set_uv(Vector2(0.5, 1.0))
	st.add_vertex(Vector3(0.0, 1.0, 0.12))

	for i in SEGMENTS - 1:
		var a := i * 2
		st.add_index(a)
		st.add_index(a + 2)
		st.add_index(a + 1)
		st.add_index(a + 1)
		st.add_index(a + 2)
		st.add_index(a + 3)
	var last := (SEGMENTS - 1) * 2
	st.add_index(last)
	st.add_index(SEGMENTS * 2)
	st.add_index(last + 1)
	return st.commit()


## Quad đơn vị (rộng 1, cao 1, gốc ở đáy giữa). UV.y = 0 ở ngọn, 1 ở gốc (theo quy ước texture).
## Shader billboard tự xoay quad về camera và scale theo instance.
static func _build_card_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var corners: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)]
	for uv in corners:
		st.set_uv(uv)
		st.add_vertex(Vector3(uv.x - 0.5, 1.0 - uv.y, 0.0))
	for i: int in [0, 2, 1, 1, 2, 3]:
		st.add_index(i)
	return st.commit()
