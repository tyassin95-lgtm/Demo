shader_type sky;
// Stylized sky (day or dusk palette): layered gradient, sun glow, stars, a ringed gas
// giant, cloud bands on the horizon and drifting puffy clouds. Fully procedural.

uniform vec3 zenith : source_color = vec3(0.04, 0.05, 0.16);
uniform vec3 mid : source_color = vec3(0.22, 0.12, 0.35);
uniform vec3 horizon : source_color = vec3(0.95, 0.42, 0.28);
uniform vec3 ground : source_color = vec3(0.03, 0.03, 0.07);
uniform vec3 sun_color : source_color = vec3(1.0, 0.6, 0.35);
uniform vec3 planet_dir = vec3(-0.55, 0.32, -0.77);
uniform vec3 planet_color : source_color = vec3(0.45, 0.55, 0.95);
uniform float star_density = 0.9;
uniform float planet_alpha = 1.0;
uniform vec3 cloud_color : source_color = vec3(1.24, 0.55, 0.44);
uniform float cloud_band = 0.45;
uniform float cloud_puffs = 0.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash13(vec3(i, 1.0));
	float b = hash13(vec3(i + vec2(1.0, 0.0), 1.0));
	float c = hash13(vec3(i + vec2(0.0, 1.0), 1.0));
	float d = hash13(vec3(i + vec2(1.0, 1.0), 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col;
	if (y > 0.0) {
		col = mix(horizon, mid, smoothstep(0.0, 0.25, y));
		col = mix(col, zenith, smoothstep(0.2, 0.75, y));
	} else {
		col = mix(horizon * 0.6, ground, smoothstep(0.0, 0.2, -y));
	}
	// Sun glow.
	vec3 sd = normalize(LIGHT0_DIRECTION);
	float sdot = max(dot(d, sd), 0.0);
	col += sun_color * (pow(sdot, 6.0) * 0.45 + pow(sdot, 90.0) * 1.6 + pow(sdot, 2000.0) * 8.0);
	// Stars.
	if (y > 0.05) {
		vec3 sp = d * 180.0;
		vec3 cell = floor(sp);
		float h = hash13(cell);
		if (h > 1.0 - 0.012 * star_density) {
			vec3 fc = fract(sp) - 0.5;
			float s = 1.0 - smoothstep(0.0, 0.18, length(fc));
			float tw = 0.6 + 0.4 * sin(TIME * (2.0 + h * 5.0) + h * 40.0);
			col += vec3(0.8, 0.9, 1.0) * s * tw * smoothstep(0.05, 0.4, y) * 1.5;
		}
	}
	// Cloud bands near the horizon.
	float band = noise2(vec2(atan(d.x, d.z) * 3.0 + TIME * 0.01, y * 18.0)) * noise2(vec2(atan(d.x, d.z) * 9.0 - TIME * 0.02, y * 40.0));
	float cl = smoothstep(0.25, 0.6, band) * smoothstep(0.35, 0.02, abs(y - 0.08));
	col = mix(col, cloud_color, cl * cloud_band);
	// Puffy clouds on a plane above (daytime).
	if (cloud_puffs > 0.0 && y > 0.02) {
		vec2 pp = d.xz / (y + 0.12) * 1.6 + vec2(TIME * 0.012, TIME * 0.004);
		float f = noise2(pp) * 0.55 + noise2(pp * 2.3 + 7.1) * 0.3 + noise2(pp * 5.1 + 3.3) * 0.15;
		float puff = smoothstep(0.52, 0.78, f) * smoothstep(0.02, 0.18, y) * (1.0 - smoothstep(0.55, 0.95, y));
		float shade2 = mix(0.78, 1.0, smoothstep(0.52, 0.9, f));
		col = mix(col, cloud_color * shade2, puff * cloud_puffs);
	}
	// Ringed planet.
	vec3 pd = normalize(planet_dir);
	float pdot = dot(d, pd);
	float pr = 0.16;
	float ang = acos(clamp(pdot, -1.0, 1.0));
	if (ang < pr) {
		vec3 local = d - pd * pdot;
		float shade = clamp(dot(normalize(local + pd * 0.02), -sd) * 0.5 + 0.55, 0.15, 1.0);
		float bands2 = 0.8 + 0.2 * sin(dot(local, vec3(0.3, 1.0, 0.2)) * 90.0);
		vec3 pc = planet_color * shade * bands2;
		float edge = smoothstep(pr, pr * 0.93, ang);
		col = mix(col, pc, edge * planet_alpha);
		col += planet_color * pow(1.0 - ang / pr, 0.5) * 0.05 * planet_alpha;
	}
	// Planet ring (a tilted thin ellipse).
	vec3 ring_n = normalize(vec3(0.25, 1.0, 0.35));
	vec3 rel = d - pd;
	float rd = abs(dot(rel, ring_n));
	float rr = length(rel - ring_n * dot(rel, ring_n));
	float ring = (1.0 - smoothstep(0.004, 0.012, rd)) * smoothstep(0.18, 0.2, rr) * (1.0 - smoothstep(0.29, 0.31, rr));
	if (!(ang < pr && dot(rel, ring_n) < 0.0)) {
		col += planet_color * ring * 0.7 * planet_alpha;
	}
	COLOR = col;
}
