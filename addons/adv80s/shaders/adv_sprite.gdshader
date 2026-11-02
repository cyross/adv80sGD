shader_type canvas_item;
// スプライトだけにかける効果（sprite.effect）。mode：0 なし、1 白黒、2 セピア、3 シルエット、4 モザイク
uniform int mode = 0;
uniform vec4 silhouette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float cells = 4.0;
varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	vec2 uv = UV;
	if (mode == 4) {
		vec2 px = TEXTURE_PIXEL_SIZE * max(cells, 1.0);
		uv = (floor(uv / px) + 0.5) * px;
	}
	vec4 c = texture(TEXTURE, uv);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	if (mode == 1) {
		c.rgb = vec3(g);
	} else if (mode == 2) {
		c.rgb = vec3(g * 1.07, g * 0.74, g * 0.43);
	} else if (mode == 3) {
		c.rgb = silhouette_color.rgb;
	}
	COLOR = c * vcol;
}
