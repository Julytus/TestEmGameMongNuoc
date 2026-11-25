// Logic gió + rẽ cỏ dùng chung cho cỏ, hoa, bụi cây... (#include vào shader spatial có world_vertex_coords)

global uniform vec3 player_position;
// Mức Low: cỏ/hoa co về 0 trong FOLIAGE_FADE_LENGTH m cuối trước khoảng cách này (m, tới camera); 0 = tắt.
// Settings đặt kèm visibility_range_end của GrassField để ô cỏ đã co hết mới bị cắt (không thấy mép).
global uniform float foliage_fade_end;
const float FOLIAGE_FADE_LENGTH = 5.0;

group_uniforms wind;
uniform sampler2D wind_noise : filter_linear, repeat_enable;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_strength : hint_range(0.0, 2.0) = 0.35;
uniform float wind_speed = 0.06;
uniform float wind_scale = 0.05;
uniform float sway_amount : hint_range(0.0, 0.5) = 0.05;
uniform float sway_speed = 2.2;

group_uniforms interaction;
uniform float push_radius = 0.9;
uniform float push_strength = 0.55;
group_uniforms;

// root: vị trí gốc (world), height: 0 gốc → 1 ngọn, rand: số ngẫu nhiên riêng mỗi instance.
// Trả về độ dời (world); gust nhận cường độ gió để tô sáng đợt gió.
vec3 foliage_offset(vec3 root, float height, float rand, float time, out float gust) {
	float bend = height * height;
	vec2 dir = normalize(wind_direction);
	vec2 noise_uv = root.xz * wind_scale - dir * time * wind_speed;
	gust = textureLod(wind_noise, noise_uv, 0.0).r;
	float sway = sin(time * sway_speed + rand * 6.2831 + root.x * 0.7) * sway_amount;
	vec3 offset = vec3(dir.x, 0.0, dir.y) * (gust * wind_strength + sway) * bend;

	vec2 away = root.xz - player_position.xz;
	float dist = length(away);
	float push = (1.0 - smoothstep(0.0, push_radius, dist)) * push_strength * bend;
	offset.xz += (away / max(dist, 0.001)) * push;

	// Hạ ngọn khi bị uốn để không bị kéo dài
	offset.y -= length(offset.xz) * 0.5 * height;
	return offset;
}


// Hệ số co (1 → 0) theo khoảng cách gốc → camera; nhân vào độ dời đỉnh so với gốc.
float foliage_distance_fade(vec3 root, vec3 camera_position) {
	if (foliage_fade_end <= 0.0) {
		return 1.0;
	}
	return 1.0 - smoothstep(foliage_fade_end - FOLIAGE_FADE_LENGTH, foliage_fade_end, distance(root, camera_position));
}
