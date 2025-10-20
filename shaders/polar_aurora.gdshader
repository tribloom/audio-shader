shader_type canvas_item;
render_mode unshaded;

uniform float aspect;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;

uniform float aurora_scale = 1.6;
uniform float base_speed = 0.12;
uniform float glow = 1.3;

float bar_avg(float a, float b){
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
float h21(vec2 p){ p = fract(p*vec2(123.34, 345.45)); p += dot(p, p+34.56); return fract(p.x*p.y); }
float vnoise(vec2 p){
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	float a = h21(i);
	float b = h21(i+vec2(1.0,0.0));
	float c = h21(i+vec2(0.0,1.0));
	float d = h21(i+vec2(1.0,1.0));
	float x1 = mix(a,b,f.x);
	float x2 = mix(c,d,f.x);
	return mix(x1,x2,f.y);
}
float fbm(vec2 p){
	float a = 0.0;
	float w = 0.5;
	for(int i=0;i<5;i++){
		a += w * vnoise(p);
		p = p*1.85 + 7.13;
		w *= 0.5;
	}
	return a;
}

mat2 rot(float a){
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c,s), vec2(-s,c));
}

void fragment(){
	vec2 q = SCREEN_UV;
	vec2 pp = -1.0 + 2.0 * q;
	vec2 uv = pp;
	uv.x *= aspect;

	float speed = base_speed + (audio_enabled ? 0.18 * pow(bar_avg(0.0,0.22)*audio_gain, 0.65) : 0.0);

	if (audio_enabled){
		float bass = pow(bar_avg(0.0, 0.22) * audio_gain, 0.6);
		speed += 0.35 * bass;
	}

	vec2 p = uv * aurora_scale;
	p *= rot(0.25 * TIME);
	float t = TIME * speed;

	float band = fbm(p + vec2(0.0, t * 2.0));
	float rib  = fbm(p * 0.7 + vec2(t, -t * 0.6));
	float v = smoothstep(0.35, 0.95, band + 0.6 * rib);

	vec3 col = mix(vec3(0.02,0.05,0.10), vec3(0.1,0.7,1.0), v);
	col += glow * v * v * 0.15;
	col *= smoothstep(1.4, 0.2, length(uv));
	COLOR = vec4(pow(col, vec3(0.9)), 1.0);
}
