shader_type canvas_item;
render_mode unshaded;

uniform float aspect;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;

uniform int count = 14;
uniform float base_radius = 0.65;
uniform float dot_size = 0.018;
uniform float spin = 0.6;

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

	float wob = 0.0;
	if (audio_enabled){
		float hi = pow(band_avg(0.6, 1.0) * audio_gain, 0.7);
		wob = 0.12 * smoothstep(0.08, 0.25, hi);
	}

	float t = TIME * spin;
	// inside fragment(), before this you compute uv, aspect, wob, t, etc.

float sdf = 1e9;
for (int i = 0; i < 256; i++){
float a = (float(i) / float(max(count, 1))) * TAU + t; // put this at top of loop
float rr = clamp(base_radius + wob * sin(t + float(i)), 0.2, 0.9);
vec2 c = vec2(cos(a), sin(a)) * rr;
sdf = min(sdf, length(uv - c) - dot_size);
}

// color (replace your old color block with this)
float d = smoothstep(0.008, 0.0, sdf);
vec3 col = mix(vec3(0.02), vec3(1.0, 0.9, 0.7), d);
col *= smoothstep(1.2, 0.2, length(uv));
COLOR = vec4(col, 1.0);

}
