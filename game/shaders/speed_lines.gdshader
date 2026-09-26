shader_type canvas_item;
// Radial speed streaks toward the screen edges (sprint, dash, jump pads).

uniform float amount = 0.0;
uniform vec4 color : source_color = vec4(0.75, 0.95, 1.0, 1.0);

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x *= 1.7;
	float ang = atan(p.y, p.x);
	float r = length(p);
	float slices = 90.0;
	float id = floor((ang + 3.14159) / 6.28318 * slices);
	float h = hash(id);
	float speed = 1.5 + h * 2.0;
	float t = fract(TIME * speed + h * 7.0);
	float streak_pos = mix(0.55, 1.9, t);
	float len = 0.25 + h * 0.35;
	float s = smoothstep(streak_pos - len, streak_pos, r) * (1.0 - smoothstep(streak_pos, streak_pos + 0.02, r));
	float w = fract((ang + 3.14159) / 6.28318 * slices);
	float thin = smoothstep(0.0, 0.2, w) * (1.0 - smoothstep(0.35, 0.55, w));
	float mask = smoothstep(0.45, 1.0, r) * step(0.55, h);
	COLOR = vec4(color.rgb, s * thin * mask * amount * color.a);
}
