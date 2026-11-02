// 自作フィルターの例：セピア。画面を読み直す canvas_item シェーダーとして書く。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform vec2 source_size = vec2(640.0, 400.0);  // フレームワークが設定する（元の解像度）
uniform float amount : hint_range(0.0, 1.0) = 0.8;
uniform vec4 tone : source_color = vec4(1.0, 0.85, 0.6, 1.0);

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, lum * tone.rgb, amount), 1.0);
}
