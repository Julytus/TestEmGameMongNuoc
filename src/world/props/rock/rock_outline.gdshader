// Viền tối kiểu pixel art cho đá (inverted hull): vẽ mặt sau, phình theo pháp tuyến một khoảng cố định
// theo pixel màn hình → nét viền đều ~1-2 px bất kể khoảng cách. Dùng làm next_pass của rock_material.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform vec3 outline_color : source_color = vec3(0.13, 0.12, 0.16);
uniform float outline_pixels = 1.5;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize(mat3(PROJECTION_MATRIX) * (mat3(MODELVIEW_MATRIX) * CUSTOM0.rgb));
	clip.xy += normalize(n.xy) / VIEWPORT_SIZE * outline_pixels * 2.0 * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color;
}
