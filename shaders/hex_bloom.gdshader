shader_type canvas_item;
render_mode unshaded;

uniform float aspect;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;

uniform float grid_scale = 6.0;
uniform float base_width = 0.015;

uniform float cell_deform = 0.08;
uniform float cell_rotate = 0.25;

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
float hex(vec2 p){
	const vec3 k = vec3(0.57735, 0.57735, 0.57735);
	p = abs(p);
	return max(dot(p, k.xy), p.x);
}

void fragment(){
	vec2 q = SCREEN_UV;
	vec2 pp = -1.0 + 2.0 * q;
	vec2 uv = pp;
	uv.x *= aspect;

vec2 p = uv * grid_scale;
vec2 id = floor(p);
vec2 g = fract(p) - 0.5;

// map cell id -> bin (wrap across X so adjacent cells differ)
float u = fract(id.x / 32.0);
float s = 0.0;
if (audio_enabled) s = texture(spectrum_tex, vec2(u, 0.25)).r * audio_gain;
float gate = smoothstep(0.08, 0.22, pow(clamp(s, 0.0, 1.0), 0.7));

// per-cell rotation and “breathing” from its bin
float a = cell_rotate * gate * sin(TIME * 2.0 + id.x * 0.6 + id.y * 0.4);
float ca = cos(a);
float sa = sin(a);
g = mat2(vec2(ca, sa), vec2(-sa, ca)) * g;

// radial deform so the hex changes shape (very visible)
float deform = 1.0 + cell_deform * gate * sin(TIME * 3.0 + u * TAU);
g *= deform;

const vec3 k = vec3(0.57735, 0.57735, 0.57735);
vec2 ap = abs(g);
float h = max(dot(ap, k.xy), ap.x);
float edge = abs(h - 0.45);

// width + glow from the same bin
float thick = mix(base_width, base_width * 2.4, gate);
float line = smoothstep(thick, 0.0, edge);

vec3 col = mix(vec3(0.02), vec3(0.85, 0.95, 1.0), line);
col += line * (0.15 + 0.45 * gate);

COLOR = vec4(col, 1.0);




}
