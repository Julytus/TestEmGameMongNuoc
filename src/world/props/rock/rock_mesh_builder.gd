class_name RockMeshBuilder
extends RefCounted
## Sinh mesh đá 3D bằng code cho StylizedRock: icosphere bị "đẽo" bằng vài mặt phẳng ngẫu nhiên → mặt lớn phẳng,
## cạnh gãy; pháp tuyến phẳng theo mặt để rock.gdshader chia bậc sáng rõ như pixel art vẽ tay.
## Đáy cắt phẳng, chìm nhẹ xuống đất. COLOR.r = AO (chân đá tối hơn), CUSTOM0.rgb = pháp tuyến mượt. Cache theo (variant, seed).

enum Variant { BOULDER, FLAT, TALL, CLUSTER }

const MATERIAL := preload("res://src/world/props/rock/rock_material.tres")

static var _cache: Dictionary = {}


static func get_mesh(variant: Variant, seed_value: int = 0) -> ArrayMesh:
	var key := Vector2i(variant, seed_value)
	if not _cache.has(key):
		_cache[key] = build(variant, seed_value)
	return _cache[key]


## (bán kính, chiều cao) va chạm của khối chính.
static func collision_size(variant: Variant) -> Vector2:
	match variant:
		Variant.FLAT:
			return Vector2(0.75, 0.5)
		Variant.TALL:
			return Vector2(0.4, 1.5)
		Variant.CLUSTER:
			return Vector2(0.75, 0.9)
	return Vector2(0.6, 0.9)


## Bán kính phần đá chạm đất (m, chưa scale) – vùng cỏ không được mọc để khỏi xuyên qua mặt đá.
static func footprint_radius(variant: Variant) -> float:
	match variant:
		Variant.FLAT:
			return 0.8
		Variant.TALL:
			return 0.45
		Variant.CLUSTER:
			return 0.95
	return 0.65


static func build(variant: Variant, seed_value: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(variant + 100, seed_value))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)
	match variant:
		Variant.BOULDER:
			_add_stone(st, rng, Vector3.ZERO, Vector3(0.7, 0.55, 0.6))
			_add_stone(st, rng, Vector3(0.75, 0.0, 0.35), Vector3(0.16, 0.12, 0.14))
		Variant.FLAT:
			_add_stone(st, rng, Vector3.ZERO, Vector3(0.9, 0.32, 0.7))
			_add_stone(st, rng, Vector3(-0.95, 0.0, 0.3), Vector3(0.14, 0.1, 0.12))
		Variant.TALL:
			_add_stone(st, rng, Vector3.ZERO, Vector3(0.45, 1.0, 0.4))
			_add_stone(st, rng, Vector3(0.5, 0.0, 0.3), Vector3(0.2, 0.16, 0.18))
		Variant.CLUSTER:
			_add_stone(st, rng, Vector3(-0.2, 0.0, 0.0), Vector3(0.62, 0.55, 0.55))
			_add_stone(st, rng, Vector3(0.6, 0.0, 0.3), Vector3(0.36, 0.3, 0.33))
			_add_stone(st, rng, Vector3(0.15, 0.0, -0.55), Vector3(0.26, 0.2, 0.24))
	var mesh := st.commit()
	mesh.surface_set_material(0, MATERIAL)
	return mesh


static func _add_stone(st: SurfaceTool, rng: RandomNumberGenerator, base: Vector3, size: Vector3) -> void:
	var sphere := _icosphere(1)
	var verts: PackedVector3Array = sphere[0]
	var faces: PackedInt32Array = sphere[1]
	# Nhát đẽo: mặt phẳng ngẫu nhiên (thiên về hướng ngang/lên) cắt phẳng phần lồi
	var cuts: Array[Vector4] = []
	for i in rng.randi_range(6, 9):
		var d := Vector3(rng.randfn(), rng.randfn() * 0.6 + 0.35, rng.randfn()).normalized()
		cuts.append(Vector4(d.x, d.y, d.z, rng.randf_range(0.7, 0.9)))
	var yaw := rng.randf() * TAU
	var lean := Vector3(rng.randf_range(-0.1, 0.1), 0.0, rng.randf_range(-0.1, 0.1))
	for i in verts.size():
		var u := verts[i] * rng.randf_range(0.95, 1.05)
		for c in cuts:
			var n := Vector3(c.x, c.y, c.z)
			var excess := u.dot(n) - c.w
			if excess > 0.0:
				u -= n * excess
		var p := u * size
		p.y = p.y * (0.9 if p.y > 0.0 else 1.15) + size.y * 0.7
		p += lean * p.y
		p = p.rotated(Vector3.UP, yaw)
		p.y = maxf(p.y, -0.06)
		verts[i] = base + p
	var center := base + Vector3(0.0, size.y * 0.6, 0.0)
	var top := size.y * 1.6
	for f in range(0, faces.size(), 3):
		var a := verts[faces[f]]
		var b := verts[faces[f + 1]]
		var c := verts[faces[f + 2]]
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-10:
			continue  # tam giác suy biến do bị cắt dồn lên cùng mặt phẳng
		n = n.normalized()
		if n.y < -0.9:
			continue  # đáy nằm trong đất
		for p: Vector3 in [a, b, c]:
			# CUSTOM0 = pháp tuyến mượt (từ tâm khối) cho viền inverted hull không bị hở ở cạnh
			var smooth := ((p - center) / size).normalized()
			st.set_custom(0, Color(smooth.x, smooth.y, smooth.z))
			st.set_normal(n)
			st.set_color(Color(lerpf(0.6, 1.0, clampf((p.y + 0.06) / top, 0.0, 1.0)), 0.0, 0.0, 1.0))
			st.add_vertex(p)


## Icosphere đơn vị (thứ tự đỉnh CW cho Godot): [đỉnh, chỉ số tam giác].
static func _icosphere(subdiv: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	])
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	for s in subdiv:
		var cache: Dictionary = {}
		var next := PackedInt32Array()
		for f in range(0, faces.size(), 3):
			var a := faces[f]
			var b := faces[f + 1]
			var c := faces[f + 2]
			var ab := _midpoint(verts, cache, a, b)
			var bc := _midpoint(verts, cache, b, c)
			var ca := _midpoint(verts, cache, c, a)
			next.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		faces = next
	for f in range(0, faces.size(), 3):
		var tmp := faces[f + 1]
		faces[f + 1] = faces[f + 2]
		faces[f + 2] = tmp
	return [verts, faces]


static func _midpoint(verts: PackedVector3Array, cache: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	cache[key] = verts.size() - 1
	return verts.size() - 1
