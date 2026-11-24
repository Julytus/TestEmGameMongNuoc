class_name LightingPreset
extends Resource
## Một "mood" ánh sáng hoàn chỉnh (nắng, trời, sương, hậu kỳ, đèn). Tạo file .tres mới để thêm mood
## (mưa, hang động, trong nhà...). LightingDirector chuyển mượt giữa các preset.

@export var display_name: String = "Preset"

@export_group("Sun")
@export var sun_color: Color = Color(1.0, 0.95, 0.84)
@export_range(0.0, 4.0, 0.01) var sun_energy: float = 1.2
## Góc cúi của mặt trời (âm = chiếu xuống). -15 bóng dài, -70 bóng ngắn.
@export_range(-89.0, -5.0, 0.5) var sun_pitch: float = -50.0
@export_range(-180.0, 180.0, 0.5) var sun_yaw: float = -30.0

@export_group("Sky")
@export var sky_top_color: Color = Color(0.36, 0.56, 0.84)
@export var sky_horizon_color: Color = Color(0.78, 0.84, 0.86)
@export var ground_bottom_color: Color = Color(0.2, 0.26, 0.16)
@export_range(0.0, 4.0, 0.01) var sky_energy: float = 1.0

@export_group("Ambient")
@export var ambient_color: Color = Color(0.75, 0.8, 0.9)
@export_range(0.0, 4.0, 0.01) var ambient_energy: float = 0.75

@export_group("Atmosphere")
@export var fog_color: Color = Color(0.72, 0.8, 0.86)
@export_range(0.0, 0.1, 0.0001) var fog_density: float = 0.0018
## Sương thể tích: tạo tia sáng & quầng sáng quanh đèn.
@export_range(0.0, 0.2, 0.001) var volumetric_fog_density: float = 0.004
@export var volumetric_fog_albedo: Color = Color(0.9, 0.92, 1.0)

@export_group("Post")
@export_range(0.1, 4.0, 0.01) var exposure: float = 1.05
@export_range(0.0, 4.0, 0.01) var glow_intensity: float = 0.7
@export_range(0.0, 1.0, 0.01) var glow_bloom: float = 0.06
@export_range(0.0, 2.0, 0.01) var saturation: float = 1.2
@export_range(0.0, 2.0, 0.01) var contrast: float = 1.1

@export_group("Local lights & VFX")
## Hệ số nhân năng lượng cho mọi đèn trong group "lamps".
@export_range(0.0, 8.0, 0.01) var lamp_energy: float = 1.0
## Độ sáng hạt bụi/đom đóm (group "ambient_motes").
@export_range(0.0, 8.0, 0.01) var motes_intensity: float = 1.0
## Hoa phát sáng nhẹ (uniform petal_glow của flower shader).
@export_range(0.0, 2.0, 0.01) var flower_glow: float = 0.0

@export_group("Water")
## Nhân màu nước – bù khi ánh sáng môi trường lệch màu (vd hoàng hôn làm nước ngả tím).
@export var water_tint: Color = Color.WHITE
## "Ánh trời" chiếu phần màu nước không chịu ánh sáng môi trường: ngày trung tính, hoàng hôn vàng ấm, đêm xanh tối.
@export var water_sheen: Color = Color(0.6, 0.6, 0.6)

@export_group("Characters")
## Màu nhân sprite nhân vật (group "tinted_sprites", không nhận đèn trực tiếp để giữ màu sạch).
@export var sprite_tint: Color = Color(0.94, 0.94, 0.92)


## Chuyển thành Dictionary để nội suy giữa 2 preset.
func to_values() -> Dictionary:
	return {
		"sun_color": sun_color,
		"sun_energy": sun_energy,
		"sun_rotation": Vector3(sun_pitch, sun_yaw, 0.0),
		"sky_top_color": sky_top_color,
		"sky_horizon_color": sky_horizon_color,
		"ground_bottom_color": ground_bottom_color,
		"sky_energy": sky_energy,
		"ambient_color": ambient_color,
		"ambient_energy": ambient_energy,
		"fog_color": fog_color,
		"fog_density": fog_density,
		"volumetric_fog_density": volumetric_fog_density,
		"volumetric_fog_albedo": volumetric_fog_albedo,
		"exposure": exposure,
		"glow_intensity": glow_intensity,
		"glow_bloom": glow_bloom,
		"saturation": saturation,
		"contrast": contrast,
		"lamp_energy": lamp_energy,
		"motes_intensity": motes_intensity,
		"flower_glow": flower_glow,
		"water_tint": water_tint,
		"water_sheen": water_sheen,
		"sprite_tint": sprite_tint,
	}
