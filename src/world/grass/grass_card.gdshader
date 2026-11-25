// Bụi cỏ pixel art dạng billboard (luôn xoay về camera quanh trục Y) – dùng với GrassField mesh_type = Card.
// Texture là atlas nhiều biến thể xếp ngang; mỗi instance chọn ngẫu nhiên 1 biến thể và có thể lật ngang.
// INSTANCE_CUSTOM: x = ngẫu nhiên (biến thể + pha gió), y = ngẫu nhiên (lật ngang).
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, specular_disabled, diffuse_lambert_wrap;

#include "res://src/world/grass/foliage_wind.gdshaderinc"

uniform sampler2D tuft_atlas : source_color, filter_nearest, repeat_disable;
uniform int atlas_columns = 4;
// >= 0: ép dùng biến thể này (cây đặt lẻ bằng MeshInstance3D không có INSTANCE_CUSTOM)
instance uniform float variant_override = -1.0;

group_uniforms colors;
uniform vec3 tint : source_color = vec3(0.86, 0.9, 0.82);
// Gốc bụi tối hơn để hòa vào mặt đất
uniform float root_darken : hint_range(0.0, 1.0) = 0.5;
uniform vec3 color_variation : source_color = vec3(0.95, 0.9, 0.5);
uniform float variation_amount : hint_range(0.0, 1.0) = 0.25;
uniform float gust_highlight : hint_range(0.0, 1.0) = 0.12;
// Mảng màu loang trên đồng cỏ (dùng chung noise với mặt đất để khớp nhau)
uniform float patch_scale = 0.035;
uniform vec3 patch_color : source_color = vec3(1.12, 1.06, 0.62);
uniform float patch_amount : hint_range(0.0, 1.0) = 0.0;
// >0: phần trên sprite tự phát sáng nhẹ (hoa ban đêm). LightingDirector chỉnh theo preset.
uniform float petal_glow : hint_range(0.0, 2.0) = 0.0;
group_uniforms;

varying float v_height;
varying float v_rand;
varying float v_gust;
varying vec2 v_uv;
varying float v_patch;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float fade = foliage_distance_fade(root, CAMERA_POSITION_WORLD);
	float width = length(MODEL_MATRIX[0].xyz) * fade;
	float height = length(MODEL_MATRIX[1].xyz) * fade;
	v_height = 1.0 - UV.y;
	v_rand = INSTANCE_CUSTOM.x;

	// Billboard trục Y: trải quad theo hướng ngang của camera
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(vec3(right.x, 0.0, right.z));
	vec3 pos = root + right * (UV.x - 0.5) * width + vec3(0.0, v_height * height, 0.0);

	float gust;
	pos += foliage_offset(root, v_height, v_rand, TIME, gust);
	VERTEX = pos;
	v_gust = gust;
	v_patch = smoothstep(0.35, 0.7, textureLod(wind_noise, root.xz * patch_scale, 0.0).r);

	float column = variant_override >= 0.0 ? variant_override : floor(v_rand * float(atlas_columns));
	float u = INSTANCE_CUSTOM.y > 0.5 ? 1.0 - UV.x : UV.x;
	v_uv = vec2((column + u) / float(atlas_columns), UV.y);
}

void fragment() {
	vec4 tex = texture(tuft_atlas, v_uv);
	vec3 col = tex.rgb * tint;
	col = mix(col, col * color_variation * 1.2, fract(v_rand * 7.13) * variation_amount);
	col = mix(col, col * patch_color, v_patch * patch_amount);
	col *= mix(1.0 - root_darken, 1.0, v_height);
	col += vec3(v_gust * gust_highlight * v_height);
	ALBEDO = col;
	EMISSION = tex.rgb * petal_glow * step(0.5, v_height);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
