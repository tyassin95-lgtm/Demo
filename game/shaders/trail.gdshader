shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Weapon swing ribbon. UV.x = age along the trail (0 newest), UV.y = hilt(0) -> tip(1).

uniform vec3 color : source_color = vec3(0.2, 0.9, 1.0);
uniform float intensity = 2.2;

void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float across = clamp(UV.y, 0.0, 1.0);
	float fade = pow(1.0 - age, 1.8);
	float edge = smoothstep(0.0, 0.3, across) * (0.3 + 0.7 * smoothstep(0.35, 1.0, across));
	float streak = 0.8 + 0.2 * sin(across * 38.0 + age * 9.0);
	vec3 c = mix(color, vec3(1.0), pow(across, 5.0) * (1.0 - age));
	ALBEDO = c * intensity * fade * edge * streak * COLOR.a;
}
