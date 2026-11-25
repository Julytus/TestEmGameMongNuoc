class_name Player
extends CharacterBody3D
## Nhân vật người chơi. Hành vi cụ thể nằm trong các State (thư mục states/);
## script này chỉ cung cấp API dùng chung: đọc input, di chuyển, hướng nhìn, animation.

@export_group("Movement")
@export var move_speed: float = 4.5
@export var acceleration: float = 35.0
@export var friction: float = 45.0

@export_group("Jump")
## Vận tốc bật lên: sqrt(2·g·h) với h ≈ 1,3 m (g = 9,8) — leo được bậc 1 m, không leo được 2 m.
@export var jump_velocity: float = 5.05
## Tăng/giảm tốc ngang khi đang trên không (thấp hơn acceleration để có quán tính).
@export var air_acceleration: float = 18.0
## Rơi nhanh hơn ngưỡng này (m/s) khi không chạm sàn mới coi là rơi khỏi mép — tránh nháy anim trên dốc nhỏ.
@export var fall_speed_threshold: float = 1.0

@export_group("Dodge")
@export var dodge_speed: float = 10.0
@export var dodge_duration: float = 0.22
@export var dodge_cooldown: float = 0.35

@export_group("Combat")
@export var attack_duration: float = 0.3
## Khoảng thời gian (giây, tính từ lúc bắt đầu chém) hitbox có hiệu lực.
@export var attack_active_window: Vector2 = Vector2(0.06, 0.2)
@export var invulnerability_time: float = 1.0

var input_vector: Vector2 = Vector2.ZERO
var facing: Vector3 = Vector3.BACK
var dodge_cooldown_left: float = 0.0
## Animation gốc đang chạy (idle/walk/attack/dodge/hurt); hậu tố hướng được ghép tự động.
var _base_animation: StringName = &"idle"
## Hướng sprite so với camera: down (quay mặt về camera), up (quay lưng), side (ngang, trái = lật).
var _sprite_direction: StringName = &"down"

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var sprite: AnimatedSprite3D = %Sprite
@onready var state_machine: StateMachine = %StateMachine
@onready var health: HealthComponent = %Health
@onready var hurtbox: Hurtbox = %Hurtbox
@onready var attack_pivot: Node3D = %AttackPivot
@onready var attack_hitbox: Hitbox = %AttackHitbox


func _ready() -> void:
	health.max_health = GameState.player_max_health
	health.current_health = clampi(GameState.player_health, 1, health.max_health)
	health.invulnerability_time = invulnerability_time
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	hurtbox.hit.connect(_on_hurt)
	sprite.frame_changed.connect(_on_sprite_frame_changed)
	attack_hitbox.active = false
	set_facing(facing)
	_on_health_changed(health.current_health, health.max_health)


func _physics_process(delta: float) -> void:
	input_vector = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	dodge_cooldown_left = maxf(dodge_cooldown_left - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	RenderingServer.global_shader_parameter_set(&"player_position", global_position)


func _process(_delta: float) -> void:
	_update_sprite_direction()
	_update_sprite_stretch()
	# Nhấp nháy khi đang trong i-frames sau khi trúng đòn
	if health.is_in_iframes() and not health.is_dead():
		sprite.visible = int(Time.get_ticks_msec() / 70.0) % 2 == 0
	else:
		sprite.visible = true


## Sprite dùng billboard khoá trục Y (đứng thẳng) để không ngả ra sau lún vào cây/đá/block phía sau.
## Bù độ co do camera cúi: kéo giãn Y theo 1/cos(pitch) để chiều cao trên màn hình như billboard thường.
## (Visual không phải physics body → scale không đều không vi phạm luật Jolt.)
func _update_sprite_stretch() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var stretch := 1.0 / maxf(cos(camera.global_rotation.x), 0.2)
	var visual := sprite.get_parent() as Node3D
	if not is_equal_approx(visual.scale.y, stretch):
		visual.scale = Vector3(1.0, stretch, 1.0)


## Hướng di chuyển theo góc xoay (yaw) của camera hiện tại.
func get_move_direction() -> Vector3:
	var direction := Vector3(input_vector.x, 0.0, input_vector.y)
	var camera := get_viewport().get_camera_3d()
	if camera:
		direction = direction.rotated(Vector3.UP, camera.global_rotation.y)
	return direction


## Tăng/giảm tốc vận tốc ngang về target rồi move_and_slide.
func move_toward_velocity(target: Vector3, rate: float, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()


func set_facing(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	facing = direction.normalized()
	attack_pivot.basis = Basis.looking_at(facing, Vector3.UP)
	_update_sprite_direction()


## Chạy animation gốc theo hướng hiện tại (vd. "walk" → "walk_side").
func play_animation(anim: StringName) -> void:
	_base_animation = anim
	_play_directional(false)


## Chọn bộ sprite theo hướng nhìn so với camera (camera có thể xoay).
func _update_sprite_direction() -> void:
	var local := facing
	var camera := get_viewport().get_camera_3d()
	if camera:
		local = facing.rotated(Vector3.UP, -camera.global_rotation.y)
	var dir: StringName
	if absf(local.x) > absf(local.z) * 0.9:
		dir = &"side"
	elif local.z > 0.0:
		dir = &"down"
	else:
		dir = &"up"
	sprite.flip_h = dir == &"side" and local.x < 0.0
	if dir != _sprite_direction:
		_sprite_direction = dir
		_play_directional(true)


func _play_directional(keep_progress: bool) -> void:
	var anim := StringName("%s_%s" % [_base_animation, _sprite_direction])
	if not sprite.sprite_frames.has_animation(anim):
		anim = _base_animation
	if sprite.animation == anim and sprite.is_playing():
		return
	var frame := sprite.frame
	var progress := sprite.frame_progress
	sprite.play(anim)
	# Đổi hướng giữa chừng: giữ nhịp bước chân thay vì chạy lại từ đầu
	if keep_progress and frame < sprite.sprite_frames.get_frame_count(anim):
		sprite.set_frame_and_progress(frame, progress)


## Khung chạm đất của anim walk: khung 0 và khung giữa (chân trái / chân phải) → phát bước chân.
func _on_sprite_frame_changed() -> void:
	if _base_animation != &"walk" or not is_on_floor():
		return
	var half := sprite.sprite_frames.get_frame_count(sprite.animation) >> 1
	if sprite.frame == 0 or sprite.frame == half:
		emit_footstep(1.0)


func emit_footstep(strength: float) -> void:
	EventBus.player_footstep.emit(global_position, strength)


func can_dodge() -> bool:
	return dodge_cooldown_left <= 0.0


func _on_health_changed(current: int, max_value: int) -> void:
	GameState.player_health = current
	GameState.player_max_health = max_value
	EventBus.player_health_changed.emit(current, max_value)


func _on_hurt(hitbox: Hitbox) -> void:
	if health.is_dead():
		return
	var away := global_position - hitbox.global_position
	away.y = 0.0
	EventBus.camera_shake_requested.emit(0.35)
	state_machine.transition_to(&"Hurt", {"knockback": away.normalized() * hitbox.knockback})


func _on_died() -> void:
	state_machine.transition_to(&"Dead")
	EventBus.camera_shake_requested.emit(0.6)
	EventBus.player_died.emit()
