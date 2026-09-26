shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Jump pad: concentric rings pulsing outward plus an upward chevron glow.

uniform vec3 color : source_color = vec3(0.3, 1.0, 0.6);
uniform float intensity = 2.0;
uniform float boost = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float rings = smoothstep(0.75, 1.0, sin((r * 5.0 - TIME * 2.2) * 6.2831) * 0.5 + 0.5);
	float rim = smoothstep(0.84, 0.94, r) * (1.0 - smoothstep(0.96, 1.0, r));
	float core = 1.0 - smoothstep(0.0, 0.35, r);
	float a = rings * (1.0 - r) * 0.8 + rim * 1.2 + core * 0.5;
	ALBEDO = color * intensity * a * (1.0 + boost * 2.0);
}
