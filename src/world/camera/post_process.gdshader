// Hậu kỳ "ống kính" phong cách HD-2D: vignette, chromatic aberration nhẹ ở rìa, film grain.
// (DOF, bloom, tonemap, color grading đã do WorldEnvironment/CameraAttributes đảm nhiệm.)
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

group_uniforms vignette;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.45;
uniform float vignette_radius : hint_range(0.0, 1.5) = 0.85;
uniform float vignette_softness : hint_range(0.01, 1.5) = 0.6;
uniform vec3 vignette_color : source_color = vec3(0.04, 0.02, 0.08);

group_uniforms lens;
uniform float aberration : hint_range(0.0, 0.01) = 0.001;
uniform float grain : hint_range(0.0, 0.2) = 0.02;
group_uniforms;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - 0.5;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float dist = length(vec2(centered.x * aspect, centered.y));

	vec2 shift = centered * aberration * dist * 2.0;
	vec3 col;
	col.r = texture(screen_texture, uv + shift).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - shift).b;

	float vig = smoothstep(vignette_radius, vignette_radius - vignette_softness, dist);
	col = mix(vignette_color, col, mix(1.0, vig, vignette_strength));

	col += (hash(uv * 1000.0 + fract(TIME) * 100.0) - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}
