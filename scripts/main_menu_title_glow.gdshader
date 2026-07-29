shader_type canvas_item;
render_mode blend_add;

uniform vec4 glow_color : source_color = vec4(0.98, 0.66, 0.24, 0.72);
uniform float radius : hint_range(2.0, 16.0, 0.5) = 9.0;

void fragment() {
	vec2 offset = TEXTURE_PIXEL_SIZE * radius;
	float halo = texture(TEXTURE, UV).a * 0.35;
	halo = max(halo, texture(TEXTURE, UV + vec2(offset.x, 0.0)).a);
	halo = max(halo, texture(TEXTURE, UV - vec2(offset.x, 0.0)).a);
	halo = max(halo, texture(TEXTURE, UV + vec2(0.0, offset.y)).a);
	halo = max(halo, texture(TEXTURE, UV - vec2(0.0, offset.y)).a);
	halo = max(halo, texture(TEXTURE, UV + offset).a);
	halo = max(halo, texture(TEXTURE, UV - offset).a);
	halo = max(halo, texture(TEXTURE, UV + vec2(offset.x, -offset.y)).a);
	halo = max(halo, texture(TEXTURE, UV + vec2(-offset.x, offset.y)).a);
	COLOR = vec4(glow_color.rgb, halo * glow_color.a);
}
