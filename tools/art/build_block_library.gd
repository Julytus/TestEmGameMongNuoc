extends SceneTree
## Dựng MeshLibrary cho block 1 m (cỏ / đất / đá) từ atlas do gen_blocks.py sinh — bake-first, không dựng lúc chạy.
##
## Chạy (sau `python tools/art/gen_blocks.py` + import):
##   <godot> --headless --path . --script res://tools/art/build_block_library.gd
## Ghi đè: res://src/world/blocks/blocks_library.tres
##
## Item: 0 Grass, 1 Dirt, 2 Stone. Mesh hộp 24 đỉnh, gốc ở ĐÁY-giữa (x,z ∈ [-0,5; 0,5], y ∈ [0; 1]) →
## GridMap dùng cell_size = 1 và cell_center_y = false để đáy khối nằm đúng mặt lưới.
## Sub-resource có id cố định (resource_scene_unique_id) để chạy lại không đổi file (git diff sạch).

const ATLAS_TILES := 4.0 ## khớp TILES trong gen_blocks.py: 0 grass_top, 1 grass_side, 2 dirt, 3 stone
const TILE_GRASS_TOP := 0
const TILE_GRASS_SIDE := 1
const TILE_DIRT := 2
const TILE_STONE := 3
## Thu UV vào trong ô một chút để lọc nearest không lấy nhầm texel ô bên cạnh ở mép mặt.
const UV_INSET := 0.001
const MATERIAL_PATH := "res://src/world/blocks/block_material.tres"
const OUT_PATH := "res://src/world/blocks/blocks_library.tres"

## name -> [top, side, bottom] (chỉ số ô atlas)
const BLOCKS: Array[Array] = [
	[&"Grass", TILE_GRASS_TOP, TILE_GRASS_SIDE, TILE_DIRT],
	[&"Dirt", TILE_DIRT, TILE_DIRT, TILE_DIRT],
	[&"Stone", TILE_STONE, TILE_STONE, TILE_STONE],
]


func _initialize() -> void:
	var material := load(MATERIAL_PATH) as Material
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	shape.resource_scene_unique_id = "BlockShape"
	var shape_xform := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0))
	var library := MeshLibrary.new()
	for id in BLOCKS.size():
		var spec: Array = BLOCKS[id]
		var mesh := _build_box(spec[1], spec[2], spec[3], material)
		mesh.resource_scene_unique_id = "Mesh_%s" % spec[0]
		library.create_item(id)
		library.set_item_name(id, String(spec[0]))
		library.set_item_mesh(id, mesh)
		library.set_item_shapes(id, [shape, shape_xform])
	var err := ResourceSaver.save(library, OUT_PATH)
	print("[build_block_library] %s -> %s" % [error_string(err), OUT_PATH])
	quit(0 if err == OK else 1)


func _build_box(top: int, side: int, bottom: int, material: Material) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Mỗi mặt: pháp tuyến, trục u (trái→phải khi nhìn từ ngoài), trục v (trên→dưới), ô atlas.
	# Mặt cạnh: v hướng -Y để viền cỏ nằm ở trên.
	_face(verts, normals, uvs, indices, Vector3.UP, Vector3.RIGHT, Vector3.BACK, top)
	_face(verts, normals, uvs, indices, Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD, bottom)
	_face(verts, normals, uvs, indices, Vector3.BACK, Vector3.RIGHT, Vector3.DOWN, side)
	_face(verts, normals, uvs, indices, Vector3.FORWARD, Vector3.LEFT, Vector3.DOWN, side)
	_face(verts, normals, uvs, indices, Vector3.RIGHT, Vector3.FORWARD, Vector3.DOWN, side)
	_face(verts, normals, uvs, indices, Vector3.LEFT, Vector3.BACK, Vector3.DOWN, side)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


## Thêm một mặt vuông 1×1 của hộp đáy-giữa. u, v: trục texture trên mặt (nhìn từ ngoài).
func _face(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, n: Vector3, u: Vector3, v: Vector3, tile: int) -> void:
	var center := Vector3(0.0, 0.5, 0.0) + n * 0.5
	var base := verts.size()
	var u0 := tile / ATLAS_TILES + UV_INSET
	var u1 := (tile + 1) / ATLAS_TILES - UV_INSET
	var corners: Array[Vector2] = [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
	for c in corners:
		verts.append(center + u * c.x + v * c.y)
		normals.append(n)
		uvs.append(Vector2(lerpf(u0, u1, c.x + 0.5), lerpf(UV_INSET, 1.0 - UV_INSET, c.y + 0.5)))
	# Godot: mặt trước theo chiều kim đồng hồ khi nhìn từ phía pháp tuyến.
	if u.cross(v).dot(n) > 0.0:
		indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
