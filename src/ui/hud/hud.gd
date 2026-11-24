extends CanvasLayer
## HUD chỉ LẮNG NGHE EventBus, không tham chiếu trực tiếp tới Player/Boss → thay gameplay không phải sửa UI.

@onready var hearts: HeartsDisplay = %Hearts
@onready var area_label: Label = %AreaLabel
@onready var boss_panel: Control = %BossPanel
@onready var boss_name_label: Label = %BossName
@onready var boss_bar: ProgressBar = %BossBar
@onready var pause_label: Label = %PauseLabel
@onready var toast_label: Label = %ToastLabel

var _area_tween: Tween
var _boss_tween: Tween
var _toast_tween: Tween


func _ready() -> void:
	area_label.modulate.a = 0.0
	toast_label.modulate.a = 0.0
	boss_panel.hide()
	pause_label.hide()
	EventBus.player_health_changed.connect(hearts.set_health)
	EventBus.area_entered.connect(_show_area_name)
	EventBus.boss_engaged.connect(_on_boss_engaged)
	EventBus.boss_health_changed.connect(_on_boss_health_changed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.toast_requested.connect(show_toast)
	EventBus.game_saved.connect(func(slot: int) -> void: show_toast("Đã lưu (slot %d)" % slot))
	EventBus.game_loaded.connect(func(slot: int) -> void: show_toast("Đã tải (slot %d)" % slot))
	SceneManager.level_changed.connect(func(_level: Node) -> void: boss_panel.hide())


func _process(_delta: float) -> void:
	pause_label.visible = get_tree().paused


func show_toast(text: String) -> void:
	toast_label.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(1.2)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.4)


func _show_area_name(area_name: String) -> void:
	area_label.text = area_name
	if _area_tween:
		_area_tween.kill()
	area_label.modulate.a = 0.0
	_area_tween = create_tween()
	_area_tween.tween_interval(0.4)
	_area_tween.tween_property(area_label, "modulate:a", 1.0, 0.8)
	_area_tween.tween_interval(2.5)
	_area_tween.tween_property(area_label, "modulate:a", 0.0, 1.2)


func _on_boss_engaged(boss_name: String, max_health: int) -> void:
	boss_name_label.text = boss_name
	boss_bar.max_value = max_health
	boss_bar.value = max_health
	boss_panel.show()


func _on_boss_health_changed(current: int, max_health: int) -> void:
	boss_bar.max_value = max_health
	if _boss_tween:
		_boss_tween.kill()
	_boss_tween = create_tween()
	_boss_tween.tween_property(boss_bar, "value", float(current), 0.25)


func _on_boss_defeated(_boss_name: String) -> void:
	await get_tree().create_timer(1.5).timeout
	boss_panel.hide()
