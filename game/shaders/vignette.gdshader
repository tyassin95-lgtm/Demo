shader_type canvas_item;
// Screen-edge vignette used for damage flashes, low health pulses and overdrive.

uniform vec4 color : source_color = vec4(1.0, 0.1, 0.1, 1.0);
uniform float amount = 0.0;
uniform float softness = 0.55;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	uv.x *= 1.25;
	float d = length(uv);
	float v = smoothstep(1.35 - softness, 1.45, d);
	COLOR = vec4(color.rgb, color.a * v * amount);
}
