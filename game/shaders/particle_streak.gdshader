shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Velocity-aligned billboard for spark streaks. Requires particle_flag_align_y so the
// particle's Y axis follows its velocity; the quad then faces the camera around that axis.

uniform sampler2D tex : source_color, hint_default_white;
uniform float intensity = 2.0;
uniform float stretch = 1.0;
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 y_axis = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float sy = length(y_axis);
	y_axis = sy > 0.0001 ? y_axis / sy : vec3(0.0, 1.0, 0.0);
	vec3 x_axis = cross(y_axis, normalize(-center));
	float lx = length(x_axis);
	x_axis = lx > 0.0001 ? x_axis / lx : vec3(1.0, 0.0, 0.0);
	float sx = length((MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 p = center + x_axis * VERTEX.x * sx + y_axis * VERTEX.y * sy * stretch;
	POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = COLOR.rgb * tint * t.rgb * intensity * COLOR.a * t.a;
}
