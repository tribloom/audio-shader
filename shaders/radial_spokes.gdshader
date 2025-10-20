shader_type canvas_item;
render_mode unshaded;

uniform float aspect;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;

uniform int spokes = 64;
uniform float base_thickness = 0.006;
uniform float spin = 0.25;

uniform float spokes_audio_level = 1.0;
uniform float spokes_gate_lo = 0.08;
uniform float spokes_gate_hi = 0.22;
uniform float spokes_thicken = 2.6;
uniform float spokes_glow = 0.40;

mat2 rot(float a){
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c,s), vec2(-s,c));
}
float band_max(float a, float b){
	if (bar_count <= 0) return 0.0;
	int ia = int(floor(a * float(bar_count)));
	int ib = int(ceil(b * float(bar_count))) - 1;
	ia = clamp(ia, 0, bar_count - 1);
	ib = clamp(ib, 0, bar_count - 1);
	float m = 0.0;
	for (int i=ia;i<=ib;i++){
		float u = (float(i) + 0.5) / float(bar_count);
		m = max(m, texture(spectrum_tex, vec2(u, 0.25)).r);
	}
	return m;
}

void fragment(){
	vec2 q = SCREEN_UV;
	vec2 pp = -1.0 + 2.0 * q;
	vec2 uv = pp;
	uv.x *= aspect;

	float seg = TAU / float(max(spokes, 1));
	float A = atan(uv.y, uv.x) + TIME * spin;
	float r = length(uv);

	float kf = floor((A / TAU + 0.5) * float(spokes));
	float u_spoke = (kf + 0.5) / float(max(spokes, 1));

	float s_spoke = 0.0;
	float s_avg = 0.0;
	if (audio_enabled){
		const int N = 8;
		float sum = 0.0;
		for (int j = -N; j <= N; j++){
			float idx = kf + float(j);
			float u = (idx + 0.5) / float(max(spokes, 1));
			sum += texture(spectrum_tex, vec2(fract(u), 0.25)).r;
		}
		s_avg = sum / float(2 * N + 1);
		s_spoke = texture(spectrum_tex, vec2(u_spoke, 0.25)).r;
	}

	float rel = max(0.0, (s_spoke - s_avg) * audio_gain * spokes_audio_level);
	float gate = smoothstep(spokes_gate_lo, spokes_gate_hi, pow(clamp(rel, 0.0, 1.0), 0.7));

	float da = abs(mod(A + 0.5 * seg, seg) - 0.5 * seg);
	float d = da * r;

	float thick = mix(base_thickness, base_thickness * spokes_thicken, gate);
	float line = smoothstep(thick, 0.0, d) * smoothstep(1.1, 0.0, r);

	vec3 col = mix(vec3(0.02), vec3(0.9, 0.95, 1.0), line);
	col += line * gate * spokes_glow;

	COLOR = vec4(col, 1.0);
}
