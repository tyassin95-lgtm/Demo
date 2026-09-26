shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Vertical energy column (spawn / pickup beams): bright rim, fading upward, scrolling bands.

uniform vec3 color : source_color = vec3(0.3, 0.9, 1.0);
uniform float fade = 1.0;
uniform float intensity = 1.8;

void fragment() {
	float v = UV.y;
	float grad = pow(clamp(v, 0.0, 1.0), 1.6);
	float ndv = abs(dot(NORMAL, VIEW));
	float rim = pow(1.0 - ndv, 1.4);
	float bands = 0.7 + 0.3 * sin(v * 26.0 + TIME * 10.0);
	ALBEDO = color * (0.25 + rim * 1.8) * grad * bands * fade * intensity;
}
