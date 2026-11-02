// adv80s 画面効果（7.4）のうち、画面全体を読み直して描くもの：invert、tint、raster。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform int mode = 0;            // 0 invert、1 tint、2 raster
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint_color : source_color = vec4(0.7, 0.55, 0.35, 1.0);
uniform vec2 screen_px = vec2(640.0, 400.0);
uniform float amplitude = 4.0;   // raster：横にずらす量（ピクセル）
uniform float wavelength = 32.0; // raster：波の長さ（行）
uniform float phase = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	if (mode == 2) {
		float line = floor(uv.y * screen_px.y);
		uv.x += sin(line / wavelength * 6.2831853 + phase) * amplitude * amount / screen_px.x;
	}
	vec4 c = texture(screen_texture, uv);
	if (mode == 0) {
		c.rgb = mix(c.rgb, vec3(1.0) - c.rgb, amount);
	} else if (mode == 1) {
		float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		c.rgb = mix(c.rgb, lum * tint_color.rgb * 1.4, amount * tint_color.a);
	}
	COLOR = vec4(c.rgb, 1.0);
}
