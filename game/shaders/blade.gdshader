shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Energy blade: white-hot core fading to a coloured edge, with a subtle flicker.

uniform vec3 color : source_color = vec3(0.2, 0.9, 1.0);
uniform float intensity = 2.6;
uniform float core_width = 0.45;
uniform float power = 1.0;

void fragment() {
	float ndv = abs(dot(NORMAL, VIEW));
	float core = smoothstep(1.0 - core_width, 1.0, ndv);
	float flicker = 0.92 + 0.08 * sin(TIME * 57.0) * sin(TIME * 13.0);
	vec3 c = mix(color * (0.35 + 0.65 * ndv), vec3(1.0), core);
	ALBEDO = c * intensity * flicker * power;
}
