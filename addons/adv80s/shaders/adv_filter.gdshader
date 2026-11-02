// adv80s 標準フィルター（7.2）。元の解像度の画面を拡大して表示するときに、1回の描画でまとめてかける。
// 順番：曲面 → 減色・ディザ（元の1ピクセル単位） → にじみ → 走査線（元の1行単位） → 液晶の網目 → 単色 → RGBマスク → 周辺の暗さ
shader_type canvas_item;
render_mode unshaded;

uniform vec2 source_size = vec2(640.0, 400.0);  // 元の解像度
uniform bool enabled = true;                    // false ならそのまま表示（フィルターの無効化）

uniform int palette_size = 0;                   // 減色：パレットの色数（0 なら使わない）
uniform vec4 palette[64];
uniform vec3 levels = vec3(0.0);                // 減色：チャンネルごとの段階数-1（例：3ビットなら 7）。0 なら使わない
uniform float dither : hint_range(0.0, 1.0) = 0.0;
uniform float bleed : hint_range(0.0, 1.0) = 0.0;
uniform float scanline : hint_range(0.0, 1.0) = 0.0;
uniform float lcd : hint_range(0.0, 0.5) = 0.0;
uniform int mono = 0;                           // 0 なし、1 グリーン、2 アンバー、3 白
uniform float rgb_mask : hint_range(0.0, 1.0) = 0.0;
uniform float curvature : hint_range(0.0, 0.2) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	return (BAYER[x + y * 4] + 0.5) / 16.0 - 0.5;
}

vec3 quantize(vec3 c, vec2 px) {
	float d = dither * bayer4(px);
	if (palette_size > 0) {
		vec3 q = clamp(c + vec3(d) * 0.35, 0.0, 1.0);
		float best = 1e9;
		vec3 out_c = c;
		for (int i = 0; i < 64; i++) {
			if (i >= palette_size) {
				break;
			}
			vec3 p = palette[i].rgb;
			vec3 diff = (q - p) * vec3(0.30, 0.59, 0.11);
			float dist = dot(diff, diff) + dot(q - p, q - p) * 0.1;
			if (dist < best) {
				best = dist;
				out_c = p;
			}
		}
		return out_c;
	}
	if (levels.x > 0.0) {
		return clamp(floor(c * levels + 0.5 + vec3(d)) / levels, 0.0, 1.0);
	}
	return c;
}

vec3 fetch(sampler2D tex, vec2 px) {
	vec2 p = clamp(px, vec2(0.0), source_size - 1.0);
	return quantize(texture(tex, (p + 0.5) / source_size).rgb, p);
}

void fragment() {
	if (!enabled) {
		COLOR = texture(TEXTURE, UV);
	} else {
		vec2 uv = UV;
		bool outside = false;
		if (curvature > 0.0) {
			vec2 cc = uv * 2.0 - 1.0;
			vec2 off = abs(cc.yx) * curvature * 3.0;
			cc = cc + cc * off * off;
			uv = cc * 0.5 + 0.5;
			outside = uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0;
		}
		vec2 src = uv * source_size;
		vec2 px = floor(src);
		vec3 c = fetch(TEXTURE, px);
		if (bleed > 0.0) {
			vec3 l = fetch(TEXTURE, px - vec2(1.0, 0.0));
			vec3 r = fetch(TEXTURE, px + vec2(1.0, 0.0));
			c = mix(c, (l + c * 2.0 + r) * 0.25, bleed);
		}
		vec2 f = fract(src);
		if (scanline > 0.0) {
			c *= 1.0 - scanline * smoothstep(0.45, 0.6, f.y);
		}
		if (lcd > 0.0 && (f.x < lcd || f.y < lcd)) {
			c *= 0.7;
		}
		if (mono > 0) {
			float lum = dot(c, vec3(0.299, 0.587, 0.114));
			vec3 tint = mono == 1 ? vec3(0.2, 1.0, 0.3) : (mono == 2 ? vec3(1.0, 0.7, 0.15) : vec3(1.0));
			c = lum * tint;
		}
		if (rgb_mask > 0.0) {
			int col = int(mod(FRAGCOORD.x, 3.0));
			vec3 m = col == 0 ? vec3(1.0, 1.0 - rgb_mask, 1.0 - rgb_mask)
				: (col == 1 ? vec3(1.0 - rgb_mask, 1.0, 1.0 - rgb_mask) : vec3(1.0 - rgb_mask, 1.0 - rgb_mask, 1.0));
			c *= m * (1.0 + rgb_mask * 0.5);
		}
		if (vignette > 0.0) {
			vec2 v = uv - 0.5;
			c *= clamp(1.0 - dot(v, v) * vignette * 2.5, 0.0, 1.0);
		}
		COLOR = outside ? vec4(0.0, 0.0, 0.0, 1.0) : vec4(c, 1.0);
	}
}
