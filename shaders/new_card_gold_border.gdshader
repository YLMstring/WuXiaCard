shader_type canvas_item;
render_mode unshaded;

uniform vec4 gold_base : source_color = vec4(0.76, 0.43, 0.07, 1.0);
uniform vec4 gold_highlight : source_color = vec4(1.0, 0.94, 0.55, 1.0);
uniform float border_width : hint_range(0.01, 0.12) = 0.055;
uniform float corner_radius : hint_range(0.01, 0.20) = 0.085;
uniform float flow_speed : hint_range(0.01, 0.50) = 0.10;
uniform float highlight_width : hint_range(0.02, 0.30) = 0.13;


float rounded_box_distance(vec2 point, vec2 half_size, float radius) {
	vec2 q = abs(point) - half_size + vec2(radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}


float perimeter_coordinate(vec2 uv) {
	float top_distance = uv.y;
	float right_distance = 1.0 - uv.x;
	float bottom_distance = 1.0 - uv.y;
	float left_distance = uv.x;
	if (
		top_distance <= right_distance
		&& top_distance <= bottom_distance
		&& top_distance <= left_distance
	) {
		return uv.x * 0.25;
	}
	if (right_distance <= bottom_distance && right_distance <= left_distance) {
		return 0.25 + uv.y * 0.25;
	}
	if (bottom_distance <= left_distance) {
		return 0.50 + (1.0 - uv.x) * 0.25;
	}
	return 0.75 + (1.0 - uv.y) * 0.25;
}


void fragment() {
	vec2 point = UV - vec2(0.5);
	float antialias_width = max(fwidth(UV.x), fwidth(UV.y)) * 1.5;
	float outer_distance = rounded_box_distance(
		point,
		vec2(0.5),
		corner_radius
	);
	float inner_radius = max(0.01, corner_radius - border_width);
	float inner_distance = rounded_box_distance(
		point,
		vec2(0.5 - border_width),
		inner_radius
	);
	float outer_mask = 1.0 - smoothstep(
		-antialias_width,
		antialias_width,
		outer_distance
	);
	float inner_mask = 1.0 - smoothstep(
		-antialias_width,
		antialias_width,
		inner_distance
	);
	float border_mask = max(0.0, outer_mask - inner_mask);

	float phase = fract(perimeter_coordinate(UV) - TIME * flow_speed);
	float wrapped_phase = min(phase, 1.0 - phase);
	float highlight = 1.0 - smoothstep(0.0, highlight_width, wrapped_phase);
	highlight = pow(highlight, 1.35);
	vec4 gold = mix(gold_base, gold_highlight, highlight);
	COLOR = vec4(gold.rgb, border_mask * mix(0.88, 1.0, highlight));
}
