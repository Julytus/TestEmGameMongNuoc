@tool
class_name WaterField
extends RefCounted
## "Water field" 16 px/m dựng một lần từ ảnh layout (kênh B), dùng chung cho mặt đất và mặt nước:
##   R = khoảng cách có dấu (m) từ tâm pixel tới mép nước (> 0 trong nước, < 0 ngoài) – đã gồm độ lượn mép
##   G = khoảng cách (m) tới bờ theo hướng -Z (bờ xa camera), chặn FAR_CAP; 0 ngoài nước
## terrain_ground.gdshader và water.gdshader cùng đọc texel này qua water_field_at() → mép khớp tuyệt đối.
## TerrainLayout cache field và gán vào material (apply_to_material). build() chỉ dùng Image + số (không SceneTree)
## để sau này chuyển sang WorkerThreadPool / bake theo chunk được.

## Phải khớp pixels_per_meter trong terrain_common.gdshaderinc (README: 16 px = 1 m).
const PIXELS_PER_METER := 16
## Độ lượn mép (biên độ quanh ngưỡng 0.5), = edge_wobble cũ của shader.
const EDGE_WOBBLE := 0.12
## Chặn khoảng cách bờ xa (m), = max_dist của shore_probe cũ.
const FAR_CAP := 0.6
## Số ô đất bao quanh vùng nước (= grow(1) cũ của TerrainWater).
const MARGIN_CELLS := 1
const _BIG := 1e6
const _DIAG := 1.41421

var texture: ImageTexture
## Vùng phủ (thế giới XZ, m). size = 0 → không có nước.
var rect: Rect2


func has_water() -> bool:
	return texture != null


## Giá trị cho uniform water_field_rect: xy = góc, zw = kích thước (m).
func rect_uniform() -> Vector4:
	return Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)


static func build(img: Image, cell_size: float) -> WaterField:
	var field := WaterField.new()
	if img == null:
		return field
	var t0 := Time.get_ticks_usec()
	var iw := img.get_width()
	var ih := img.get_height()
	# 1. Kênh B mọi ô + khung bao ô nước.
	var cellb := PackedFloat32Array()
	cellb.resize(iw * ih)
	var bounds := Rect2i()
	var found := false
	for cy in ih:
		for cx in iw:
			var c := img.get_pixel(cx, cy)
			cellb[cy * iw + cx] = c.b
			if TerrainLayout.matches_mask(c, TerrainLayout.FLAG_WATER):
				var cell := Rect2i(cx, cy, 1, 1)
				bounds = cell if not found else bounds.merge(cell)
				found = true
	if not found:
		return field
	bounds = bounds.grow(MARGIN_CELLS)

	# 2. Gốc (snap lưới 1/16 m) + kích thước pixel.
	var ppm := float(PIXELS_PER_METER)
	var origin := (Vector2(bounds.position) - Vector2(iw, ih) * 0.5) * cell_size
	origin = (origin * ppm).floor() / ppm
	var w := ceili(bounds.size.x * cell_size * ppm)
	var h := ceili(bounds.size.y * cell_size * ppm)
	if w * h > 256 * 256:
		push_warning("[WaterField] field lớn %dx%d — chia chunk/bake (roadmap 'Đi trên nước & biển')" % [w, h])

	# Mảng có viền đệm 1 pixel (pad = _BIG) → vòng chamfer không cần rẽ nhánh biên.
	var pw := w + 2
	var water := PackedByteArray()
	water.resize(pw * (h + 2))
	var dist := PackedFloat32Array()
	dist.resize(pw * (h + 2))
	dist.fill(_BIG)
	var data := PackedFloat32Array()
	data.resize(w * h * 2)

	# Hệ số nội suy theo cột (giống TerrainLayout.sample: tâm ô, kẹp biên).
	var col_x0 := PackedInt32Array()
	var col_x1 := PackedInt32Array()
	var col_t := PackedFloat32Array()
	col_x0.resize(w)
	col_x1.resize(w)
	col_t.resize(w)
	for x in w:
		var fx := (origin.x + (x + 0.5) / ppm) / cell_size + iw * 0.5 - 0.5
		var fl := floorf(fx)
		col_x0[x] = clampi(int(fl), 0, iw - 1)
		col_x1[x] = clampi(int(fl) + 1, 0, iw - 1)
		col_t[x] = fx - fl
	var row := PackedFloat32Array()
	row.resize(iw)
	var runs := PackedInt32Array()
	runs.resize(w)
	var low := 0.5 - EDGE_WOBBLE
	var high := 0.5 + EDGE_WOBBLE

	# 3. Mặt nạ (+ lượn mép ở dải gần ngưỡng) + gieo khoảng cách ở pixel sát lớp kia + G (quét -Z → +Z).
	for y in h:
		var wz := origin.y + (y + 0.5) / ppm
		var fy := wz / cell_size + ih * 0.5 - 0.5
		var fly := floorf(fy)
		var y0 := clampi(int(fly), 0, ih - 1) * iw
		var y1 := clampi(int(fly) + 1, 0, ih - 1) * iw
		var ty := fy - fly
		for cx in iw:
			row[cx] = lerpf(cellb[y0 + cx], cellb[y1 + cx], ty)
		var pi := (y + 1) * pw + 1
		for x in w:
			var b := lerpf(row[col_x0[x]], row[col_x1[x]], col_t[x])
			if b > low and b < high:
				var wx := origin.x + (x + 0.5) / ppm
				b += (_noise(wx * 2.0 + 17.3, wz * 2.0 + 17.3) - 0.5) * EDGE_WOBBLE * 2.0
			var wv := 1 if b > 0.5 else 0
			var i := pi + x
			water[i] = wv
			# So với 4 lân cận đã tính (trái, trên-trái, trên, trên-phải); khác lớp → cả hai cách lớp kia 1 / √2.
			if x > 0 and water[i - 1] != wv:
				dist[i] = 1.0
				dist[i - 1] = 1.0
			if y > 0:
				var u := i - pw
				if water[u] != wv:
					dist[i] = 1.0
					dist[u] = 1.0
				if x > 0 and water[u - 1] != wv:
					dist[i] = minf(dist[i], _DIAG)
					dist[u - 1] = minf(dist[u - 1], _DIAG)
				if x < w - 1 and water[u + 1] != wv:
					dist[i] = minf(dist[i], _DIAG)
					dist[u + 1] = minf(dist[u + 1], _DIAG)
			var o := (y * w + x) * 2
			if wv == 1:
				runs[x] += 1
				data[o + 1] = minf((runs[x] - 0.5) / ppm, FAR_CAP)
			else:
				runs[x] = 0
	var t_mask := Time.get_ticks_usec()

	# 4. Chamfer 2 lượt trên MỘT mảng: khoảng cách tới pixel khác lớp (trong nước → tới đất, ngoài → tới nước).
	# Pixel sát biên đã gieo ≤ √2 nên không bao giờ nhận giá trị lan từ lớp kia.
	for y in h:
		var i := (y + 1) * pw + 1
		for x in w:
			var d := dist[i]
			d = minf(d, dist[i - 1] + 1.0)
			d = minf(d, dist[i - pw] + 1.0)
			d = minf(d, dist[i - pw - 1] + _DIAG)
			d = minf(d, dist[i - pw + 1] + _DIAG)
			dist[i] = d
			i += 1
	for y in range(h - 1, -1, -1):
		var i := (y + 1) * pw + w
		var o := (y * w + w - 1) * 2
		for x in w:
			var d := dist[i]
			d = minf(d, dist[i + 1] + 1.0)
			d = minf(d, dist[i + pw] + 1.0)
			d = minf(d, dist[i + pw + 1] + _DIAG)
			d = minf(d, dist[i + pw - 1] + _DIAG)
			dist[i] = d
			# 5. R có dấu (m) từ tâm pixel tới mép.
			data[o] = (d - 0.5) / ppm if water[i] == 1 else -(d - 0.5) / ppm
			i -= 1
			o -= 2
	var t_dist := Time.get_ticks_usec()

	# 6. Ghép texture RGF.
	var fimg := Image.create_from_data(w, h, false, Image.FORMAT_RGF, data.to_byte_array())
	field.texture = ImageTexture.create_from_image(fimg)
	field.rect = Rect2(origin, Vector2(w, h) / ppm)
	var t_end := Time.get_ticks_usec()
	print("[WaterField] %dx%d px (%.0fx%.0f m), %.1f ms (mask %.1f, dist %.1f, tex %.1f)" % [
		w, h, field.rect.size.x, field.rect.size.y, (t_end - t0) / 1000.0,
		(t_mask - t0) / 1000.0, (t_dist - t_mask) / 1000.0, (t_end - t_dist) / 1000.0])
	return field


## Value noise CPU (hash số nguyên, deterministic) – cùng tần số với terrain_noise cũ, giá trị khác.
static func _noise(px: float, py: float) -> float:
	var fx := floorf(px)
	var fy := floorf(py)
	var ix := int(fx)
	var iy := int(fy)
	var tx := px - fx
	var ty := py - fy
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	return lerpf(lerpf(_hash(ix, iy), _hash(ix + 1, iy), tx), lerpf(_hash(ix, iy + 1), _hash(ix + 1, iy + 1), tx), ty)


static func _hash(x: int, y: int) -> float:
	var h: int = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0
