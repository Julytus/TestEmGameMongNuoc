// Mặt đất HD-2D: trộn texture cỏ / đất pixel art theo bản đồ layout.
// Mép đất/cỏ + texture snap lưới 32 px = 1 m, ngưỡng lệch theo mặt nạ edge_fringe (sinh sẵn) → răng cưa cỏ xanh đậm.
// Mép nước vẫn snap 16 px = 1 m (dùng chung texel với water field / water.gdshader).
// Ô nước bị khoét (discard) để lộ mặt nước TerrainWater nằm thấp hơn; ô rừng tối hơn (bóng tán cây).
shader_type spatial;
render_mode specular_disabled;

#include "res://src/world/terrain/terrain_common.gdshaderinc"
#include "res://src/world/terrain/terrain_noise.gdshaderinc"

group_uniforms textures;
uniform sampler2D grass_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D dirt_texture : source_color, filter_nearest, repeat_enable;
// Kích thước (m) mà một texture phủ: 128 px / 32 = 4 m
uniform float texture_meters = 4.0;
// Lưới pixel của texture + mép đất/cỏ (phải khớp PX_PER_M trong tools/art/gen_terrain.py)
uniform float texture_pixels_per_meter = 32.0;

group_uniforms edges;
// Mặt nạ xám lát liền (gen_terrain.py gen_edge_fringe, cùng tỉ lệ texture_meters): nâng ngưỡng đất 0..fringe_amount
// → chỉ cỏ lấn ra đất (răng cưa), không sinh đốm đất lẻ trong cỏ (vùng cỏ luôn có f.x < 0,5).
uniform sampler2D edge_fringe : hint_default_black, filter_nearest, repeat_enable;
uniform float fringe_amount : hint_range(0.0, 0.5) = 0.3;
uniform float edge_shadow_width : hint_range(0.0, 0.3) = 0.1;
uniform vec3 edge_shadow_color : source_color = vec3(0.86, 0.78, 0.72);
// Viền cỏ xanh đậm sát mép (bề rộng theo đơn vị layout ≈ m)
uniform float grass_lip_width : hint_range(0.0, 0.3) = 0.1;
uniform vec3 grass_lip_color : source_color = vec3(0.13, 0.27, 0.1);
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
	vec2 pf = (floor(world_pos.xz * texture_pixels_per_meter) + 0.5) / texture_pixels_per_meter;
	vec4 f = terrain_fields(pf);
	vec2 tex_uv = pf / texture_meters;
	float threshold = 0.5 + texture(edge_fringe, tex_uv).r * fringe_amount;
	float is_dirt = step(threshold, f.x);

	vec3 grass = texture(grass_texture, tex_uv).rgb * grass_tint;
	vec3 dirt = texture(dirt_texture, tex_uv).rgb * dirt_tint;

	// Bóng cỏ đổ nhẹ xuống mép đường + viền cỏ xanh đậm răng cưa sát mép
	float shadow_band = is_dirt * (1.0 - step(threshold + edge_shadow_width, f.x));
	dirt *= mix(vec3(1.0), edge_shadow_color, shadow_band);
	float lip = (1.0 - is_dirt) * step(threshold - grass_lip_width, f.x);
	grass = mix(grass, grass_lip_color, lip);
	float patch = smoothstep(0.35, 0.7, texture(patch_noise, p * patch_scale).r);
	grass = mix(grass, grass * patch_color, patch * patch_amount);
	grass *= 1.0 - f.y * tall_grass_shade;
	grass *= mix(vec3(1.0), forest_floor_tint, smoothstep(0.2, 0.8, f.w));

	vec3 col = mix(grass, dirt, is_dirt);
	col *= mix(vec3(1.0), shore_color, step(-shore_width, water_sd));
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
