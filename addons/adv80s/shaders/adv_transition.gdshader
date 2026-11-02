// adv80s 切り替え演出（7.4）。画像の層の中身（CanvasGroup）にかけ、progress（0→1）で新しい画像を現す。
// invert が true のときは、消えていく側（image.hide や mosaic の前半）として使う。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform bool invert = false;
// 0 fade, 1 wipe, 2 blinds, 3 line_draw, 4 interlace, 5 plane_draw, 6 mosaic, 7 dissolve, 8 blocks, 9 iris, 10 mask
uniform int mode = 0;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);   // 画像の層の範囲（画面全体に対する割合）
uniform vec2 region_px = vec2(640.0, 400.0);      // 画像の層の大きさ（元の解像度のピクセル）
uniform int direction = 0;                         // 0 左→右（下へ）、1 右→左（上へ）、2 上→下、3 下→上
uniform float softness = 0.0;
uniform float count = 8.0;                         // blinds の本数
uniform float block_size = 16.0;                   // blocks の大きさ、mosaic の最大の大きさ
uniform int pattern = 0;                           // dissolve：0 ディザ模様、1 乱数。blocks：0 乱数、1 順番
uniform vec2 center = vec2(0.5, 0.5);
uniform vec3 plane_order = vec3(0.0, 1.0, 2.0);    // plane_draw：赤・緑・青の面が現れる順番（0、1、2）
uniform sampler2D rule_texture : filter_linear;    // mask：ルール画像

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float edge(float x, float p) {
	if (softness <= 0.0) {
		return x < p ? 1.0 : 0.0;
	}
	float pp = p * (1.0 + softness);
	return clamp((pp - x) / softness, 0.0, 1.0);
}

float axis(vec2 local) {
	if (direction == 1) return 1.0 - local.x;
	if (direction == 2) return local.y;
	if (direction == 3) return 1.0 - local.y;
	return local.x;
}

void fragment() {
	vec2 local = (SCREEN_UV - region.xy) / region.zw;
	vec2 suv = SCREEN_UV;
	vec4 c;
	float vis = 1.0;
	vec2 px = floor(local * region_px);
	float p = progress;

	if (mode == 6) {
		// mosaic：粗さを progress に合わせる（invert 側は粗くなっていき、新しい側は細かくなっていく）
		float s = max(1.0, floor(block_size * (invert ? p : 1.0 - p)) + 1.0);
		vec2 q = (floor(px / s) * s + s * 0.5) / region_px;
		suv = region.xy + q * region.zw;
		c = texture(screen_texture, suv);
		COLOR = c;
	} else {
		c = texture(screen_texture, suv);
		if (mode == 0) {
			vis = p;
		} else if (mode == 1) {
			vis = edge(axis(local), p);
		} else if (mode == 2) {
			float a = (direction >= 2) ? local.y : local.x;
			vis = edge(fract(a * count), p);
		} else if (mode == 3) {
			// 上から1行ずつ（direction が 3 なら下から）
			float line = direction == 3 ? (region_px.y - 1.0 - px.y) : px.y;
			vis = line < floor(p * region_px.y + 0.0001) ? 1.0 : 0.0;
		} else if (mode == 4) {
			float l = px.y / region_px.y;
			bool even = mod(px.y, 2.0) < 1.0;
			vis = even ? (l < p * 2.0 ? 1.0 : 0.0) : (l < p * 2.0 - 1.0 ? 1.0 : 0.0);
		} else if (mode == 5) {
			vec3 shown = vec3(
				p * 3.0 > plane_order.x ? 1.0 : 0.0,
				p * 3.0 > plane_order.y ? 1.0 : 0.0,
				p * 3.0 > plane_order.z ? 1.0 : 0.0);
			c.rgb *= shown;
			vis = p > 0.0 ? 1.0 : 0.0;
		} else if (mode == 7) {
			float t = pattern == 0 ? (BAYER[int(mod(px.x, 4.0)) + int(mod(px.y, 4.0)) * 4] + 0.5) / 16.0 : hash(px);
			vis = t < p ? 1.0 : 0.0;
		} else if (mode == 8) {
			vec2 b = floor(px / block_size);
			vec2 nb = ceil(region_px / block_size);
			float t = pattern == 0 ? hash(b + 0.37) : (b.y * nb.x + b.x) / (nb.x * nb.y);
			vis = t < p ? 1.0 : 0.0;
		} else if (mode == 9) {
			vec2 d = (local - center) * region_px;
			float maxd = length(max(center, 1.0 - center) * region_px);
			vis = edge(length(d) / maxd, p);
		} else if (mode == 10) {
			float r = texture(rule_texture, local).r;
			vis = edge(r, p);
		}
		if (invert) {
			vis = 1.0 - vis;
		}
		COLOR = vec4(c.rgb, c.a * vis);
	}
}
