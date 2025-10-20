shader_type canvas_item;
render_mode unshaded;

uniform float aspect;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;

uniform float base_amp = 0.35;
uniform float freq = 8.0;
uniform float drift = 0.12;

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

void fragment(){
	vec2 q = SCREEN_UV;
	vec2 pp = -1.0 + 2.0 * q;
	vec2 uv = pp;
	uv.x *= aspect;



float amp = base_amp;
float fmul = 1.0;
float v = 0.0;
if (audio_enabled){
	v = texture(spectrum_tex, vec2(0.12, 0.25)).r * audio_gain; // bass focus
	float gate = smoothstep(0.06, 0.18, pow(clamp(v,0.0,1.0), 0.7));
	amp = base_amp + 0.45 * gate;
	fmul = mix(1.0, 1.35, gate);
}

float r = length(uv);
float a = atan(uv.y, uv.x);

float w = sin(r * freq * fmul - TIME * drift * 6.0) + sin(a * 6.0 + TIME * drift * 3.0);
float m = smoothstep(0.0, 1.0, 0.5 + 0.5 * w);
m = pow(m, 1.2);

vec3 base = mix(vec3(0.03,0.05,0.08), vec3(0.7,0.9,1.0), m);
base += amp * 0.15 * m;

// add a bass-driven highlight ring
float ring_r = 0.38 + 0.25 * sin(TIME * 3.3 * (1.0 + 0.6 * v));
float ring = smoothstep(0.02, 0.0, abs(r - ring_r));
base += vec3(0.6, 0.8, 1.0) * ring * (0.2 + 1.2 * clamp(v, 0.0, 1.0));

base *= smoothstep(1.4, 0.2, r);
COLOR = vec4(base, 1.0);


}
