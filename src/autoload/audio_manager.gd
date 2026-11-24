extends Node
## Phát nhạc nền (crossfade giữa 2 player) và SFX 2D dùng pool (không tạo node mới mỗi lần).
## Âm thanh có vị trí trong thế giới (tiếng bước chân, slime nhảy...) → dùng AudioStreamPlayer3D ngay trong scene.

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const UI_BUS := &"UI"
const SFX_POOL_SIZE := 12
const SILENT_DB := -60.0

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer
var _music_tween: Tween
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_index := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _create_player(MUSIC_BUS)
	_music_b = _create_player(MUSIC_BUS)
	_active_music = _music_a
	for i in SFX_POOL_SIZE:
		_sfx_pool.append(_create_player(SFX_BUS))


func play_music(stream: AudioStream, fade_time: float = 1.0) -> void:
	if stream == null:
		stop_music(fade_time)
		return
	if _active_music.stream == stream and _active_music.playing:
		return
	var outgoing := _active_music
	var incoming := _music_b if outgoing == _music_a else _music_a
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	_active_music = incoming

	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel()
	_music_tween.tween_property(incoming, "volume_db", 0.0, fade_time)
	if outgoing.playing:
		_music_tween.tween_property(outgoing, "volume_db", SILENT_DB, fade_time)
	_music_tween.chain().tween_callback(outgoing.stop)


func stop_music(fade_time: float = 1.0) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_active_music, "volume_db", SILENT_DB, fade_time)
	_music_tween.tween_callback(_active_music.stop)


func play_sfx(stream: AudioStream, pitch_variation: float = 0.0, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player := _sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func _create_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player
