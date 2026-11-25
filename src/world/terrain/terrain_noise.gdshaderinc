// Noise thủ tục cho mép đường đất của mặt đất. CHỈ terrain_ground.gdshader include, SAU terrain_common.gdshaderinc
// (dùng terrain_layout()). Nước không include file này (bake-first). Mục roadmap "Viền đất/cỏ bake" sẽ thay bằng
// field bake (cùng cơ chế WaterField) rồi xóa file này.

// Độ lượn của mép đường đất (noise ~0.5 m)
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

// Field tại điểm đã snap: x = đất (đã cộng noise lượn mép, so với 0.5), y = cỏ cao, z = nước (layout thô — mặt nạ
// nước thật nằm ở water field), w = rừng.
vec4 terrain_fields(vec2 p) {
	vec4 lay = terrain_layout(p);
	float dirt = lay.r + (terrain_noise(p * 2.0) - 0.5) * edge_wobble * 2.0;
	return vec4(dirt, lay.g, lay.b, 1.0 - lay.a);
}
