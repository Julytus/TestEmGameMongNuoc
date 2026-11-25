@tool
class_name BlockGrid
extends GridMap
## GridMap block đất/cỏ/đá tự nối liền: mỗi ô chọn biến thể mesh theo 6 ô kề (cạnh giáp khối khác thì không bo,
## mặt bị che thì bỏ) → khối đặt sát nhau không lộ rãnh. Biến thể bake sẵn trong blocks_library.tres
## (tools/art/build_block_library.gd), ở đây chỉ đổi chỉ số item — không dựng mesh lúc chạy.
##
## Item id = mask * TYPE_COUNT + loại (0 Grass, 1 Dirt, 2 Stone) → item 0..2 là khối rời; vẽ bằng 3 item đầu,
## script tự sửa id. Trong editor: dò thay đổi mỗi EDITOR_POLL giây (GridMap không có signal đổi ô).

const TYPE_COUNT := 3
## Bit i của mask = có khối ở ô cell + NEIGHBORS[i]. Thứ tự phải khớp build_block_library.gd.
const NEIGHBORS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const VARIANT_COUNT := 64 ## 2^NEIGHBORS.size()
const EDITOR_POLL := 0.2

var _poll_left := 0.0
var _last_hash := 0


func _ready() -> void:
	retile()
	set_process(Engine.is_editor_hint())


func _process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = EDITOR_POLL
	var h := _cells_hash()
	if h != _last_hash:
		retile()


## Gán lại biến thể cho mọi ô theo hàng xóm; chỉ ghi ô có id thay đổi. Trả về số ô đã đổi.
func retile() -> int:
	var cells := get_used_cells()
	var occupied := {}
	for c in cells:
		occupied[c] = true
	var changed := 0
	for c in cells:
		var item := get_cell_item(c)
		var mask := 0
		for i in NEIGHBORS.size():
			if occupied.has(c + NEIGHBORS[i]):
				mask |= 1 << i
		var want := mask * TYPE_COUNT + item % TYPE_COUNT
		if want != item or get_cell_item_orientation(c) != 0:
			set_cell_item(c, want, 0)
			changed += 1
	_last_hash = _cells_hash()
	return changed


func _cells_hash() -> int:
	var h := 0
	for c in get_used_cells():
		h = hash([h, c, get_cell_item(c)])
	return h
