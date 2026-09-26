shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Sweeping crescent for melee swings. UV.x runs along the arc, UV.y from inner to outer edge.

uniform vec3 color : source_color = vec3(0.2, 0.9, 1.0);
uniform float progress = 0.0;
uniform float intensity = 2.4;

void fragment() {
	float head = progress * 1.4 - 0.1;
	float behind = head - UV.x;
	float body = smoothstep(-0.02, 0.06, behind) * (1.0 - smoothstep(0.25, 0.7, behind));
	float radial = smoothstep(0.0, 0.45, UV.y) * (0.25 + 0.75 * pow(UV.y, 2.5));
	float edge = pow(UV.y, 10.0);
	float fade = 1.0 - smoothstep(0.65, 1.0, progress);
	vec3 c = mix(color, vec3(1.0), edge * 0.85 + 0.15);
	ALBEDO = c * intensity * body * radial * fade;
}
