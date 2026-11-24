// Cỏ HD-2D: màu chuyển gốc → ngọn, đợt gió sáng lên, pháp tuyến hướng trời cho ánh sáng mềm.
// Dùng với GrassField (MultiMesh). INSTANCE_CUSTOM.x = số ngẫu nhiên riêng mỗi ngọn cỏ.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, specular_disabled, diffuse_lambert_wrap;

#include "res://src/world/grass/foliage_wind.gdshaderinc"

group_uniforms colors;
uniform vec3 color_root : source_color = vec3(0.09, 0.22, 0.08);
uniform vec3 color_tip : source_color = vec3(0.55, 0.78, 0.30);
uniform vec3 color_variation : source_color = vec3(0.82, 0.80, 0.32);
uniform float variation_amount : hint_range(0.0, 1.0) = 0.35;
uniform float gust_highlight : hint_range(0.0, 1.0) = 0.15;
group_uniforms;

varying float v_height;
varying float v_rand;
varying float v_gust;

void vertex() {
	v_height = UV.y;
	v_rand = INSTANCE_CUSTOM.x;
	float gust;
	VERTEX += foliage_offset(MODEL_MATRIX[3].xyz, v_height, v_rand, TIME, gust);
	v_gust = gust;
}

void fragment() {
	vec3 col = mix(color_root, color_tip, v_height);
	col = mix(col, color_variation, v_rand * variation_amount * v_height);
	col += vec3(v_gust * gust_highlight * v_height);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	// Pháp tuyến hướng lên trời cho cả 2 mặt → cỏ sáng giống mặt đất, không bị đen mặt sau
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	AO = mix(0.35, 1.0, v_height);
	AO_LIGHT_AFFECT = 0.6;
}
