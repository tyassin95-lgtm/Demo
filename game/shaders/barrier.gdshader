shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// Translucent energy barrier with hex cells, rising scanlines and fresnel.

uniform vec3 color : source_color = vec3(0.25, 0.7, 1.0);
uniform float intensity = 0.55;

varying vec3 wpos;

float hex_dist(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.73))), p.x);
}

vec4 hex_coords(vec2 uv) {
	vec2 r = vec2(1.0, 1.73);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	vec2 id = uv - gv;
	return vec4(gv, id);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2(wpos.x + wpos.z, wpos.y) * 0.9;
	vec4 hc = hex_coords(uv);
	float d = hex_dist(hc.xy);
	float edge = smoothstep(0.42, 0.5, d);
	float flick = 0.5 + 0.5 * sin(TIME * 2.0 + hc.z * 3.1 + hc.w * 1.7);
	float scan = smoothstep(0.0, 0.1, fract(wpos.y * 0.15 - TIME * 0.25)) * (1.0 - smoothstep(0.1, 0.2, fract(wpos.y * 0.15 - TIME * 0.25)));
	float ndv = abs(dot(NORMAL, VIEW));
	float fres = pow(1.0 - ndv, 2.0);
	float h = clamp(1.0 - (wpos.y - 3.5) / 7.0, 0.0, 1.0);
	float a = (edge * (0.4 + 0.6 * flick) * 0.6 + scan * 0.5 + fres * 0.5) * h;
	ALBEDO = color * a * intensity;
}
