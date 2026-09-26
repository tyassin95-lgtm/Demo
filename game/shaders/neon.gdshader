shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
// Emissive neon strip with a slow travelling pulse.

uniform vec3 color : source_color = vec3(0.2, 0.9, 1.0);
uniform float intensity = 2.4;
uniform float pulse_speed = 1.5;
uniform float pulse_scale = 0.12;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float p = 0.75 + 0.25 * sin((wpos.x + wpos.z) * pulse_scale * 6.2831 - TIME * pulse_speed * 3.0);
	ALBEDO = COLOR.rgb * color * intensity * p;
}
