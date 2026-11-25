// Block 1 m (GridMap, MeshLibrary từ tools/art/build_block_library.gd): màu lấy thẳng từ atlas pixel
// (gen_blocks.py, 32 px/m, nearest). Ánh sáng cùng kiểu rock.gdshader để block đứng cạnh đá/mặt đất không lệch tông:
// mặt phẳng một bậc sáng, dải bo cạnh (pháp tuyến mượt) lên/xuống bậc → mép mềm, bóng ngả tím / sáng ngả vàng, mặt khuất giữ tối thiểu min_light (ban đêm không đen kịt).
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;

group_uniforms lighting;
uniform float light_steps = 3.0;
uniform float wrap : hint_range(0.0, 1.0) = 0.0;
uniform vec3 shadow_tint : source_color = vec3(0.74, 0.7, 0.86);
uniform vec3 light_tint : source_color = vec3(1.08, 1.02, 0.9);
uniform float min_light : hint_range(0.0, 0.6) = 0.18;
group_uniforms;

void fragment() {
	ALBEDO = texture(atlas, UV).rgb * COLOR.rgb; // COLOR = AO chân khối bake trong mesh
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	w = floor(w * light_steps + 0.5) / light_steps;
	// Nắng/trăng: bóng đổ chia bậc cứng. Đèn điểm: giữ suy giảm theo khoảng cách (tránh cắt ô cluster Forward+).
	float shadow = LIGHT_IS_DIRECTIONAL ? step(0.5, ATTENUATION) : 1.0;
	float falloff = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	float lit = w * shadow;
	vec3 tint = mix(shadow_tint, light_tint, lit);
	DIFFUSE_LIGHT += LIGHT_COLOR * tint * max(lit, min_light) * falloff / PI;
}
