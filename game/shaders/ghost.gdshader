shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
// Dash afterimage: fresnel-lit hologram silhouette.

uniform vec3 color : source_color = vec3(0.2, 0.8, 1.0);
uniform float alpha = 0.6;

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	float scan = 0.85 + 0.15 * sin(FRAGCOORD.y * 0.9);
	ALBEDO = color * (0.12 + fres * 1.6) * alpha * scan;
}
