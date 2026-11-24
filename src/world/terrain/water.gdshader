// Mặt nước stylized HD-2D (tham chiếu video). Mặt nước ĐẶC (opaque) nhưng giả độ trong bằng parallax:
// - Đáy hồ (texture đất + caustics) được vẽ ngay trong shader tại điểm tia nhìn chạm đáy → thấy đáy
//   lệch theo góc nhìn như nhìn xuyên nước thật; nếu tia chạm vào dưới bờ đất → thấy vách bờ.
// - Màu xanh ngọc đậm dần ra giữa (khoảng cách tới bờ do TerrainWater tính sẵn), viền đồng mức lượn
// - Viền bọt trắng uốn lượn sát mép + sóng gợn chạy dần vào bờ
// - Phản chiếu trời / cây (SSR) lăn tăn theo pháp tuyến gợn pixel
// Opaque nên không bị sương phủ 2 lần và rẻ hơn dùng screen texture.
shader_type spatial;

#include "res://src/world/terrain/terrain_common.gdshaderinc"

group_uniforms colors;
uniform vec3 shallow_color : source_color = vec3(0.28, 0.62, 0.6);
uniform vec3 deep_color : source_color = vec3(0.12, 0.35, 0.47);
// Khoảng cách tới bờ (m) mà nước đạt độ sâu tối đa
uniform float depth_distance = 2.4;
uniform float color_steps = 3.0;
// Độ đục: sát bờ → giữa hồ (0 = thấy rõ đáy, 1 = không thấy đáy)
uniform float clarity_shallow : hint_range(0.0, 1.0) = 0.35;
uniform float clarity_deep : hint_range(0.0, 1.0) = 0.92;
// Phần màu nước KHÔNG chịu ánh sáng môi trường (giữ sắc xanh ngọc khi trời lệch màu như hoàng hôn).
// Phần này được "chiếu" bởi sky_sheen – màu ánh trời do LightingDirector đặt theo preset.
uniform float unlit_amount : hint_range(0.0, 1.0) = 0.5;
uniform vec3 sky_sheen : source_color = vec3(0.55);
uniform vec3 water_tint : source_color = vec3(1.0);

group_uniforms bed;
uniform sampler2D bed_texture : source_color, filter_nearest, repeat_enable;
uniform float bed_texture_meters = 4.0;
uniform vec3 bed_tint : source_color = vec3(0.55, 0.62, 0.48);
// Độ sâu đáy dưới mặt nước (m) – quyết định độ lệch parallax
uniform float bed_depth = 0.5;
uniform vec3 wall_color : source_color = vec3(0.24, 0.2, 0.13);
uniform float caustic_scale = 1.4;
uniform float caustic_speed = 0.35;
uniform float caustic_width : hint_range(0.0, 0.2) = 0.035;
uniform float caustic_brightness : hint_range(0.0, 1.0) = 0.3;

group_uniforms shore;
uniform vec3 foam_color : source_color = vec3(0.93, 0.98, 0.97);
uniform float foam_far_width : hint_range(0.0, 0.5) = 0.15;
uniform float foam_side_width : hint_range(0.0, 0.5) = 0.08;
uniform float foam_wave : hint_range(0.0, 1.0) = 0.6;
uniform vec3 edge_line_color : source_color = vec3(0.12, 0.16, 0.1);
uniform float edge_line_width : hint_range(0.0, 0.2) = 0.05;

group_uniforms waves;
uniform float wave_frequency = 0.8;
uniform float wave_speed = 0.25;
uniform float wave_thickness : hint_range(0.0, 0.5) = 0.08;
uniform float wave_reach = 1.2;
uniform float wave_brightness : hint_range(0.0, 1.0) = 0.25;
// Độ lượn của đường đồng mức (m) để không lộ hình chữ nhật của ô layout
uniform float contour_wobble = 0.35;

group_uniforms surface;
uniform float streak_brightness : hint_range(0.0, 0.3) = 0.05;
uniform float ripple_length = 5.0;
uniform float ripple_rarity : hint_range(0.9, 1.0) = 0.985;
uniform float ripple_speed = 1.1;
uniform float ripple_brightness : hint_range(0.0, 1.0) = 0.16;
uniform float roughness : hint_range(0.0, 1.0) = 0.2;
uniform float specular : hint_range(0.0, 1.0) = 0.18;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.2;
group_uniforms;

varying vec3 world_pos;

bool is_water(vec2 world_xz) {
	return terrain_fields(terrain_snap(world_xz)).z > 0.5;
}

float shore_probe(vec2 p, vec2 dir, float max_dist) {
	for (int k = 1; k <= 4; k++) {
		float d = max_dist * float(k) / 4.0;
		if (!is_water(p + dir * d)) {
			return d;
		}
	}
	return max_dist;
}

vec3 bed_color(vec2 b, float depth) {
	vec2 bp = terrain_snap(b);
	vec3 col = texture(bed_texture, bp / bed_texture_meters).rgb * bed_tint;
	col *= 1.0 - depth * 0.5;
	vec2 q = bp * caustic_scale;
	float a = terrain_noise(q + vec2(TIME * caustic_speed, 0.0));
	float c = terrain_noise(q * 1.3 + vec2(0.0, -TIME * caustic_speed * 0.8) + 9.1);
	float caustic = 1.0 - step(caustic_width, abs(a - c));
	return col + caustic * caustic_brightness * (1.0 - depth * 0.7) * vec3(0.9, 1.0, 0.85);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = terrain_snap(world_pos.xz);
	if (!is_water(p)) {
		discard;
	}
	vec2 pixel = floor(p * pixels_per_meter);
	float wobble = (terrain_noise(p * 0.9 + 3.7) - 0.5) * contour_wobble * 2.0;
	float dist = max(shore_distance_at(p) + wobble * smoothstep(0.1, 0.6, shore_distance_at(p)), 0.0);

	float depth = clamp(dist / depth_distance, 0.0, 1.0);
	float stepped = floor(depth * color_steps + 0.5) / color_steps;
	vec3 water = mix(shallow_color, deep_color, stepped) * water_tint;

	// Parallax: tia nhìn đi xuống chạm đáy hồ cách mặt nước bed_depth mét
	vec3 view_dir = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec2 bed_point = world_pos.xz + view_dir.xz * (bed_depth / max(-view_dir.y, 0.2));
	vec3 below = is_water(bed_point) ? bed_color(bed_point, depth) : wall_color;
	float opacity = mix(clarity_shallow, clarity_deep, smoothstep(0.0, 1.0, depth));
	vec3 col = mix(below, water, opacity);

	// Vệt sáng ngang mờ + vệt pixel lấp lánh
	float streak = terrain_noise(vec2(p.x * 0.7 + TIME * 0.15, p.y * 7.0));
	col += step(0.72, streak) * streak_brightness;
	vec2 cell = vec2(floor((pixel.x + terrain_hash(vec2(pixel.y, 3.1)) * ripple_length) / ripple_length), pixel.y);
	float phase = floor(TIME * ripple_speed + terrain_hash(cell) * 8.0);
	col += step(ripple_rarity, terrain_hash(cell + phase * 0.37)) * ripple_brightness;

	// Sóng chạy vào bờ
	float ring = fract(dist * wave_frequency + TIME * wave_speed);
	float broken = step(0.55, terrain_noise(p * 1.4 + vec2(TIME * 0.15, 0.0)));
	float wave_line = step(1.0 - wave_thickness, ring) * broken * (1.0 - smoothstep(wave_reach * 0.4, wave_reach, dist));
	col = mix(col, foam_color, wave_line * wave_brightness);

	// Bọt sát bờ (dày hơn ở bờ xa camera) + đường tối mảnh ngay mép
	float wobble_w = mix(1.0 - foam_wave, 1.0 + foam_wave, terrain_noise(p * 3.0 + vec2(TIME * 0.6, -TIME * 0.4)));
	float far = shore_probe(p, vec2(0.0, -1.0), 0.6);
	float side = min(min(shore_probe(p, vec2(1.0, 0.0), 0.6), shore_probe(p, vec2(-1.0, 0.0), 0.6)),
			shore_probe(p, vec2(0.0, 1.0), 0.6));
	float foam = max(step(far, foam_far_width * wobble_w), step(side, foam_side_width * wobble_w));
	float edge_line = step(min(far, side), edge_line_width);
	col = mix(col, foam_color, foam);
	col = mix(col, edge_line_color, edge_line);

	float matte_mask = max(foam, edge_line);
	float unlit = unlit_amount * (1.0 - matte_mask);
	ALBEDO = col * (1.0 - unlit);
	EMISSION = col * sky_sheen * unlit * 2.0;
	float matte = max(foam, edge_line);
	ROUGHNESS = mix(roughness, 1.0, matte);
	SPECULAR = specular * (1.0 - matte);
	vec2 q = p * 2.5 + vec2(TIME * 0.35, TIME * 0.2);
	float h0 = terrain_noise(q);
	float hx = terrain_noise(q + vec2(0.4, 0.0)) - h0;
	float hz = terrain_noise(q + vec2(0.0, 0.4)) - h0;
	vec3 n = normalize(vec3(-hx * normal_strength * 4.0, 1.0, -hz * normal_strength * 4.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(mix(n, vec3(0.0, 1.0, 0.0), matte), 0.0)).xyz);
}
