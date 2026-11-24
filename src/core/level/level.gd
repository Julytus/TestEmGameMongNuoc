class_name Level
extends Node3D
## Script gốc cho mọi level/map. Tự sinh người chơi tại SpawnPoint, gắn camera, phát nhạc, hiện tên khu vực.
## Tạo map mới: tạo scene Node3D, gắn script này (hoặc kế thừa), thêm SpawnPoint + FollowCamera.

const PLAYER_SCENE: PackedScene = preload("res://src/entities/player/player.tscn")

## Tên khu vực hiện ở giữa màn hình khi vào map (để trống = không hiện).
@export var area_name: String = ""
@export var music: AudioStream
@export var follow_camera: FollowCamera

var player: Player


func _ready() -> void:
	_spawn_player()
	if music:
		AudioManager.play_music(music)
	if area_name != "":
		EventBus.area_entered.emit(area_name)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	var spawn := find_spawn_point(GameState.spawn_id)
	if spawn:
		player.global_position = spawn.global_position
	else:
		push_warning("%s: không tìm thấy SpawnPoint '%s'" % [name, GameState.spawn_id])
	# Dev: --pos=x,z đặt người chơi tại tọa độ world (soi cận cảnh khi chụp màn hình)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pos="):
			var xz := arg.trim_prefix("--pos=").split_floats(",")
			if xz.size() == 2:
				player.global_position = Vector3(xz[0], 0.1, xz[1])
	player.reset_physics_interpolation()
	if follow_camera:
		follow_camera.target = player
		follow_camera.snap_to_target()


func find_spawn_point(id: StringName) -> SpawnPoint:
	var fallback: SpawnPoint = null
	for node in get_tree().get_nodes_in_group(&"spawn_points"):
		var spawn := node as SpawnPoint
		if spawn == null or not is_ancestor_of(spawn):
			continue
		if spawn.id == id:
			return spawn
		if fallback == null or spawn.id == &"default":
			fallback = spawn
	return fallback
