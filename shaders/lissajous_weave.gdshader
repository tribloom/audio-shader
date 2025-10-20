shader_type canvas_item;
render_mode unshaded;

uniform float aspect;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;

uniform float base_thick = 0.008;
uniform float freq_x = 3.0;
uniform float freq_y = 2.0;
uniform float drift = 0.25;

uniform float bass_lo = 0.02;
uniform float bass_hi = 0.20;
uniform float treb_lo = 0.70;
uniform float treb_hi = 0.95;

float band_max(float a, float b){
	if (bar_count <= 0) return 0.0;
	int ia = int(floor(a * float(bar_count)));
	int ib = int(ceil(b * float(bar_count))) - 1;
	ia = clamp(ia, 0, bar_count - 1);
	ib = clamp(ib, 0, bar_count - 1);
	float m = 0.0;
	for (int i = ia; i <= ib; i++){
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

float t = TIME * drift;

// average bass/treble bands for stability
float b = 0.0;
float h = 0.0;
if (audio_enabled){
	const int N = 16;
	float sb = 0.0;
	float st = 0.0;
	for (int i=0;i<N;i++){
		float ub = mix(bass_lo, bass_hi, (float(i)+0.5)/float(N));
		float uh = mix(treb_lo, treb_hi, (float(i)+0.5)/float(N));
		sb += texture(spectrum_tex, vec2(ub, 0.25)).r;
		st += texture(spectrum_tex, vec2(uh, 0.25)).r;
	}
	b = (sb/float(N)) * audio_gain;
	h = (st/float(N)) * audio_gain;
}
float bg = smoothstep(0.10, 0.22, pow(clamp(b,0.0,1.0), 0.7));
float hg = smoothstep(0.08, 0.20, pow(clamp(h,0.0,1.0), 0.7));

// thickness from bass, speed from both
float thick = mix(base_thick, base_thick * 2.6, bg);

float x = sin((uv.y + 1.0) * freq_x + t * (1.2 + 2.2 * bg));
float y = sin((uv.x + 1.0) * freq_y - t * (1.0 + 2.0 * hg));

float d = min(abs(uv.x - x * 0.6), abs(uv.y - y * 0.6));
float line = smoothstep(thick, 0.0, d) * smoothstep(1.1, 0.0, length(uv));

// bright “sparkle” on treble to make it obvious
vec3 col = mix(vec3(0.02), vec3(1.0, 0.85, 0.95), line);
col += line * hg * 0.50;

COLOR = vec4(col, 1.0);




}
