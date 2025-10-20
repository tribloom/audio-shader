shader_type canvas_item;
render_mode unshaded;

uniform float aspect;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;

uniform float ring_density = 14.0;
uniform float base_width = 0.015;
uniform float drift = 0.15;

uniform float breathe_amp = 0.12;
uniform float breathe_speed = 0.35;


float band_avg(float a, float b){
	if (bar_count <= 1) return 0.0;
	int ia = int(floor(a * float(bar_count)));
	int ib = int(ceil(b * float(bar_count))) - 1;
	ia = clamp(ia, 0, bar_count - 1);
	ib = clamp(ib, 0, bar_count - 1);
	float s = 0.0;
	int n = max(1, ib - ia + 1);
	for (int i = ia; i <= ib; i++){
		float u = (float(i) + 0.5) / float(bar_count);
		s += texture(spectrum_tex, vec2(u, 0.25)).r;
	}
	return s / float(n);
}

vec3 hsv2rgb_local(vec3 c){
	vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	rgb = rgb * rgb * (3.0 - 2.0 * rgb);
	return c.z * mix(vec3(1.0), rgb, c.y);
}

void fragment(){
	vec2 q = SCREEN_UV;
	vec2 pp = -1.0 + 2.0 * q;
	vec2 uv = pp;
	uv.x *= aspect;

	// gentle global breathing (independent of audio)
	float breathe = 1.0 + breathe_amp * sin(TIME * breathe_speed);

	float t = TIME * drift;
	float r = length(uv);

	float rid_f = r * ring_density * breathe + t;
	float rid_frac = fract(rid_f);
	int ring_id = int(floor(max(rid_f, 0.0)));

	// map ring id -> spectrum bin and color
	float u = fract(float(ring_id) / max(ring_density, 1.0));
	float s = 0.0;
	if (audio_enabled) s = texture(spectrum_tex, vec2(u, 0.25)).r * audio_gain;
	float gate = smoothstep(0.08, 0.22, pow(clamp(s, 0.0, 1.0), 0.7));

	// width + brightness from audio (per ring)
	float w = mix(base_width, base_width * 2.0, gate);
	float d = abs(rid_frac - 0.5);
	float ring = smoothstep(w, 0.0, d) * smoothstep(1.2, 0.0, r);

	vec3 neon = hsv2rgb_local(vec3(u, 0.85, 1.0));
	vec3 col = mix(vec3(0.04, 0.05, 0.06), neon, ring);
	col += ring * (0.12 + 0.35 * gate);

	COLOR = vec4(col, 1.0);
}
