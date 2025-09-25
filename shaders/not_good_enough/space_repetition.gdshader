shader_type canvas_item;
render_mode unshaded;

/* Shadertoy bridges */
vec2  iResolution() { return vec2(1.0 / 1920.0, 1.0 / 1080.0); }
float iTime()       { return TIME; }

/* Small knobs */
uniform float time_speed : hint_range(0.25, 2.0) = 1.0;
uniform float brightness : hint_range(0.5, 2.0) = 1.0;
/* Show outside the original time windows (45–88s, 98.6–109s) */
uniform bool always_show = true;

/* Helpers (ported; mat2 uses column vectors) */
float random(vec2 uv){ return fract(sin(dot(uv, vec2(12.2544, 35.1571))) * 5418.548416); }
mat2 r2d(float a){ float c=cos(a), s=sin(a); return mat2(vec2(c,s), vec2(-s,c)); }
vec3 re(vec3 p, float d){ return mod(p - d*0.5, d) - d*0.5; }
void amod2(inout vec2 p, float d){ float a = re(vec3(atan(p.x, p.y)), d).x; p = vec2(cos(a), sin(a)) * length(p); }
void mo(inout vec2 p, vec2 d){ p = abs(p) - d; if (p.y > p.x) p = p.yx; }
vec3 get_cam(vec3 ro, vec3 ta, vec2 uv){
	vec3 fwd = normalize(ta - ro);
	vec3 right = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(right, fwd);
	return normalize(fwd + right*uv.x + up*uv.y);
}

/* SDFs (iq) */
float cube(vec3 p, vec3 b){ b = abs(p) - b; return min(max(b.x, max(b.y, b.z)), 0.0) + length(max(b, 0.0)); }
float sc(vec3 p, float d){ p = abs(p); p = max(p, p.yzx); return min(p.x, min(p.y, p.z)) - d; }

/* Scene pieces (parameterized on t) */
float prim(vec3 p, float t){
	p.xy *= r2d(3.14 * 0.5 + p.z * 0.1);
	amod2(p.xy, 6.28 / 3.0);
	p.x = abs(p.x) - 9.0;
	p.xy *= r2d(p.z * 0.2);
	amod2(p.xy, 6.28 / mix(mix(10.0, 5.0, smoothstep(59.5,61.5,t)), 3.0, smoothstep(77.5,77.75,t)));
	mo(p.xy, vec2(2.0));
	p.x = abs(p.x) - 0.6;
	return length(p.xy) - 0.2;
}

/* Return (d_final, glow1, glow2) */
vec3 de_pack(vec3 p, float t){
	if (t > 109.2){ mo(p.xy, vec2(0.2)); p.x -= 10.0; }
	if (t > 101.4){ p.xy *= r2d(t * 0.2); }
	if (t > 106.5){ mo(p.xy, vec2(5.0 + sin(t)*3.0*cos(t*0.5), 0.0)); }
	if (t > 104.0){ amod2(p.xy, 6.28/3.0); p.x += 5.0; }
	if (t > 101.4){ mo(p.xy, vec2(2.0 + sin(t)*3.0*cos(t*0.5), 0.0)); }

	p.xy *= r2d(t * 0.05);
	p.xy *= r2d(p.z * mix(0.05, 0.002, step(89.5, t))); // P2 - T11

	p.x += sin(t) * smoothstep(77.0, 82.0, t);

	amod2(p.xy, 6.28 / mix(mix(1.0,2.0,smoothstep(63.5,68.5,t)), 5.0, smoothstep(72.0,73.5,t)));
	p.x -= 21.0;

	vec3 q = p;

	p.xy *= r2d(p.z * 0.1);
	amod2(p.xy, 6.28 / 3.0);
	p.x = abs(p.x) - mix(20.0, 5.0, smoothstep(49.5, 55.0, t)); // T2

	p.xy *= r2d(p.z * mix(1.0, 0.2, smoothstep(77.5, 77.75, t))); // T8b
	p.z = re(p.zzz, 3.0).x;

	p.x = abs(p.x);
	amod2(p.xy, 6.28 / mix(6.0, 3.0, smoothstep(77.75, 78.5, t))); // T10
	float sc1 = sc(p, mix(8.0, 1.0, smoothstep(45.5, 51.0, t)));   // T1

	amod2(p.xz, 6.28 / mix(3.0, 8.0, smoothstep(61.5, 65.5, t)));  // T5
	mo(p.xz, vec2(0.1));
	p.x = abs(p.x) - 1.0;

	float d = cube(p, vec3(0.2, 10.0, 1.0));
	d = max(d, -sc1) - mix(0.01, 2.0, smoothstep(56.0, 58.5, t));  // T3

	float g1 = 0.006 / (0.010 + d*d); // glow1
	d = min(d, prim(q, t));
	float g2 = 0.004 / (0.013 + d*d); // glow2

	return vec3(d, g1, g2);
}

/* Raymarch (~50 steps) */
vec3 raymarch_lsdlive(vec3 ro, vec3 rd, vec2 uv, float t){
	vec3 p; float acc=0.0; float ri=0.0; float dither = random(uv);
	float glow = 0.0;

	for (int j=0; j<50; ++j){
		ri = float(j) / 50.0;
		p = ro + rd * acc;

		vec3 pack = de_pack(p, t);
		float d = pack.x;
		glow += pack.y + pack.z;

		d *= 1.0 + dither * 0.05;
		d  = max(abs(d), 0.002);
		acc += d * 0.5;
	}

	vec3 c = mix(vec3(0.9,0.8,0.6), vec3(0.1,0.1,0.2), length(uv) + ri);
	c.r += sin(p.z * 0.1) * 0.2;
	c += glow * 0.035;
	return c;
}

/* Correct glitch: only active between start/end (like source) */
void glitch_window(inout vec2 uv, vec2 fragCoord, float t, float start_t, float end_t){
	if (!(t > start_t && t <= end_t)) return;

	int offset = int(floor(t)*2.0) + int((uv.x + uv.y) * 8.0);
	float res = mix(10.0, 100.0, random(vec2(float(offset))));
	uv = floor(uv * res) / res;

	int seedX = int(fragCoord.x + t) / 32;
	int seedY = int(fragCoord.y + t) / 32;
	int seed  = (mod(t, 2.0) > 1.0) ? seedX : seedY;

	float r = random(vec2(float(seed)));
	uv.x += (r * 2.0 - 1.0)
	      * step(random(vec2(float(seed))), pow(sin(t * 4.0), 7.0))
	      * random(vec2(float(seed)));
}

void fragment(){
	vec2  res       = iResolution();
	vec2  fragCoord = SCREEN_UV * res;
	vec2  q         = fragCoord / res;
	vec2  uv        = (q - 0.5) * res.xx / res.yx;

	// Scripted time
	float t = mod(iTime() * time_speed, 43.0 + 10.4);
	t = t + 45.0;
	if (t > 88.0 && t <= 98.6) t += 10.6;

	// Glitch windows (fixed gating)
	vec2 uv_g = uv;
	glitch_window(uv_g, fragCoord, t,   0.0,   2.0);
	glitch_window(uv_g, fragCoord, t,  98.0,  99.0);
	glitch_window(uv_g, fragCoord, t, 100.5, 101.5);
	glitch_window(uv_g, fragCoord, t, 103.0, 104.0);
	glitch_window(uv_g, fragCoord, t, 105.5, 106.5);

	// Camera (exact)
	vec3 ro = vec3(0.0, 0.0, -4.0 + t * 8.0);
	vec3 ta = vec3(0.0, 0.0,        t * 8.0);
	vec3 rd = get_cam(ro, ta, uv_g);

	bool in_window = (t > 45.0 && t <= 88.0) || (t > 98.6 && t <= 109.0);
	if (always_show) in_window = true;

	vec3 col = vec3(0.0);
	if (in_window){
		col = raymarch_lsdlive(ro, rd, uv_g, t);
	}

	// vignette + grade
	col *= 0.5 + 0.5 * pow(16.0*q.x*q.y*(1.0-q.x)*(1.0-q.y), 0.25);
	col *= brightness;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
