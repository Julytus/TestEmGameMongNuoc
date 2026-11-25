// Tán lá cây 3D stylized: mỗi thẻ lá xoay về camera (billboard quanh tâm thẻ), pháp tuyến lấy từ mesh
// (hướng ra ngoài khối tán) → khối lá sáng/tối tròn trịa như cây 3D. Ánh sáng chia bậc mềm (toon)
// + ánh xuyên lá khi ngược sáng. Texture atlas lá dạng xám, tô màu theo bảng 2 màu + biến thể.
// Mesh tạo bởi TreeMeshBuilder: VERTEX = tâm thẻ, UV2 = góc thẻ (m), COLOR.r = AO, COLOR.g = biến thể.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D leaf_atlas : source_color, filter_nearest;

group_uniforms colors;
uniform vec3 color_dark : source_color = vec3(0.12, 0.26, 0.12);
uniform vec3 color_light : source_color = vec3(0.66, 0.84, 0.36);
uniform vec3 color_variation : source_color = vec3(0.75, 0.8, 0.35);
uniform float variation_amount : hint_range(0.0, 1.0) = 0.25;

group_uniforms lighting;
// Số bậc ánh sáng (càng ít càng "vẽ tay")
uniform float light_steps = 3.0;
uniform float wrap : hint_range(0.0, 1.0) = 0.35;
uniform vec3 translucency_color : source_color = vec3(0.55, 0.7, 0.2);
uniform float translucency : hint_range(0.0, 2.0) = 0.6;
// Độ đậm bóng đổ nhận được (lá che lá trong tán dày làm cả tán tối đều). 1 = đầy đủ, 0 = bỏ bóng.
uniform float self_shadow : hint_range(0.0, 1.0) = 0.45;
// Mặt lá khuất nắng/trăng vẫn nhận phần này (ánh dội từ trời) → tán không đen kịt, nhất là ban đêm.
uniform float shadow_fill : hint_range(0.0, 0.6) = 0.22;

group_uniforms wind;
uniform float wind_strength = 0.05;
uniform float wind_speed = 1.4;
group_uniforms;

void vertex() {
	vec3 center = VERTEX;
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 world_center = (MODEL_MATRIX * vec4(center, 1.0)).xyz;
	// Lá đung đưa: biên độ tăng theo độ cao, pha theo vị trí
	float phase = world_center.x * 0.7 + world_center.z * 0.5;
	vec3 sway = vec3(sin(TIME * wind_speed + phase), 0.0, cos(TIME * wind_speed * 0.8 + phase)) * wind_strength * center.y;
	vec3 world_offset = mat3(INV_VIEW_MATRIX) * vec3(UV2 * scale, 0.0) + sway;
	// Giả định scale ĐỀU (M = R·s): M⁻¹ = Mᵀ / s². Đúng cho GrassField (Basis(UP, θ).scaled(ONE*h))
	// và cây đặt tay (tree.tscn chỉ scale đều). Scale không đều → lá lệch; khi đó quay lại inverse().
	VERTEX = center + transpose(mat3(MODEL_MATRIX)) * world_offset / (scale * scale);
}

void fragment() {
	vec4 tex = texture(leaf_atlas, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 col = mix(color_dark, color_light, tex.r);
	col = mix(col, col * color_variation * 1.3, COLOR.g * variation_amount);
	ALBEDO = col * COLOR.r;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	// Chia bậc mềm: trộn bậc và mượt để không bị gắt
	w = mix(floor(w * light_steps + 0.5) / light_steps, w, 0.35);
	// Chỉ làm nhẹ bóng của nắng/trăng. Với đèn điểm, ATTENUATION còn chứa suy giảm theo khoảng cách –
	// làm nhẹ nó sẽ khiến ánh đèn bị cắt cụt ở mép tầm chiếu thành ô vuông (cluster của Forward+).
	float att = LIGHT_IS_DIRECTIONAL ? mix(1.0, ATTENUATION, self_shadow) : ATTENUATION;
	// Nắng/trăng: mặt khuất vẫn giữ tối thiểu shadow_fill. Đèn điểm: nhân suy giảm như thường.
	float diffuse = LIGHT_IS_DIRECTIONAL ? max(w * att, shadow_fill) : w * att;
	DIFFUSE_LIGHT += LIGHT_COLOR * diffuse / PI;
	// Ánh xuyên lá: nhìn ngược về phía nguồn sáng
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * clamp(-ndl + 0.5, 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * att * back * translucency * translucency_color / PI;
}
