// Phản chiếu nhân vật trên mặt nước (WaterReflection): quad billboard trục Y, lật ngược xuống dưới mặt nước,
// đọc đúng khung sprite hiện tại của người chơi (region trong sheet). Thay SSR (đắt, gần như không thấy trên nước stylized).
// - Cắt theo water field tại giao điểm tia nhìn với mặt đất (cùng cách water.gdshader cắt mép) → không tràn lên bờ.
// - DEPTH = độ sâu của MẶT NƯỚC tại pixel đó → vẽ đè lên nước (nước đặc, ghi depth) nhưng vẫn bị cây / vật phía trước che.
// Rẻ: một quad nhỏ, 2 lần đọc texture; chạy cả ở Low.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/world/terrain/terrain_common.gdshaderinc"

uniform sampler2D sprite_sheet : source_color, filter_nearest;
// Vùng khung hiện tại trong sheet (chuẩn hóa): xy = góc, zw = kích thước.
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool flip_h = false;
uniform vec4 modulate : source_color = vec4(1.0);
uniform vec3 water_color : source_color = vec3(0.16, 0.42, 0.52);
uniform float water_mix : hint_range(0.0, 1.0) = 0.4;
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
// Độ cao mặt nước (m) và mặt đất (m, nơi mặt nạ nước được đánh giá – khớp ground_offset của water.gdshader).
uniform float water_height = -0.06;
uniform float ground_height = 0.0;
// Lệch ngang tối đa (pixel sprite) của các hàng – gợn nhẹ theo thời gian.
uniform float wobble_pixels = 1.0;
uniform float wobble_speed = 4.0;

varying vec3 world_pos;

void vertex() {
	// Billboard khóa trục Y (giống sprite người chơi), giữ scale của node.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
			MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	world_pos = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 ray = world_pos - cam;
	// Mặt nạ: điểm mặt đất mà pixel này nhìn qua phải là nước.
	vec3 on_ground = cam + ray * ((ground_height - cam.y) / min(ray.y, -1e-4));
	if (!is_water_at(terrain_snap(on_ground.xz))) {
		discard;
	}
	vec2 frame_px = frame_rect.zw * vec2(textureSize(sprite_sheet, 0));
	// Quad: UV.y = 0 ở mép trên (chân), 1 ở dưới (đầu khi lật) → v sprite = 1 - UV.y.
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float row = floor(uv.y * frame_px.y);
	uv.x += round(sin(row * 1.7 + TIME * wobble_speed) * wobble_pixels) / frame_px.x;
	if (flip_h) {
		uv.x = 1.0 - uv.x;
	}
	if (uv.x < 0.0 || uv.x > 1.0) {
		discard;
	}
	vec4 tex = texture(sprite_sheet, frame_rect.xy + uv * frame_rect.zw);
	if (tex.a < 0.5) {
		discard;
	}
	ALBEDO = mix(tex.rgb, water_color, water_mix) * modulate.rgb;
	ALPHA = opacity * modulate.a;
	// Độ sâu = mặt nước tại pixel (nhích 0,1 % về phía camera) → nổi trên nước, vẫn bị vật phía trước che.
	vec3 on_water = cam + ray * ((water_height - cam.y) / min(ray.y, -1e-4)) * 0.999;
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(on_water, 1.0);
	DEPTH = clip.z / clip.w;
}
