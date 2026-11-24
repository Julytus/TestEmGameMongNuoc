// Dùng chung cho terrain_ground.gdshader và water.gdshader: đọc layout, snap lưới pixel,
// làm lượn mép bằng noise. Hai shader phải tính giống hệt nhau để mép đất/nước khớp từng pixel.

uniform sampler2D layout_map : filter_linear, repeat_disable;
uniform vec2 layout_size = vec2(48.0);
uniform float pixels_per_meter = 16.0;
// Độ lượn của mép (noise ~0.5 m)
uniform float edge_wobble : hint_range(0.0, 0.5) = 0.12;

float terrain_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float terrain_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = terrain_hash(i);
	float b = terrain_hash(i + vec2(1.0, 0.0));
	float c = terrain_hash(i + vec2(0.0, 1.0));
	float d = terrain_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Tâm pixel (lưới pixels_per_meter) chứa world_xz.
vec2 terrain_snap(vec2 world_xz) {
	return (floor(world_xz * pixels_per_meter) + 0.5) / pixels_per_meter;
}

vec4 terrain_layout(vec2 p) {
	return texture(layout_map, p / layout_size + 0.5);
}

// Field tại điểm đã snap: x = đất, y = cỏ cao, z = nước, w = rừng. Đất và nước đã cộng noise lượn mép
// (so sánh với 0.5 để biết trong / ngoài).
vec4 terrain_fields(vec2 p) {
	vec4 lay = terrain_layout(p);
	float dirt = lay.r + (terrain_noise(p * 2.0) - 0.5) * edge_wobble * 2.0;
	float water = lay.b + (terrain_noise(p * 2.0 + 17.3) - 0.5) * edge_wobble * 2.0;
	return vec4(dirt, lay.g, water, 1.0 - lay.a);
}

// ---- Khoảng cách tới bờ (chỉ nước / đáy hồ dùng). TerrainWater tính sẵn thành texture (m).
uniform sampler2D shore_sdf : filter_linear, repeat_disable;
// xy = góc vùng nước (thế giới XZ), zw = kích thước (m)
uniform vec4 shore_sdf_rect = vec4(0.0, 0.0, 1.0, 1.0);

float shore_distance_at(vec2 p) {
	return texture(shore_sdf, (p - shore_sdf_rect.xy) / shore_sdf_rect.zw).r;
}
