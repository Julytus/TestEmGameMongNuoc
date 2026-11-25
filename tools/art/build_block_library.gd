extends SceneTree
## Dựng MeshLibrary cho block 1 m (cỏ / đất / đá) từ atlas do gen_blocks.py sinh — bake-first, không dựng lúc chạy.
##
## Chạy (sau `python tools/art/gen_blocks.py` + import):
##   <godot> --headless --path . --script res://tools/art/build_block_library.gd
## Ghi đè: res://src/world/blocks/blocks_library.tres
##
## Item id = mask * 3 + loại (0 Grass, 1 Dirt, 2 Stone), mask 6 bit = ô kề có khối (thứ tự BlockGrid.NEIGHBORS)
## → 192 biến thể; BlockGrid (block_grid.gd) tự chọn id theo hàng xóm. Cạnh giáp khối khác: phẳng tới mép (không
## bo, không rãnh); mặt giáp khối khác: bỏ. Khối cỏ có khối đè lên: cạnh dùng ô đất (không lộ dải cỏ giữa chồng).
## Mesh hộp BO CẠNH (bán kính BEVEL, lưới mỗi mặt EDGE_STOPS², pháp tuyến mượt
## qua mép → ánh sáng chia bậc của block.gdshader cho dải sáng/tối mềm ở cạnh), AO bake vào vertex color
## (chân khối tối dần). Va chạm vẫn là hộp vuông 1 m. Gốc ở ĐÁY-giữa (x,z ∈ [-0,5; 0,5], y ∈ [0; 1]) →
## GridMap dùng cell_size = 1 và cell_center_y = false để đáy khối nằm đúng mặt lưới.
## Sub-resource có id cố định (resource_scene_unique_id) để chạy lại không đổi file (git diff sạch).

const ATLAS_TILES := 4.0 ## khớp TILES trong gen_blocks.py: 0 grass_top, 1 grass_side, 2 dirt, 3 stone
const TILE_GRASS_TOP := 0
const TILE_GRASS_SIDE := 1
const TILE_DIRT := 2
const TILE_STONE := 3
## Thu UV vào trong ô một chút để lọc nearest không lấy nhầm texel ô bên cạnh ở mép mặt.
const UV_INSET := 0.001
## Bán kính bo cạnh (m). 0.1 m ≈ 3 px atlas — đủ thấy mềm, khe giữa 2 khối kề nhau không quá sâu.
const BEVEL := 0.1
## Vị trí lưới trên trục mặt (đơn vị bán kính tính từ mép): 0 = mép, 1 = hết dải bo. 2 bước bo → ~300 tam giác/khối.
const EDGE_STOPS: Array[float] = [0.0, 0.35, 1.0]
## AO chân khối (chỉ khi dưới không có khối): vertex color ở đáy = AO_MIN, sáng dần lên tới chiều cao AO_HEIGHT.
const AO_MIN := 0.68
const AO_HEIGHT := 0.45
const MATERIAL_PATH := "res://src/world/blocks/block_material.tres"
const OUT_PATH := "res://src/world/blocks/blocks_library.tres"

## name -> [top, side, bottom] (chỉ số ô atlas)
const BLOCKS: Array[Array] = [
	[&"Grass", TILE_GRASS_TOP, TILE_GRASS_SIDE, TILE_DIRT],
	[&"Dirt", TILE_DIRT, TILE_DIRT, TILE_DIRT],
	[&"Stone", TILE_STONE, TILE_STONE, TILE_STONE],
]

## Vertex color (AO) gom trong lúc dựng một mesh (_face ghi vào, _build_box đưa vào ARRAY_COLOR).
var _colors := PackedColorArray()
## Mặt nạ hàng xóm của mesh đang dựng.
var _mask := 0


func _initialize() -> void:
	var material := load(MATERIAL_PATH) as Material
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	shape.resource_scene_unique_id = "BlockShape"
	var shape_xform := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0))
	var library := MeshLibrary.new()
	assert(BLOCKS.size() == BlockGrid.TYPE_COUNT)
	for mask in BlockGrid.VARIANT_COUNT:
		for type in BLOCKS.size():
			var spec: Array = BLOCKS[type]
			var id := mask * BlockGrid.TYPE_COUNT + type
			var item_name := String(spec[0]) if mask == 0 else "%s_%02d" % [spec[0], mask]
			_mask = mask
			var side: int = TILE_DIRT if spec[2] == TILE_GRASS_SIDE and _has(Vector3i.UP) else spec[2]
			var mesh := _build_box(spec[1], side, spec[3], material)
			mesh.resource_scene_unique_id = "Mesh_%s" % item_name
			library.create_item(id)
			library.set_item_name(id, item_name)
			library.set_item_mesh(id, mesh)
			library.set_item_shapes(id, [shape, shape_xform])
	var err := ResourceSaver.save(library, OUT_PATH)
	print("[build_block_library] %s -> %s" % [error_string(err), OUT_PATH])
	quit(0 if err == OK else 1)


## Có khối ở ô kề theo hướng dir (trục đơn vị) với mặt nạ đang dựng?
func _has(dir: Vector3i) -> bool:
	return _mask & (1 << BlockGrid.NEIGHBORS.find(dir)) != 0


func _build_box(top: int, side: int, bottom: int, material: Material) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	_colors = PackedColorArray()
	# Mỗi mặt: pháp tuyến, trục u (trái→phải khi nhìn từ ngoài), trục v (trên→dưới), ô atlas.
	# Mặt cạnh: v hướng -Y để viền cỏ nằm ở trên.
	_face(verts, normals, uvs, indices, Vector3.UP, Vector3.RIGHT, Vector3.BACK, top)
	_face(verts, normals, uvs, indices, Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD, bottom)
	_face(verts, normals, uvs, indices, Vector3.BACK, Vector3.RIGHT, Vector3.DOWN, side)
	_face(verts, normals, uvs, indices, Vector3.FORWARD, Vector3.LEFT, Vector3.DOWN, side)
	_face(verts, normals, uvs, indices, Vector3.RIGHT, Vector3.FORWARD, Vector3.DOWN, side)
	_face(verts, normals, uvs, indices, Vector3.LEFT, Vector3.BACK, Vector3.DOWN, side)
	var mesh := ArrayMesh.new()
	if verts.is_empty():  # bị bao kín 6 phía: không mặt nào lộ
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


## Thêm một mặt của hộp bo cạnh đáy-giữa (bỏ qua nếu ô kề phía n có khối). u, v: trục texture (nhìn từ ngoài).
## Mỗi điểm lưới p trên mặt phẳng hộp được chiếu lên hộp bo: inner = clamp(p) vào hộp co BEVEL (không co ở phía
## có hàng xóm), vị trí = inner + hướng(p - inner) · BEVEL → điểm mép hai mặt kề nhau trùng vị trí + pháp tuyến.
func _face(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, n: Vector3, u: Vector3, v: Vector3, tile: int) -> void:
	if _has(Vector3i(n)):
		return
	var lo := Vector3.ONE * -0.5
	var hi := Vector3.ONE * 0.5
	for axis in 3:
		var dir := Vector3i.ZERO
		dir[axis] = 1
		if not _has(dir):
			hi[axis] -= BEVEL
		if not _has(-dir):
			lo[axis] += BEVEL
	var su := _stops(not _has(Vector3i(-u)), not _has(Vector3i(u)))
	var sv := _stops(not _has(Vector3i(-v)), not _has(Vector3i(v)))
	var base := verts.size()
	var u0 := tile / ATLAS_TILES + UV_INSET
	var u1 := (tile + 1) / ATLAS_TILES - UV_INSET
	var ao_on := not _has(Vector3i.DOWN)
	for j in sv.size():
		for i in su.size():
			var p := n * 0.5 + u * su[i] + v * sv[j]
			var inner := p.clamp(lo, hi)
			var d := p - inner
			var normal := d.normalized() if d.length_squared() > 0.0 else n
			var pos := inner + normal * BEVEL if d.length_squared() > 0.0 else p
			verts.append(pos + Vector3(0.0, 0.5, 0.0))
			normals.append(normal)
			uvs.append(Vector2(lerpf(u0, u1, su[i] + 0.5), lerpf(UV_INSET, 1.0 - UV_INSET, sv[j] + 0.5)))
			var ao := lerpf(AO_MIN, 1.0, clampf((pos.y + 0.5) / AO_HEIGHT, 0.0, 1.0)) if ao_on else 1.0
			_colors.append(Color(ao, ao, ao))
	# Godot: mặt trước theo chiều kim đồng hồ khi nhìn từ phía pháp tuyến.
	var flip := u.cross(v).dot(n) > 0.0
	var count := su.size()
	for j in sv.size() - 1:
		for i in count - 1:
			var a := base + j * count + i
			var b := a + 1
			var c := a + count + 1
			var e := a + count
			if flip:
				indices.append_array([a, c, b, a, e, c])
			else:
				indices.append_array([a, b, c, a, c, e])


## Vị trí lưới dọc một trục mặt (-0,5..0,5): thêm các bước bo ở đầu nào có cạnh bo.
func _stops(bevel_lo: bool, bevel_hi: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array([-0.5])
	if bevel_lo:
		for k in range(1, EDGE_STOPS.size()):
			out.append(-0.5 + EDGE_STOPS[k] * BEVEL)
	if bevel_hi:
		for k in range(EDGE_STOPS.size() - 1, 0, -1):
			out.append(0.5 - EDGE_STOPS[k] * BEVEL)
	out.append(0.5)
	return out
