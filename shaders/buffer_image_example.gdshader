shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D buffer_a_tex;
uniform sampler2D spectrum_tex;
uniform vec2 buffer_a_size = vec2(1920.0, 1080.0);
uniform float vignette_power = 1.6;
uniform float spectrum_mix = 0.45;

vec3 palette(float x) {
	vec3 c1 = vec3(0.1, 0.2, 0.7);
	vec3 c2 = vec3(0.9, 0.35, 0.15);
	vec3 c3 = vec3(0.9, 0.95, 0.8);
	float m = smoothstep(0.0, 1.0, x);
	return mix(mix(c1, c2, m), c3, m * 0.5);
}

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv * 2.0 - 1.0;
	float vignette = pow(clamp(1.0 - length(centered), 0.0, 1.0), vignette_power);

	vec3 buffer_color = texture(buffer_a_tex, uv).rgb;
	float spectrum_value = texture(spectrum_tex, vec2(clamp(uv.x, 0.0, 1.0), 0.0)).r;
	vec3 overlay = palette(spectrum_value) * spectrum_value * spectrum_mix;

	vec3 color = mix(overlay, buffer_color, vignette);
	COLOR = vec4(color, 1.0);
}
