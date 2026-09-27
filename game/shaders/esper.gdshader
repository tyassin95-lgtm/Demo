shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Textured fighters (outfit, skin, hair, eyes): baked outfit albedo + mask
// (R glow, G roughness, B metallic, A clothes), normal map (flattened under clothes),
// team-coloured glow trims and a soft rim, plus the same hit flash / dissolve /
// overdrive / close-camera fade as the other character materials.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap;
uniform bool use_normal = true;
uniform bool use_mask = true;
uniform float normal_depth = 1.0;
// Normal map strength kept under clothes (the body normal map carries bare anatomy).
uniform float cloth_normal = 0.15;
// Multiplies the texture (hair and eyebrows are greyscale and take their colour here).
uniform vec3 tint : source_color = vec3(1.0);
uniform float tint_boost = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
uniform float specular = 0.5;
// Eyes: recolours the iris (a disc in the middle of the eye texture).
uniform bool is_eye = false;
uniform vec3 iris_color : source_color = vec3(0.2, 0.6, 1.0);
uniform vec3 glow_color : source_color = vec3(0.2, 0.9, 1.0);
uniform float glow_strength = 2.4;
uniform vec3 rim_color : source_color = vec3(0.6, 0.85, 1.0);
uniform float rim_strength = 0.25;
uniform float rim_power = 3.0;
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
	vec3 col = texture(albedo_tex, UV).rgb * tint * tint_boost;
	if (is_eye) {
		float r = length(UV - vec2(0.5, 0.5));
		float iris = 1.0 - smoothstep(0.095, 0.115, r);
		float pupil = 1.0 - smoothstep(0.035, 0.05, r);
		float lum = dot(col, vec3(0.333));
		vec3 ic = iris_color * (0.55 + 1.6 * lum) * mix(0.8, 1.25, smoothstep(0.03, 0.11, r));
		col = mix(col, ic, iris * (1.0 - pupil));
		col = mix(col, vec3(0.02), pupil * 0.85);
		col += vec3(1.0) * (1.0 - smoothstep(0.0, 0.02, length(UV - vec2(0.475, 0.465)))) * 0.8;
	}
	vec4 m = use_mask ? texture(mask_tex, UV) : vec4(0.0, roughness, 0.0, 0.0);
	col = mix(col, vec3(1.0), hit_flash * 0.85);
	col = mix(col, col * overdrive_color * 1.6, overdrive * 0.3);
	ALBEDO = col;
	ROUGHNESS = m.g;
	METALLIC = m.b;
	SPECULAR = specular;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth * mix(1.0, cloth_normal, m.a);
	}
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, rim_power);
	vec3 rim = mix(rim_color, overdrive_color, overdrive);
	EMISSION = glow_color * m.r * glow_strength * (1.0 + overdrive)
		+ rim * fres * (rim_strength + overdrive * 1.2)
		+ vec3(1.0, 0.95, 0.9) * hit_flash * 1.6
		+ dissolve_color * edge * 5.0;
}
