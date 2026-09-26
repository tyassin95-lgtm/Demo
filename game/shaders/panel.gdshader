shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// World-space procedural sci-fi panelling for arena geometry: tiled plates with
// bevelled seams, per-tile tint variation, occasional glowing inset lights and a
// detail texture sampled triplanar. Cheap enough for mobile GPUs.

uniform vec3 base_color : source_color = vec3(0.32, 0.35, 0.4);
uniform vec3 alt_color : source_color = vec3(0.24, 0.26, 0.31);
uniform vec3 seam_color : source_color = vec3(0.06, 0.07, 0.09);
uniform vec3 light_color : source_color = vec3(0.2, 0.85, 1.0);
uniform float tile_size = 2.0;
uniform float seam_width = 0.035;
uniform float light_density = 0.12;
uniform float light_strength = 2.2;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.42;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.35;
uniform sampler2D detail_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 0.25;
uniform float detail_strength = 0.35;
uniform float edge_glow = 0.0;

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
	// Pick the dominant axis plane for the panel grid.
	vec2 uv;
	if (n.y > n.x && n.y > n.z) {
		uv = wpos.xz;
	} else if (n.x > n.z) {
		uv = wpos.zy;
	} else {
		uv = wpos.xy;
	}
	vec2 g = uv / tile_size;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float h = hash12(cell);
	// Seams: distance to the tile edge.
	vec2 e = min(f, 1.0 - f) * tile_size;
	float edge = min(e.x, e.y);
	float seam = 1.0 - smoothstep(seam_width * 0.5, seam_width, edge);
	float bevel = 1.0 - smoothstep(seam_width, seam_width * 3.0, edge);
	// Sub-panel detail lines on some tiles.
	float sub = 0.0;
	if (h > 0.55) {
		float l = abs(f.x - 0.5) * tile_size;
		sub = 1.0 - smoothstep(0.01, 0.025, l);
	}
	vec3 col = mix(base_color, alt_color, step(0.7, h) * 0.8 + h * 0.2);
	// Triplanar detail texture for grit.
	vec3 w = pow(n, vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 dt = texture(detail_tex, wpos.zy * detail_scale).rgb * w.x
			+ texture(detail_tex, wpos.xz * detail_scale).rgb * w.y
			+ texture(detail_tex, wpos.xy * detail_scale).rgb * w.z;
	col *= mix(vec3(1.0), dt * 1.6, detail_strength);
	col = mix(col, seam_color, max(seam, sub * 0.6));
	col += bevel * (1.0 - seam) * 0.05;
	// Inset light strips on a few tiles.
	float lit = 0.0;
	if (h < light_density) {
		vec2 c = abs(f - 0.5);
		float strip = (1.0 - smoothstep(0.03, 0.045, c.y)) * (1.0 - smoothstep(0.3, 0.32, c.x));
		lit = strip;
	}
	ALBEDO = col;
	ROUGHNESS = mix(roughness_base, 0.8, seam) - h * 0.08;
	METALLIC = metallic_base;
	vec3 glow = light_color * lit * light_strength;
	glow += light_color * edge_glow * seam;
	EMISSION = glow;
}
