class_name TreeMeshBuilder
extends RefCounted
## Sinh mesh cây 3D stylized (kiểu HD-2D) bằng code:
##  - Surface 0: thân + cành (trụ thon nhiều cạnh, bark_material)
##  - Surface 1: tán lá = hàng trăm "thẻ lá" (quad) gom thành các khối cầu / tầng nón.
##    Mỗi thẻ lưu tâm ở VERTEX, góc ở UV2; foliage_leaves.gdshader xoay thẻ về camera (billboard),
##    pháp tuyến hướng ra ngoài khối tán → ánh sáng tròn khối như cây 3D thật.
## Mesh được cache theo (variant, seed) nên trăm cây trong MultiMesh dùng chung vài mesh.
## get_shadow_proxy(): khối low-poly (ellipsoid mỗi cụm tán, nón mỗi tầng thông, trụ thân) dựng từ chính các khối
## lúc build → dùng làm bóng rẻ (SHADOWS_ONLY) thay hàng trăm thẻ lá trong shadow pass.
## (Dựng lúc chạy, cache – ngoại lệ bake-first tạm cho tới mục roadmap "Cây bake sẵn".)

enum Variant { OAK, WIDE_OAK, PINE, BUSH }

const BARK_MATERIAL := preload("res://src/world/props/tree/bark_material.tres")
const LEAF_MATERIAL := preload("res://src/world/props/tree/leaves_material.tres")
const PINE_MATERIAL := preload("res://src/world/props/tree/pine_leaves_material.tres")
const ATLAS_COLUMNS := 4
const ATLAS_ROWS := 2
## Proxy bóng: hệ số bán kính tán (1,0: cỡ bóng dưới đất khớp thẻ lá nhất, không thấy tán tự tối – so ảnh Mốc 1) và số cạnh.
const PROXY_CANOPY_SCALE := 1.0
const PROXY_SIDES := 8
const PROXY_RINGS := 4

enum _Shape { ELLIPSOID, CONE, LIMB }

static var _cache: Dictionary = {}
static var _proxy_cache: Dictionary = {}
## Khối dựng của từng (variant, seed) – ghi lại lúc build() để dựng proxy bóng.
static var _shapes: Dictionary = {}
static var _recording: Array[Array] = []
static var _proxy_material: StandardMaterial3D


static func get_mesh(variant: Variant, seed_value: int = 0) -> ArrayMesh:
	var key := Vector2i(variant, seed_value)
	if not _cache.has(key):
		_cache[key] = build(variant, seed_value)
	return _cache[key]


static func get_shadow_proxy(variant: Variant, seed_value: int = 0) -> ArrayMesh:
	var key := Vector2i(variant, seed_value)
	if not _proxy_cache.has(key):
		get_mesh(variant, seed_value) # build() ghi khối vào _shapes
		_proxy_cache[key] = _build_proxy(_shapes[key])
	return _proxy_cache[key]


static func build(variant: Variant, seed_value: int = 0) -> ArrayMesh:
	_recording = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(variant, seed_value))
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf_material: Material = LEAF_MATERIAL
	var has_trunk := true
	match variant:
		Variant.OAK:
			_build_oak(trunk, leaves, rng, 1.0, 4, 1.15)
		Variant.WIDE_OAK:
			_build_oak(trunk, leaves, rng, 1.45, 5, 0.95)
		Variant.PINE:
			_build_pine(trunk, leaves, rng)
			leaf_material = PINE_MATERIAL
		Variant.BUSH:
			_build_bush(leaves, rng)
			has_trunk = false
	var mesh := ArrayMesh.new()
	if has_trunk:
		trunk.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, BARK_MATERIAL)
	leaves.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, leaf_material)
	_shapes[Vector2i(variant, seed_value)] = _recording
	return mesh


# ---------------------------------------------------------------- Các loài cây

static func _build_oak(trunk: SurfaceTool, leaves: SurfaceTool, rng: RandomNumberGenerator,
		spread: float, branch_count: int, height_scale: float) -> void:
	var lean := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
	var mid := Vector3(0.0, 1.9 * height_scale, 0.0) + lean
	var top := Vector3(0.0, 2.9 * height_scale, 0.0) + lean * 1.4
	_add_limb(trunk, Vector3.ZERO, mid, 0.26, 0.16, 7)
	_add_limb(trunk, mid, top, 0.16, 0.1, 6)
	var canopy_center := Vector3(0.0, 3.2 * height_scale, 0.0) + lean
	_add_cluster(leaves, rng, canopy_center + Vector3(0.0, 0.2, 0.0), 1.35 * lerpf(1.0, spread, 0.5),
			int(62 * spread), canopy_center, Vector2(0.85, 1.2), 0)
	var angle0 := rng.randf() * TAU
	for i in branch_count:
		var a := angle0 + TAU * i / branch_count + rng.randf_range(-0.3, 0.3)
		var start := Vector3(0.0, rng.randf_range(1.5, 2.3) * height_scale, 0.0) + lean
		var dir := Vector3(cos(a), rng.randf_range(0.45, 0.8), sin(a)).normalized()
		var end := start + dir * rng.randf_range(1.0, 1.3) * spread
		_add_limb(trunk, start, end, 0.09, 0.045, 5)
		_add_cluster(leaves, rng, end + Vector3(0.0, 0.35, 0.0), rng.randf_range(0.85, 1.05),
				rng.randi_range(30, 38), canopy_center, Vector2(0.75, 1.05), 0)
	_add_cluster(leaves, rng, canopy_center + Vector3(rng.randf_range(-0.3, 0.3), 1.15, 0.0), 0.9, 28,
			canopy_center, Vector2(0.75, 1.0), 0)


static func _build_pine(trunk: SurfaceTool, leaves: SurfaceTool, rng: RandomNumberGenerator) -> void:
	_add_limb(trunk, Vector3.ZERO, Vector3(0.0, 5.4, 0.0), 0.2, 0.05, 6)
	const TIERS := 6
	for k in TIERS:
		var t := float(k) / (TIERS - 1)
		var y := 1.5 + t * 3.8
		var radius := lerpf(1.8, 0.45, t)
		var count := int(22 + radius * 30)
		# Tầng thông: thẻ rủ xuống tới ~0,85 m ở mép → nón từ đáy rủ tới trên tâm tầng một chút
		_recording.append([_Shape.CONE, Vector3(0.0, y - 0.6, 0.0), radius, 0.95])
		for i in count:
			var a := rng.randf() * TAU
			# Phần lớn thẻ nằm ở vỏ ngoài tầng (đọc rõ hình tầng); 1/4 nằm sát thân để che thân
			var r := radius * (sqrt(rng.randf_range(0.0, 0.3)) if i % 4 == 0 else sqrt(rng.randf_range(0.45, 1.0)))
			var radial := Vector3(cos(a), 0.0, sin(a))
			var droop := pow(r / radius, 1.5) * 0.85
			var pos := radial * r + Vector3(0.0, y - droop + rng.randf_range(-0.12, 0.12), 0.0)
			var normal := (radial * 0.75 + Vector3.UP * 0.65).normalized()
			# Mép dưới mỗi tầng tối hơn → các tầng thông tách lớp rõ
			var under := clampf((y - pos.y) / 0.6, 0.0, 1.0)
			var ao := lerpf(0.7, 1.05, r / radius) * lerpf(0.9, 1.05, t) * lerpf(1.0, 0.62, under)
			_add_card(leaves, rng, pos, normal, rng.randf_range(0.75, 1.05), ao, 1)
	_add_cluster(leaves, rng, Vector3(0.0, 5.5, 0.0), 0.35, 12, Vector3(0.0, 5.0, 0.0), Vector2(0.55, 0.75), 1)


static func _build_bush(leaves: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var center := Vector3(0.0, 0.45, 0.0)
	_add_cluster(leaves, rng, Vector3(0.0, 0.6, 0.0), 0.75, 42, center, Vector2(0.7, 0.95), 0)
	for i in 3:
		var a := TAU * i / 3.0 + rng.randf()
		_add_cluster(leaves, rng, Vector3(cos(a) * 0.6, 0.42, sin(a) * 0.6), 0.55, 22, center,
				Vector2(0.6, 0.85), 0)


# ---------------------------------------------------------------- Khối dựng

## Khối cầu thẻ lá: điểm rải gần bề mặt cầu, pháp tuyến trộn giữa hướng ra của cụm và của cả tán.
static func _add_cluster(st: SurfaceTool, rng: RandomNumberGenerator, center: Vector3, radius: float,
		count: int, canopy_center: Vector3, size_range: Vector2, atlas_row: int) -> void:
	_recording.append([_Shape.ELLIPSOID, center, radius])
	for i in count:
		var dir := Vector3(rng.randfn(), rng.randfn() * 0.85, rng.randfn()).normalized()
		var depth := sqrt(rng.randf_range(0.3, 1.0))
		var pos := center + dir * radius * depth
		var normal := (dir + (pos - canopy_center).normalized()).normalized()
		# AO: lá bên trong và phía dưới tối hơn
		var ao := clampf(lerpf(0.6, 1.0, depth) * lerpf(0.8, 1.05, normal.y * 0.5 + 0.5), 0.45, 1.0)
		_add_card(st, rng, pos, normal, rng.randf_range(size_range.x, size_range.y), ao, atlas_row)


## Một thẻ lá: 2 tam giác, cả 4 đỉnh cùng tâm (VERTEX); UV2 = độ dời góc trong không gian màn hình.
## COLOR.r = AO, COLOR.g = biến thể màu ngẫu nhiên.
static func _add_card(st: SurfaceTool, rng: RandomNumberGenerator, center: Vector3, normal: Vector3,
		size: float, ao: float, atlas_row: int) -> void:
	var column := rng.randi() % ATLAS_COLUMNS
	var cell := Vector2(1.0 / ATLAS_COLUMNS, 1.0 / ATLAS_ROWS)
	var uv0 := Vector2(column, atlas_row) * cell
	var rot := rng.randf_range(-0.6, 0.6)
	var color := Color(ao, rng.randf(), 0.0, 1.0)
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for c in corners:
		st.set_normal(normal)
		st.set_color(color)
		st.set_uv(uv0 + Vector2(c.x * 0.5 + 0.5, 0.5 - c.y * 0.5) * cell)
		st.set_uv2((c * 0.5 * size).rotated(rot))
		st.add_vertex(center)


## Trụ thon từ a → b (thân/cành), UV: u quanh trụ, v theo chiều dài (m).
static func _add_limb(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides: int) -> void:
	_recording.append([_Shape.LIMB, a, b, r0, r1])
	var axis := (b - a).normalized()
	var side_ref := Vector3.FORWARD if absf(axis.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var u := axis.cross(side_ref).normalized()
	var v := axis.cross(u).normalized()
	var length := a.distance_to(b)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var n0 := u * cos(a0) + v * sin(a0)
		var n1 := u * cos(a1) + v * sin(a1)
		var quad: Array = [
			[a + n0 * r0, n0, Vector2(float(i) / sides, 0.0), 0.6],
			[b + n0 * r1, n0, Vector2(float(i) / sides, length * 0.5), 1.0],
			[b + n1 * r1, n1, Vector2(float(i + 1) / sides, length * 0.5), 1.0],
			[a + n1 * r0, n1, Vector2(float(i + 1) / sides, 0.0), 0.6],
		]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			var q: Array = quad[idx]
			st.set_normal(q[1])
			st.set_uv(q[2])
			var shade: float = q[3]
			st.set_color(Color(shade, shade, shade, 1.0))
			st.add_vertex(q[0])


# ---------------------------------------------------------------- Proxy bóng

static func _build_proxy(shapes: Array[Array]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for shape in shapes:
		match shape[0] as _Shape:
			_Shape.ELLIPSOID:
				var r: float = shape[2] * PROXY_CANOPY_SCALE
				_proxy_ellipsoid(st, shape[1], Vector3(r, r * 0.85, r))
			_Shape.CONE:
				_proxy_cone(st, shape[1], shape[2] * PROXY_CANOPY_SCALE, shape[3])
			_Shape.LIMB:
				# Chỉ thân chính – cành nhỏ nằm trong bóng tán
				if shape[3] >= 0.15:
					_proxy_cone_frustum(st, shape[1], shape[2], shape[3], shape[4])
	var mesh := st.commit()
	if _proxy_material == null:
		# Chỉ đổ bóng (SHADOWS_ONLY) → material opaque rẻ nhất, hai mặt để không phụ thuộc chiều cuộn tam giác.
		_proxy_material = StandardMaterial3D.new()
		_proxy_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_proxy_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, _proxy_material)
	return mesh


static func _proxy_ellipsoid(st: SurfaceTool, center: Vector3, radii: Vector3) -> void:
	var rows: Array[PackedVector3Array] = []
	for ring in PROXY_RINGS + 1:
		var phi := PI * ring / PROXY_RINGS
		var row := PackedVector3Array()
		for i in PROXY_SIDES:
			var theta := TAU * i / PROXY_SIDES
			row.append(center + Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * radii)
		rows.append(row)
	for ring in PROXY_RINGS:
		for i in PROXY_SIDES:
			var j := (i + 1) % PROXY_SIDES
			_proxy_quad(st, rows[ring][i], rows[ring][j], rows[ring + 1][j], rows[ring + 1][i])


static func _proxy_cone(st: SurfaceTool, base: Vector3, radius: float, height: float) -> void:
	var apex := base + Vector3(0.0, height, 0.0)
	for i in PROXY_SIDES:
		var a := base + Vector3(cos(TAU * i / PROXY_SIDES), 0.0, sin(TAU * i / PROXY_SIDES)) * radius
		var b := base + Vector3(cos(TAU * (i + 1) / PROXY_SIDES), 0.0, sin(TAU * (i + 1) / PROXY_SIDES)) * radius
		for v: Vector3 in [apex, b, a, base, a, b]:
			st.add_vertex(v)


static func _proxy_cone_frustum(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	const SIDES := 6
	var axis := (b - a).normalized()
	var side_ref := Vector3.FORWARD if absf(axis.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var u := axis.cross(side_ref).normalized()
	var v := axis.cross(u).normalized()
	for i in SIDES:
		var n0 := u * cos(TAU * i / SIDES) + v * sin(TAU * i / SIDES)
		var n1 := u * cos(TAU * (i + 1) / SIDES) + v * sin(TAU * (i + 1) / SIDES)
		_proxy_quad(st, a + n0 * r0, a + n1 * r0, b + n1 * r1, b + n0 * r1)


static func _proxy_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		st.add_vertex(v)
