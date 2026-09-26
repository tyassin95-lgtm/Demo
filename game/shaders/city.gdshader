shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled, shadows_disabled;
// Distant city blocks: dark facades with procedural lit windows and roof beacons.

uniform vec3 facade : source_color = vec3(0.05, 0.06, 0.09);
uniform vec3 window_a : source_color = vec3(1.0, 0.7, 0.4);
uniform vec3 window_b : source_color = vec3(0.3, 0.8, 1.0);
uniform float window_strength = 1.6;

varying vec3 wpos;
varying vec3 wnrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(wnrm);
	vec3 col = facade;
	vec3 em = vec3(0.0);
	if (n.y < 0.5) {
		vec2 uv = (n.x > n.z ? wpos.zy : wpos.xy) * vec2(0.55, 0.45);
		vec2 cell = floor(uv);
		vec2 f = fract(uv);
		float h = hash12(cell + floor(wpos.xz * 0.01) * 17.0);
		float win = step(0.25, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.7);
		float on = step(0.62, h);
		vec3 wc = mix(window_a, window_b, step(0.85, h));
		em = wc * win * on * window_strength * (0.6 + 0.4 * hash12(cell * 1.3));
	}
	ALBEDO = col;
	ROUGHNESS = 0.8;
	EMISSION = em;
}
