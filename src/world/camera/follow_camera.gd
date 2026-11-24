class_name FollowCamera
extends Node3D
## Camera nghiêng kiểu HD-2D: bám mục tiêu mượt, DOF tự lấy nét vào nhân vật, rung màn hình.
## Cấu trúc rig: FollowCamera (vị trí + yaw) → Camera3D (lùi ra theo distance, cúi xuống theo pitch).

@export var target: Node3D
@export_range(2.0, 60.0, 0.5) var distance: float = 16.0
@export_range(5.0, 85.0, 0.5) var pitch_degrees: float = 38.0
@export_range(-180.0, 180.0, 1.0) var yaw_degrees: float = 0.0
@export var follow_smoothing: float = 6.0
@export var target_offset: Vector3 = Vector3(0.0, 0.6, 0.0)

@export_group("Depth of Field")
## Tự đặt vùng nét quanh nhân vật dựa trên distance.
@export var auto_focus: bool = true
@export var focus_band: float = 3.0

@export_group("Shake")
@export var max_shake_offset: float = 0.35
@export var shake_decay: float = 2.5

var _trauma: float = 0.0
var _noise := FastNoiseLite.new()
var _noise_time: float = 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	# Camera được di chuyển trong _process và tự nội suy → tắt physics interpolation cho rig.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_noise.frequency = 2.0
	update_rig()
	EventBus.camera_shake_requested.connect(add_trauma)
	if target:
		snap_to_target()


func _process(delta: float) -> void:
	if is_instance_valid(target):
		var goal := target.get_global_transform_interpolated().origin + target_offset
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_smoothing * delta))
	_update_shake(delta)


func update_rig() -> void:
	rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	var pitch := deg_to_rad(pitch_degrees)
	camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	camera.rotation = Vector3(-pitch, 0.0, 0.0)
	var attributes := camera.attributes as CameraAttributesPractical
	if auto_focus and attributes:
		attributes.dof_blur_far_distance = distance + focus_band
		attributes.dof_blur_near_distance = maxf(distance - focus_band, 0.1)


func snap_to_target() -> void:
	if is_instance_valid(target):
		global_position = target.global_position + target_offset


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _update_shake(delta: float) -> void:
	if _trauma <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		return
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	_noise_time += delta * 60.0
	var amount := _trauma * _trauma * max_shake_offset
	camera.h_offset = _noise.get_noise_2d(_noise_time, 0.0) * amount
	camera.v_offset = _noise.get_noise_2d(0.0, _noise_time) * amount
