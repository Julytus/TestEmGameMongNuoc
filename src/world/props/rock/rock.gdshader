// Đá 3D vẽ kiểu pixel art: mỗi mặt đẽo (flat normal) nhận một bậc sáng; bóng ngả tím, sáng ngả vàng
// (hue-shift như bảng màu pixel art); vài đốm/khe pixel từ texture chiếu triplanar theo lưới 32 px/m;
// rêu trên mặt hướng lên với mép dither Bayer theo lưới pixel thế giới. Viền tối: rock_outline.gdshader.
// Mesh: RockMeshBuilder – COLOR.r = AO.
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D detail_texture : filter_nearest, repeat_enable;
uniform float pixels_per_meter = 32.0;
uniform float texture_pixels = 32.0;

group_uniforms stone;
uniform vec3 stone_color : source_color = vec3(0.52, 0.49, 0.48);
uniform vec3 crack_color : source_color = vec3(0.24, 0.22, 0.29);
uniform vec3 speck_color : source_color = vec3(0.72, 0.68, 0.6);
uniform vec3 base_tint : source_color = vec3(0.62, 0.56, 0.5);

group_uniforms moss;
uniform vec3 moss_dark : source_color = vec3(0.27, 0.45, 0.18);
uniform vec3 moss_light : source_color = vec3(0.49, 0.7, 0.28);
uniform float moss_slope : hint_range(0.0, 1.0) = 0.75;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.2;

group_uniforms lighting;
uniform float light_steps = 3.0;
uniform float wrap : hint_range(0.0, 1.0) = 0.0;
uniform vec3 shadow_tint : source_color = vec3(0.74, 0.7, 0.86);
uniform vec3 light_tint : source_color = vec3(1.08, 1.02, 0.9);
group_uniforms;

varying vec3 world_pos;
varying vec3 world_normal;

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 a = abs(world_normal);
	vec2 uv = a.y >= max(a.x, a.z) ? world_pos.xz : (a.x >= a.z ? vec2(world_pos.z, -world_pos.y) : vec2(world_pos.x, -world_pos.y));
	vec2 cell = floor(uv * pixels_per_meter);
	vec4 tex = texture(detail_texture, (cell + 0.5) / texture_pixels);
	vec3 col = stone_color;
	col = mix(col, speck_color, tex.r);
	col = mix(col, crack_color, tex.b);
	// Rêu: mặt hướng lên + noise (G) + ngưỡng Bayer theo ô pixel → mép rêu răng cưa pixel
	ivec2 b = ivec2(mod(cell, 4.0));
	float dither = (BAYER[b.y * 4 + b.x] / 16.0 - 0.5) * 0.1;
	float moss = tex.g * 0.7 + smoothstep(moss_slope, 1.0, world_normal.y) * 0.6 + dither;
	if (moss > 1.25 - moss_amount && tex.b < 0.5) {
		col = mix(moss_dark, moss_light, step(0.55, tex.g + dither));
	}
	col *= mix(base_tint, vec3(1.0), smoothstep(0.6, 0.85, COLOR.r));
	ALBEDO = col;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	w = floor(w * light_steps + 0.5) / light_steps;
	// Nắng/trăng: bóng đổ chia bậc cứng. Đèn điểm: giữ suy giảm theo khoảng cách (về 0 ở mép tầm chiếu),
	// nếu không ánh đèn bị cắt cụt thành ô vuông theo cluster của Forward+.
	float shadow = LIGHT_IS_DIRECTIONAL ? step(0.5, ATTENUATION) : 1.0;
	float falloff = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	float lit = w * shadow;
	vec3 tint = mix(shadow_tint, light_tint, lit);
	DIFFUSE_LIGHT += LIGHT_COLOR * tint * max(lit, 0.18) * falloff / PI;
}
