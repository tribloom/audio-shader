shader_type canvas_item;
render_mode unshaded;

uniform float aspect;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;

uniform float density = 140.0;
uniform float base_speed = 0.08;

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
float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453); }

void fragment(){
	vec2 uv01 = SCREEN_UV;
	vec2 p = uv01 * density;

	float speed = base_speed;
	if (audio_enabled){
		float mids = pow(band_avg(0.2, 0.6) * audio_gain, 0.7);
		speed += 0.25 * mids;
	}

	float t = TIME * speed;
	float acc = 0.0;

	for (int j=-1;j<=1;j++){
		for (int i=-1;i<=1;i++){
			vec2 cell = floor(p) + vec2(float(i), float(j));
			vec2 center = fract(vec2(hash(cell + 7.0), hash(cell + 19.0)));
			center += 0.35 * vec2(sin(t + hash(cell) * 6.0), cos(t + hash(cell) * 6.0));
			float d = length(fract(p) - center);
			acc += smoothstep(0.08, 0.0, d);
		}
	}

	acc = clamp(acc, 0.0, 1.0);
	vec3 col = mix(vec3(0.01,0.02,0.03), vec3(0.8,1.0,0.9), acc);
	COLOR = vec4(col, 1.0);
}
