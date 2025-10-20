shader_type canvas_item;
render_mode unshaded;

uniform float aspect;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;

uniform float base_speed = 0.6;
uniform float stripe_density = 8.0;
uniform float vignette = 1.4;

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

float sp = base_speed;
if (audio_enabled){
	float vol = pow(band_avg(0.0, 0.5) * audio_gain, 0.7);
	sp += 1.0 * vol;
}
float r = length(uv);
float z = TIME * sp + 1.2 / max(0.2, r + 0.05);
float s = sin(z * stripe_density + atan(uv.y, uv.x) * 3.0);
float stripe = smoothstep(0.1, 0.0, abs(s));

	vec3 col = mix(vec3(0.03), vec3(0.9,1.0,0.9), stripe);
	col *= smoothstep(vignette, 0.2, length(uv));
	COLOR = vec4(col, 1.0);
}
