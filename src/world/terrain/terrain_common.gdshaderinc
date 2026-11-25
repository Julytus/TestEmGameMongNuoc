// Dùng chung cho terrain_ground.gdshader và water.gdshader: đọc layout, snap lưới pixel, đọc water field.
// KHÔNG chứa noise thủ tục (lượn mép đường đất bake sẵn vào ground_field — terrain_ground.gdshader).

uniform sampler2D layout_map : filter_linear, repeat_disable;
uniform vec2 layout_size = vec2(48.0);
// Phải khớp WaterField.PIXELS_PER_METER (16 px = 1 m)
uniform float pixels_per_meter = 16.0;

// Tâm pixel (lưới pixels_per_meter) chứa world_xz.
vec2 terrain_snap(vec2 world_xz) {
	return (floor(world_xz * pixels_per_meter) + 0.5) / pixels_per_meter;
}

vec4 terrain_layout(vec2 p) {
	return texture(layout_map, p / layout_size + 0.5);
}

// ---- Water field (WaterField.gd dựng lúc load, 16 px/m, TerrainLayout.apply_to_material gán): x = khoảng cách có dấu
// tới mép nước (m, > 0 trong nước, đã gồm độ lượn mép), y = khoảng cách tới bờ hướng -Z (m, 0 ngoài nước).
// Đất và nước đọc CÙNG texel (gốc field snap lưới 1/16 m, p là tâm pixel đã terrain_snap).
uniform sampler2D water_field : hint_default_black, filter_nearest, repeat_disable;
// xy = góc (thế giới XZ), zw = kích thước (m); z = 0 → không có nước
uniform vec4 water_field_rect = vec4(0.0);

vec2 water_field_at(vec2 p) {
	if (water_field_rect.z <= 0.0) {
		return vec2(-1000.0, 0.0);
	}
	return texture(water_field, (p - water_field_rect.xy) / water_field_rect.zw).rg;
}

bool is_water_at(vec2 p) {
	return water_field_at(p).x > 0.0;
}
