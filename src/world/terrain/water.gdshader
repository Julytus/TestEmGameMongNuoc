// Mặt nước stylized HD-2D (tham chiếu video). Mặt nước ĐẶC (opaque) nhưng giả độ trong bằng parallax:
// - Đáy hồ (texture đất + caustics) được vẽ ngay trong shader tại điểm tia nhìn chạm đáy → thấy đáy
//   lệch theo góc nhìn như nhìn xuyên nước thật; nếu tia chạm vào dưới bờ đất → thấy vách bờ.
// - Màu xanh ngọc đậm dần ra giữa (khoảng cách tới bờ đọc từ water field), viền đồng mức lượn
// - Viền bọt trắng uốn lượn sát mép + sóng gợn chạy dần vào bờ
// - Ánh trời (sky_sheen) + specular lăn tăn theo pháp tuyến gợn pixel; KHÔNG SSR (tắt: ~0,5 ms mà gần như không thấy)
//   → phản chiếu nhân vật là sprite lật giả (WaterReflection)
// Opaque nên không bị sương phủ 2 lần và rẻ hơn dùng screen texture.
// Bake-first: fragment CHỈ đọc texture + cuộn theo TIME (không noise thủ tục / vòng lặp). Noise bake bởi
// tools/art/gen_water.py (water_noise, water_sparkle); mặt nạ + khoảng cách bờ bởi WaterField (water field).
// Low (global water_detail = 0, Settings đặt): đáy phẳng tại p, không parallax / vách bờ / caustic.
shader_type spatial;

#include "res://src/world/terrain/terrain_common.gdshaderinc"

// 1 = đủ chi tiết (High/Medium), 0 = Low. project.godot [shader_globals], Settings.apply_graphics() đặt.
global uniform float water_detail;

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
uniform float sparkle_length = 5.0;
uniform float sparkle_rarity : hint_range(0.9, 1.0) = 0.985;
uniform float sparkle_speed = 1.1;
uniform float sparkle_brightness : hint_range(0.0, 1.0) = 0.16;
uniform float roughness : hint_range(0.0, 1.0) = 0.2;
uniform float specular : hint_range(0.0, 1.0) = 0.18;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.2;

group_uniforms detail;
// Value noise lát liền (R = noise, GB = sai phân 0.4 ô mã hóa 0.5 + 0.8·d) – dữ liệu tuyến tính, không source_color
uniform sampler2D water_noise : filter_linear, repeat_enable;
// = CELLS trong gen_water.py (số ô noise trên một tile) → wnoise(q) cùng tần số với value noise lưới nguyên
uniform float noise_cells = 32.0;
// White noise thay hash cho đốm lấp lánh (đọc đúng tâm texel)
uniform sampler2D sparkle_texture : filter_nearest, repeat_enable;

group_uniforms ripple;
// Gợn sóng tương tác (WaterRipples vẽ vòng bước chân vào SubViewport đi theo người chơi). Global uniform → mọi
// mặt nước / chunk biển dùng chung, không phụ thuộc water field / khoảng cách tới bờ (chạy được giữa biển).
// Texture: R = độ cao sóng (0 = phẳng), G = bọt. water_ripple_rect: xy = góc thế giới XZ, zw = kích thước (m).
// water_ripple_strength = 0 (không có vòng nào) → không đọc texture.
global uniform sampler2D water_ripple_texture : filter_linear;
global uniform vec4 water_ripple_rect;
global uniform float water_ripple_strength;
// Đỉnh sóng sáng lên theo nấc (pixel art, nhìn rõ cả khi SSR tắt ở Low); ngưỡng bọt (step → pixel sắc nét).
uniform float ripple_highlight : hint_range(0.0, 1.0) = 0.55;
uniform float ripple_steps = 3.0;
// Độ lệch pháp tuyến do gợn (chỉ làm phản chiếu SSR lăn tăn theo vòng).
uniform float ripple_slope_scale = 1.0;
uniform float ripple_foam_threshold : hint_range(0.0, 1.0) = 0.4;
group_uniforms;

// Mặt đất cao hơn mặt nước bao nhiêu (m) – TerrainWater đặt = -water_level. Mặt nạ + các lớp mặt nước tính tại
// giao điểm tia nhìn với MẶT ĐẤT → cùng điểm XZ mà terrain_ground khoét lỗ → không hở viền.
uniform float ground_offset = 0.06;

varying vec3 world_pos;

float wnoise(vec2 q) {
	return texture(water_noise, q / noise_cells).r;
}

float sparkle_rnd(vec2 c) {
	vec2 s = vec2(textureSize(sparkle_texture, 0));
	return texture(sparkle_texture, (mod(c, s) + 0.5) / s).r;
}

// Mô phỏng shore_probe cũ (dò 4 bước 0.15 m): khoảng cách tới bờ lượng tử thành bậc 0.15, chặn 0.6.
float probe_steps(float d) {
	return min(ceil(d / 0.15) * 0.15, 0.6);
}

vec3 bed_color(vec2 b, float depth) {
	vec2 bp = terrain_snap(b);
	vec3 col = texture(bed_texture, bp / bed_texture_meters).rgb * bed_tint;
	col *= 1.0 - depth * 0.5;
	vec2 q = bp * caustic_scale;
	float a = wnoise(q + vec2(TIME * caustic_speed, 0.0));
	float c = wnoise(q * 1.3 + vec2(0.0, -TIME * caustic_speed * 0.8) + 9.1);
	float caustic = 1.0 - step(caustic_width, abs(a - c));
	return col + caustic * caustic_brightness * (1.0 - depth * 0.7) * vec3(0.9, 1.0, 0.85);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 view_dir = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec2 p = terrain_snap(world_pos.xz + view_dir.xz * (ground_offset / min(view_dir.y, -0.01)));
	vec2 f = water_field_at(p);
	if (f.x <= 0.0) {
		discard;
	}
	vec2 pixel = floor(p * pixels_per_meter);
	float wobble = (wnoise(p * 0.9 + 3.7) - 0.5) * contour_wobble * 2.0;
	float dist = max(f.x + wobble * smoothstep(0.1, 0.6, f.x), 0.0);

	float depth = clamp(dist / depth_distance, 0.0, 1.0);
	float stepped = floor(depth * color_steps + 0.5) / color_steps;
	vec3 water = mix(shallow_color, deep_color, stepped) * water_tint;

	// Dải sâu nhất: không thấy đáy (bỏ hẳn phần đáy). Còn lại: đáy parallax (High/Medium) hoặc đáy phẳng (Low).
	vec3 col = water;
	if (stepped < 1.0) {
		vec3 below;
		if (water_detail > 0.5) {
			// Parallax: tia nhìn đi xuống chạm đáy hồ cách mặt nước bed_depth mét (tính từ world_pos – đáy là vật lý)
			vec2 bed_point = world_pos.xz + view_dir.xz * (bed_depth / max(-view_dir.y, 0.2));
			below = is_water_at(terrain_snap(bed_point)) ? bed_color(bed_point, depth) : wall_color;
		} else {
			below = texture(bed_texture, p / bed_texture_meters).rgb * bed_tint * (1.0 - depth * 0.5);
		}
		float opacity = mix(clarity_shallow, clarity_deep, smoothstep(0.0, 1.0, depth));
		col = mix(below, water, opacity);
	}

	// Vệt sáng ngang mờ + vệt pixel lấp lánh
	float streak = wnoise(vec2(p.x * 0.7 + TIME * 0.15, p.y * 7.0));
	col += step(0.72, streak) * streak_brightness;
	vec2 cell = vec2(floor((pixel.x + sparkle_rnd(vec2(3.0, pixel.y)) * sparkle_length) / sparkle_length), pixel.y);
	float phase = floor(TIME * sparkle_speed + sparkle_rnd(cell) * 8.0);
	vec2 sparkle_size = vec2(textureSize(sparkle_texture, 0));
	col += step(sparkle_rarity, sparkle_rnd(cell + mod(phase * vec2(37.0, 59.0), sparkle_size))) * sparkle_brightness;

	// Sóng chạy vào bờ
	float ring = fract(dist * wave_frequency + TIME * wave_speed);
	float broken = step(0.55, wnoise(p * 1.4 + vec2(TIME * 0.15, 0.0)));
	float wave_line = step(1.0 - wave_thickness, ring) * broken * (1.0 - smoothstep(wave_reach * 0.4, wave_reach, dist));
	col = mix(col, foam_color, wave_line * wave_brightness);

	// Bọt sát bờ (dày hơn ở bờ xa camera) + đường tối mảnh ngay mép
	float wobble_w = mix(1.0 - foam_wave, 1.0 + foam_wave, wnoise(p * 3.0 + vec2(TIME * 0.6, -TIME * 0.4)));
	float far = probe_steps(f.y);
	float side = probe_steps(f.x);
	float foam = max(step(far, foam_far_width * wobble_w), step(side, foam_side_width * wobble_w));
	float edge_line = step(min(far, side), edge_line_width);
	col = mix(col, foam_color, foam);
	col = mix(col, edge_line_color, edge_line);

	// Gợn sóng bước chân: mọi lần đọc water_ripple_texture nằm trong nhánh này (tắt khi không có vòng nào).
	vec2 ripple_slope = vec2(0.0);
	float ripple_foam = 0.0;
	if (water_ripple_strength > 0.0) {
		vec2 ruv = (p - water_ripple_rect.xy) / max(water_ripple_rect.zw, vec2(1e-4));
		if (all(greaterThanEqual(ruv, vec2(0.0))) && all(lessThanEqual(ruv, vec2(1.0)))) {
			vec2 texel = 1.0 / vec2(textureSize(water_ripple_texture, 0));
			vec2 r0 = texture(water_ripple_texture, ruv).rg * water_ripple_strength;
			float rx = texture(water_ripple_texture, ruv + vec2(texel.x, 0.0)).r * water_ripple_strength;
			float rz = texture(water_ripple_texture, ruv + vec2(0.0, texel.y)).r * water_ripple_strength;
			ripple_slope = vec2(rx - r0.x, rz - r0.x) * ripple_slope_scale;
			float level = floor(clamp(r0.x, 0.0, 1.0) * ripple_steps + 0.35) / ripple_steps;
			col = mix(col, foam_color, level * ripple_highlight);
			ripple_foam = step(ripple_foam_threshold, r0.y);
			col = mix(col, foam_color, ripple_foam);
		}
	}

	float matte = max(max(foam, edge_line), ripple_foam);
	float unlit = unlit_amount * (1.0 - matte);
	ALBEDO = col * (1.0 - unlit);
	EMISSION = col * sky_sheen * unlit * 2.0;
	ROUGHNESS = mix(roughness, 1.0, matte);
	SPECULAR = specular * (1.0 - matte);
	vec2 q = p * 2.5 + vec2(TIME * 0.35, TIME * 0.2);
	vec2 d = (texture(water_noise, q / noise_cells).gb - 0.5) / 0.8 + ripple_slope;
	vec3 n = normalize(vec3(-d.x * normal_strength * 4.0, 1.0, -d.y * normal_strength * 4.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(mix(n, vec3(0.0, 1.0, 0.0), matte), 0.0)).xyz);
}
