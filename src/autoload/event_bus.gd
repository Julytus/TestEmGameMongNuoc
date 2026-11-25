extends Node
## Trạm signal toàn cục cho các sự kiện XUYÊN hệ thống (gameplay ↔ UI ↔ audio ↔ save).
##
## Quy tắc: trong cùng một scene, ưu tiên signal trực tiếp giữa các node.
## Chỉ đưa signal lên đây khi bên phát và bên nhận không biết nhau
## (ví dụ: Player phát máu → HUD hiển thị).

@warning_ignore_start("unused_signal")

# --- Player ---
signal player_health_changed(current: int, max_health: int)
signal player_died

# --- World / Story ---
signal area_entered(area_name: String)
signal dialogue_requested(dialogue_id: StringName)

# --- Boss ---
signal boss_engaged(boss_name: String, max_health: int)
signal boss_health_changed(current: int, max_health: int)
signal boss_defeated(boss_name: String)

# --- Camera / Feel ---
signal camera_shake_requested(strength: float)

# --- UI ---
signal toast_requested(text: String)

# --- Save ---
signal game_saved(slot: int)
signal game_loaded(slot: int)

# --- Dev / Bench ---
## Bench vừa dời người chơi tới một BenchPoint, TRƯỚC khởi động — stress (Mốc 2/3) spawn kẻ địch/skill ở đây
## để chúng được khởi động cùng điểm đo.
signal bench_point_entered(id: StringName)

@warning_ignore_restore("unused_signal")
