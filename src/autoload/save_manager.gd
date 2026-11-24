extends Node
## Lưu/tải game theo slot. Định dạng JSON (dễ debug, dễ diff) có trường "version" để migrate.
##
## An toàn dữ liệu: ghi ra file .tmp trước, giữ bản .bak của save cũ, rồi mới thay thế
## → mất điện/crash giữa chừng không làm hỏng save đang có.
##
## Khi đổi cấu trúc save: tăng SAVE_VERSION và thêm một bước trong _migrate().

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1
const MAX_SLOTS := 3


func get_slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(get_slot_path(slot))


func save_game(slot: int) -> Error:
	assert(slot >= 0 and slot < MAX_SLOTS, "Slot save không hợp lệ: %d" % slot)
	var dir_err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if dir_err != OK:
		push_error("Không tạo được thư mục save: %s" % error_string(dir_err))
		return dir_err

	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"game_state": GameState.to_dict(),
	}

	var path := get_slot_path(slot)
	var tmp_path := path + ".tmp"
	var bak_path := path + ".bak"

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		var open_err := FileAccess.get_open_error()
		push_error("Không ghi được save %s: %s" % [tmp_path, error_string(open_err)])
		return open_err
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		DirAccess.rename_absolute(path, bak_path)
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_error("Không hoàn tất save: %s" % error_string(err))
		return err

	print("[SaveManager] Đã lưu slot %d → %s" % [slot, ProjectSettings.globalize_path(path)])
	EventBus.game_saved.emit(slot)
	return OK


## Đọc save (đã migrate). Trả về {} nếu không có hoặc hỏng.
func read_save(slot: int) -> Dictionary:
	var path := get_slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("File save hỏng: %s" % path)
		return {}
	return _migrate(parsed)


func load_game(slot: int) -> Error:
	var data := read_save(slot)
	if data.is_empty():
		return ERR_FILE_NOT_FOUND
	var state: Variant = data.get("game_state", {})
	if not (state is Dictionary):
		return ERR_FILE_CORRUPT
	GameState.from_dict(state)
	SceneManager.change_level(GameState.current_level, GameState.spawn_id)
	print("[SaveManager] Đã tải slot %d" % slot)
	EventBus.game_loaded.emit(slot)
	return OK


func delete_save(slot: int) -> void:
	var path := get_slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Nâng cấp save cũ lên SAVE_VERSION hiện tại, từng bước một.
func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("Save được tạo bởi phiên bản game mới hơn (v%d)." % version)
		return data
	while version < SAVE_VERSION:
		match version:
			# Ví dụ khi lên v2:
			# 1:
			# 	data["game_state"]["new_field"] = default_value
			_:
				pass
		version += 1
	data["version"] = SAVE_VERSION
	return data
