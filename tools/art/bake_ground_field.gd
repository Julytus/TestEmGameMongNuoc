extends SceneTree
## Bake "ground field" cho mặt đất — bake-first, thay noise thủ tục cũ trong shader (terrain_noise.gdshaderinc).
##
## Chạy (sau khi sửa ảnh layout của level nào đó):
##   <godot> --headless --path . --script res://tools/art/bake_ground_field.gd
##   <godot> --headless --path . --import
## Lần đầu cho một level mới: PNG chưa được import nên chưa gán được vào .tres → chạy --import rồi chạy lại tool.
##
## Quét src/world/levels/*/*_layout.tres; mỗi layout ghi `<level>_ground.png` cạnh nó (L8, WaterField.PIXELS_PER_METER
## px/m, phủ đúng vùng layout, tâm pixel = tâm texel shader đọc):
##   giá trị = clamp(layout.r nội suy + (value_noise(p·2) − 0,5) · EDGE_WOBBLE · 2, 0, 1)
## Ngưỡng shader nằm trong 0,4..0,9 nên kẹp [0, 1] không mất gì. Deterministic: chạy lại ra file giống hệt.
## .import đi kèm: lossless, không mipmap, không tự nén VRAM khi dùng trong 3D (detect_3d/compress_to=0).

const LEVELS_DIR := "res://src/world/levels"
const IMPORT_TEMPLATE := """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
mipmaps/generate=false
process/fix_alpha_border=false
detect_3d/compress_to=0
"""


func _initialize() -> void:
	var failed := false
	for dir_name in DirAccess.get_directories_at(LEVELS_DIR):
		var dir := LEVELS_DIR.path_join(dir_name)
		for file in DirAccess.get_files_at(dir):
			if file.ends_with("_layout.tres"):
				failed = not _bake(dir.path_join(file)) or failed
	quit(1 if failed else 0)


func _bake(layout_path: String) -> bool:
	var layout := load(layout_path) as TerrainLayout
	if layout == null or layout.get_image() == null:
		push_error("[bake_ground_field] không đọc được %s" % layout_path)
		return false
	var t0 := Time.get_ticks_msec()
	var ppm := float(WaterField.PIXELS_PER_METER)
	var world := layout.get_world_size()
	var w := roundi(world.x * ppm)
	var h := roundi(world.y * ppm)
	var origin := -world * 0.5
	var data := PackedByteArray()
	data.resize(w * h)
	for y in h:
		var wz := origin.y + (y + 0.5) / ppm
		for x in w:
			var wx := origin.x + (x + 0.5) / ppm
			var v := layout.sample(Vector2(wx, wz)).r
			v += (WaterField.value_noise(wx * 2.0, wz * 2.0) - 0.5) * WaterField.EDGE_WOBBLE * 2.0
			data[y * w + x] = roundi(clampf(v, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_L8, data)
	var png_path := layout_path.trim_suffix("_layout.tres") + "_ground.png"
	var err := img.save_png(png_path)
	if err != OK:
		push_error("[bake_ground_field] ghi %s lỗi %s" % [png_path, error_string(err)])
		return false
	if not FileAccess.file_exists(png_path + ".import"):
		var f := FileAccess.open(png_path + ".import", FileAccess.WRITE)
		f.store_string(IMPORT_TEMPLATE)
		f.close()
	print("[bake_ground_field] %s → %dx%d px, %d ms" % [png_path, w, h, Time.get_ticks_msec() - t0])

	if layout.ground_field != null and layout.ground_field.resource_path == png_path:
		return true
	# ResourceLoader.exists() đúng ngay khi có .import (chưa import thật) → kiểm dòng dest_files Godot ghi lúc import.
	if not FileAccess.get_file_as_string(png_path + ".import").contains("dest_files="):
		print("[bake_ground_field] %s chưa import → chạy --import rồi chạy lại tool để gán vào %s" % [
			png_path, layout_path])
		return true
	layout.ground_field = load(png_path) as Texture2D
	err = ResourceSaver.save(layout, layout_path)
	if err != OK:
		push_error("[bake_ground_field] lưu %s lỗi %s" % [layout_path, error_string(err)])
		return false
	print("[bake_ground_field] gán ground_field vào %s" % layout_path)
	return true
