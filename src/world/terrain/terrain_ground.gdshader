// Mặt đất HD-2D: trộn texture cỏ / đất pixel art theo bản đồ layout.
// Ranh giới snap theo lưới pixel (16 px = 1 m) → mép răng cưa kiểu pixel art, góc bo nhờ nội suy layout.
// Ô nước bị khoét (discard) để lộ mặt nước TerrainWater nằm thấp hơn; ô rừng tối hơn (bóng tán cây).
shader_type spatial;
render_mode specular_disabled;

#include "res://src/world/terrain/terrain_common.gdshaderinc"
#include "res://src/world/terrain/terrain_noise.gdshaderinc"

group_uniforms textures;
uniform sampler2D grass_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D dirt_texture : source_color, filter_nearest, repeat_enable;
// Kích thước (m) mà một texture phủ: 64 px / 16 = 4 m
uniform float texture_meters = 4.0;

group_uniforms edges;
uniform float edge_shadow_width : hint_range(0.0, 0.3) = 0.1;
uniform vec3 edge_shadow_color : source_color = vec3(0.72, 0.58, 0.48);
uniform float grass_lip_width : hint_range(0.0, 0.3) = 0.06;
uniform vec3 grass_lip_color : source_color = vec3(0.6, 0.8, 0.35);
// Đất ẩm sẫm màu quanh bờ nước: bề rộng (m) dải ngoài mép nước (theo water field)
uniform float shore_width : hint_range(0.0, 0.4) = 0.14;
uniform vec3 shore_color : source_color = vec3(0.55, 0.6, 0.45);

group_uniforms tint;
uniform vec3 grass_tint : source_color = vec3(1.0);
uniform vec3 dirt_tint : source_color = vec3(1.0);
// Làm tối đất dưới vùng cỏ cao (cỏ che sáng) → khối cỏ có chiều sâu
uniform float tall_grass_shade : hint_range(0.0, 1.0) = 0.3;
// Mảng màu loang (cùng noise + tỉ lệ với grass_card để cỏ và đất khớp màu)
uniform sampler2D patch_noise : filter_linear, repeat_enable;
uniform float patch_scale = 0.035;
uniform vec3 patch_color : source_color = vec3(1.12, 1.06, 0.62);
uniform float patch_amount : hint_range(0.0, 1.0) = 0.3;
uniform vec3 forest_floor_tint : source_color = vec3(0.5, 0.58, 0.48);
group_uniforms;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = terrain_snap(world_pos.xz);
	// Cùng texel với water.gdshader → lỗ khoét khớp tuyệt đối mép nước.
	float water_sd = water_field_at(p).x;
	if (water_sd > 0.0) {
		discard;
	}
	vec4 f = terrain_fields(p);
	float is_dirt = step(0.5, f.x);

	vec2 tex_uv = world_pos.xz / texture_meters;
	vec3 grass = texture(grass_texture, tex_uv).rgb * grass_tint;
	vec3 dirt = texture(dirt_texture, tex_uv).rgb * dirt_tint;

	// Bóng cỏ đổ xuống mép đường + viền cỏ sáng sát mép
	float shadow_band = is_dirt * (1.0 - step(0.5 + edge_shadow_width, f.x));
	dirt *= mix(vec3(1.0), edge_shadow_color, shadow_band);
	float lip = (1.0 - is_dirt) * step(0.5 - grass_lip_width, f.x);
	grass = mix(grass, grass_lip_color, lip * 0.6);
	float patch = smoothstep(0.35, 0.7, texture(patch_noise, p * patch_scale).r);
	grass = mix(grass, grass * patch_color, patch * patch_amount);
	grass *= 1.0 - f.y * tall_grass_shade;
	grass *= mix(vec3(1.0), forest_floor_tint, smoothstep(0.2, 0.8, f.w));

	vec3 col = mix(grass, dirt, is_dirt);
	col *= mix(vec3(1.0), shore_color, step(-shore_width, water_sd));
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
