shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Stylized armor for the mannequin rig: glossy base + fresnel rim + emissive,
// with hit flash and a noise dissolve used for spawn/death effects.

uniform vec3 base_color : source_color = vec3(0.85, 0.87, 0.9);
uniform float metallic : hint_range(0.0, 1.0) = 0.3;
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform vec3 rim_color : source_color = vec3(0.2, 0.9, 1.0);
uniform float rim_strength = 1.0;
uniform float rim_power = 3.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_strength = 0.0;
uniform float stripe_strength = 0.0;
uniform vec3 stripe_color : source_color = vec3(0.2, 0.9, 1.0);
uniform float hit_flash = 0.0;
uniform float dissolve = 0.0;
uniform vec3 dissolve_color : source_color = vec3(0.3, 0.9, 1.0);
uniform float overdrive = 0.0;
uniform float dither_fade = 0.0;
uniform vec3 overdrive_color : source_color = vec3(1.0, 0.45, 0.1);

varying vec3 obj_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
				   mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
				   mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	if (dither_fade > 0.001) {
		// 4x4 ordered dither (screen-door transparency keeps the opaque pipeline).
		ivec2 q = ivec2(FRAGCOORD.xy) % 4;
		int idx = q.x + q.y * 4;
		float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		if ((bayer[idx] + 0.5) / 16.0 < dither_fade) {
			discard;
		}
	}
	float edge = 0.0;
	if (dissolve > 0.001) {
		float n = vnoise(obj_pos * 8.0) * 0.65 + vnoise(obj_pos * 21.0) * 0.35;
		float d = n - dissolve * 1.05;
		if (d < 0.0) {
			discard;
		}
		edge = 1.0 - smoothstep(0.0, 0.07, d);
	}
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, rim_power);
	// Horizontal energy stripes that scroll slowly (armour "circuitry").
	float stripe = 0.0;
	if (stripe_strength > 0.0) {
		float s = fract(obj_pos.y * 7.0 - TIME * 0.25);
		stripe = smoothstep(0.46, 0.5, s) * (1.0 - smoothstep(0.5, 0.54, s));
	}
	vec3 col = mix(base_color, vec3(1.0), hit_flash * 0.85);
	col = mix(col, col * overdrive_color * 1.6, overdrive * 0.35);
	ALBEDO = col;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	vec3 rim = mix(rim_color, overdrive_color, overdrive);
	EMISSION = emission_color * emission_strength
		+ rim * fres * (rim_strength + overdrive * 1.5)
		+ stripe_color * stripe * stripe_strength
		+ vec3(1.0, 0.95, 0.9) * hit_flash * 1.6
		+ dissolve_color * edge * 5.0;
}
