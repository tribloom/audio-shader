shader_type canvas_item;
render_mode unshaded;


/* --- AUDIO UNIFORMS --- */
uniform bool  audio_enabled = false;
uniform sampler2D spectrum_tex;   // 1 x bar_count, R=current
uniform int   bar_count = 64;
uniform float audio_gain = 1.0;   // overall sensitivity

/* tiny helpers */
float bar_at_index(int i){
	if (bar_count <= 0) return 0.0;
	i = clamp(i, 0, bar_count - 1);
	float u = (float(i) + 0.5) / float(bar_count);
	return texture(spectrum_tex, vec2(u, 0.5)).r;
}
float band_avg(float a, float b){          // a,b in [0,1] fraction across bars
	if (bar_count <= 1) return 0.0;
	int ia = int(floor(a * float(bar_count)));
	int ib = int(ceil (b * float(bar_count))) - 1;
	ia = clamp(ia, 0, bar_count - 1);
	ib = clamp(ib, 0, bar_count - 1);
	float s = 0.0;
	int n = max(1, ib - ia + 1);
	for (int i = ia; i <= ib; i++) s += bar_at_index(i);
	return s / float(n);
}

/* --- rotation: column-major constructor --- */
mat2 rot(float a){ float s = sin(a), c = cos(a); return mat2(vec2(c, s), vec2(-s, c)); }
vec2 OFF6(float n){ return vec2(1.0, 0.0) * rot(n * TAU / 6.0); }

const float planeDist = 0.5;
const float furthest  = 6.0;
const float fadeFrom  = 4.0;
const float cutOff    = 0.975;

const vec3  L  = vec3(0.299, 0.587, 0.114);
const vec2  pathA = vec2(0.31, 0.41);
const vec2  pathB = vec2(sqrt(2.0), 1.0);
const vec4  U = vec4(0.0, 1.0, 2.0, 3.0);

vec3 offset(float z){ return vec3(pathB * sin(pathA * z), z); }
vec3 doffset(float z){ return vec3(pathA * pathB * cos(pathA * z), 1.0); }
vec3 ddoffset(float z){ return vec3(-pathA * pathA * pathB * sin(pathA * z), 0.0); }

float tanh_approx(float x){ float x2 = x*x; return clamp(x * (27.0 + x2) / (27.0 + 9.0 * x2), -1.0, 1.0); }

/* --- Hex helpers --- */
vec2 hextile(inout vec2 p){
	const vec2 sz  = vec2(1.0, sqrt(3.0));
	const vec2 hsz = 0.5 * sz;
	vec2 p1 = mod(p, sz) - hsz;
	vec2 p2 = mod(p - hsz, sz) - hsz;
	vec2 p3 = (dot(p1,p1) < dot(p2,p2)) ? p1 : p2;
	vec2 n  = (p3 - p + hsz) / sz;
	p = p3;
	n -= vec2(0.5);
	return round(n * 2.0) * 0.5;
}

/* --- IQ helpers --- */
float hexagon(vec2 p, float r){
	p = p.yx;
	const vec3 k = 0.5 * vec3(-sqrt(3.0), 1.0, sqrt(4.0 / 3.0));
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}
float hash(vec2 co){ co += 1.234; return fract(sin(dot(co, vec2(12.9898,58.233))) * 13758.5453); }
float dot2(vec2 p){ return dot(p, p); }
float segment(vec2 p, vec2 a, vec2 b){
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa,ba)/dot(ba,ba), 0.0, 1.0);
	return length(pa - ba * h);
}
float bezier(vec2 pos, vec2 A, vec2 B, vec2 C){
	vec2 a = B - A;
	vec2 b = A - 2.0*B + C;
	vec2 c = a * 2.0;
	vec2 d = A - pos;
	float kk = 1.0/dot(b,b);
	float kx = kk * dot(a,b);
	float ky = kk * (2.0*dot(a,a) + dot(d,b)) / 3.0;
	float kz = kk * dot(d,a);
	float p  = ky - kx*kx;
	float q  = kx*(2.0*kx*kx - 3.0*ky) + kz;
	float h  = q*q + 4.0*p*p*p;
	float res;
	if (h >= 0.0){
		h = sqrt(h);
		vec2 x = (vec2(h, -h) - q) / 2.0;
		vec2 uv = sign(x) * pow(abs(x), vec2(1.0/3.0));
		float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
		res = dot2(d + (c + b*t)*t);
	}else{
		float z = sqrt(-p);
		float v = acos(q / (p*z*2.0)) / 3.0;
		float m = cos(v);
		float n = sin(v) * 1.732050808;
		vec3  t = clamp(vec3(m+m, -n-m, n-m)*z - kx, 0.0, 1.0);
		res = min(dot2(d + (c + b*t.x)*t.x),
		          dot2(d + (c + b*t.y)*t.y));
	}
	return sqrt(res);
}
vec2 coff(float h){
	float h1 = fract(h * 9677.0);
	float t  = 0.75 * mix(0.5, 1.0, h*h) * (TIME + 1234.5);
	return mix(0.1, 0.2, h1*h1) * sin(t * vec2(1.0, sqrt(0.5)));
}

/* --- ACES --- */
vec3 aces_approx(vec3 v){
	v = max(v, 0.0);
	v *= 0.6;
	float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
	return clamp((v*(a*v+b))/(v*(c*v+d)+e), 0.0, 1.0);
}
vec3 alphaBlend(vec3 back, vec4 front){ return mix(back, front.rgb, front.a); }
vec4 alphaBlend(vec4 back, vec4 front){
	float w = front.a + back.a*(1.0 - front.a);
	vec3 rgb = (front.rgb*front.a + back.rgb*back.a*(1.0 - front.a)) / max(w, 1e-6);
	return (w > 0.0) ? vec4(rgb, w) : vec4(0.0);
}

/* const arrays → index helpers */
vec2 off6(int i){
	if(i==0) return OFF6(0.0);
	if(i==1) return OFF6(1.0);
	if(i==2) return OFF6(2.0);
	if(i==3) return OFF6(3.0);
	if(i==4) return OFF6(4.0);
	return OFF6(5.0);
}
vec2 noff6(int i){
	if(i==0) return vec2(-1.0,  0.0);
	if(i==1) return vec2(-0.5,  0.5);
	if(i==2) return vec2( 0.5,  0.5);
	if(i==3) return vec2( 1.0,  0.0);
	if(i==4) return vec2( 0.5, -0.5);
	return vec2(-0.5, -0.5);
}

/* --- Layer plane --- */
vec4 plane(vec3 ro, vec3 rd, vec3 pp, vec3 off, float aa, float n){
	vec2 p = (pp - off.yyx).xy;
	vec2 p2 = p;
	p2 *= rot(TAU*0.1*n + 0.05*TIME);
	p2 += 0.125*(ro.z - pp.z) * vec2(1.0) * rot(TAU * hash(vec2(n)));
	vec2 hp = p2 + 0.5;

	const float z = 1.0/3.0;
	hp /= z;

	vec2 hn = hextile(hp);

	float h0 = hash(hn + n);
	vec2 p0  = coff(h0);

	// base color as before
	vec3 bcol = 0.5 * (1.0 + cos(vec3(0.0, 1.0, 2.0) + 2.0*(p2.x*p2.y + p2.x) - 0.33*n));

	vec3 col = vec3(0.0);

	for (int i=0;i<6;i++){
		float h1 = hash(hn + noff6(i) + n);
		vec2 p1  = off6(i) + coff(h1);
		float h2 = h0 + h1;
		float fade = smoothstep(1.05, 0.85, distance(p0, p1));
		if (fade < 0.0125) continue;

		vec2 cp = 0.5*(p1 + p0) + coff(h2);
		float dd = bezier(hp, p0, cp, p1);

		float base_gd = max(abs(dd) * sqrt(abs(dd)), 0.0005);
		vec3 line_col = bcol;
		float amp = 0.0;
		if (audio_enabled && bar_count > 0){
			float bar_f = fract(h2);
			int bar_idx = clamp(int(floor(bar_f * float(bar_count))), 0, bar_count - 1);
			amp = clamp(pow(bar_at_index(bar_idx) * audio_gain, 0.5), 0.0, 1.0);
		}
		float width_scale = mix(1.0, 0.25, amp);
		float gd = max(base_gd * width_scale, 0.0002);
		float glow = mix(1.0, 1.25, amp);
		col += glow * fade * 0.0022 * line_col / gd;
	}
	{
		float gd = max(length(hp - p0) * length(hp - p0), 0.0005);
		col += 0.0025 * sqrt(bcol) / gd;
	}
	{
		float gd = max(abs(hexagon(hp, 0.485)), 0.005);
		col += 0.0005 * bcol * bcol / gd;
	}

	float l = dot(col, L);
	return vec4(col, tanh_approx(sqrt(l) + dot(p, p)));
}

/* --- Field accumulation --- */
vec3 color_field(vec3 ww, vec3 uu, vec3 vv, vec3 ro, vec2 p, vec2 RES){
	vec2 np  = p + 1.0 / RES;
	float rdd = 2.0;

	vec3 rd  = normalize(p.x*uu + p.y*vv + rdd*ww);
	vec3 nrd = normalize(np.x*uu + np.y*vv + rdd*ww);

	float nz = floor(ro.z / planeDist);
	vec4 acol = vec4(0.0);
	vec3 skyCol = vec3(0.0);

	for (float i=1.0;i<=furthest;i+=1.0){
		float pz = planeDist*nz + planeDist*i;
		float pd = (pz - ro.z)/rd.z;

		if (pd > 0.0 && acol.a < cutOff){
			vec3 pp  = ro + rd*pd;
			vec3 npp = ro + nrd*pd;

			float aa = 3.0 * length(pp - npp);
			vec3 off = offset(pp.z);

			vec4 pcol = plane(ro, rd, pp, off, aa, nz + i);

			float ndz = pp.z - ro.z;
			float fadeIn  = smoothstep(planeDist*furthest, planeDist*fadeFrom, ndz);
			float fadeOut = smoothstep(0.0, planeDist*0.1, ndz);
			pcol.a *= fadeOut * fadeIn;

			acol = alphaBlend(pcol, acol);
		}else{
			acol.a = (acol.a > cutOff) ? 1.0 : acol.a;
			break;
		}
	}
	return alphaBlend(skyCol, acol);
}

/* --- Fragment --- */
void fragment(){
	vec2 RES = 1.0 / SCREEN_PIXEL_SIZE;

	vec2 r  = RES;
	vec2 q  = FRAGCOORD.xy / r;
	vec2 pp = -1.0 + 2.0 * q;
	vec2 p  = pp;
	p.x *= r.x / r.y;

	float tdist = length(pp);
	float tm  = 0.2 * planeDist * TIME + 0.1 * tdist;

	vec3 ro   = offset(tm);
	vec3 dro  = doffset(tm);
	vec3 ddro = ddoffset(tm);

	vec3 ww = normalize(dro);
	vec3 uu = normalize(cross(U.xyx + ddro, ww));
	vec3 vv = cross(ww, uu);

	vec3 col = color_field(ww, uu, vv, ro, p, RES);

	col -= 0.02 * U.zwx * (length(pp) + 0.125);
	col *= smoothstep(1.5, 1.0, length(pp));
	col *= smoothstep(0.0, 10.0, TIME - 2.0 * (q.x - q.x * q.y));
	col  = aces_approx(col);
	col  = sqrt(col);

	COLOR = vec4(col, 1.0);
}