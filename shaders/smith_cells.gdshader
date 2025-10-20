shader_type canvas_item;

/* ---------- Audio (optional) ---------- */
uniform bool enable_audio = true;
uniform sampler2D spectrum_tex;
uniform int bar_count;

/* Amounts (keep small for classy look) */
uniform float audio_dot_size = 0.35;
uniform float audio_dot_brightness = 0.65;

/* Look / behavior */
uniform float rep = 32.0;
uniform float over = 4.0;

/* Tone mapping toggles */
uniform bool use_aces = true;
uniform bool use_srgb = true;

/* ---------- Utils ---------- */
const float pm = 17.0;

vec3 hsv2rgb(vec3 c){
    const vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    vec3 rgb = c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    return rgb;
}
vec3 sRGB(vec3 t){
    vec3 a = 1.055 * pow(max(t, vec3(0.0)), vec3(1.0/2.4)) - 0.055;
    vec3 b = 12.92 * t;
    vec3 m = step(t, vec3(0.0031308));
    return mix(a, b, m);
}
vec3 aces_approx(vec3 v){
    v = max(v, 0.0);
    v *= 0.6;
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    vec3 num = v * (a * v + b);
    vec3 den = v * (c * v + d) + e;
    vec3 r = clamp(num / den, 0.0, 1.0);
    return r;
}

mat2 rot2(float a){
    float c = cos(a);
    float s = sin(a);
    // columns, not rows
    return mat2(vec2(c, s), vec2(-s, c));
}

/* ---------- Spectrum helpers ---------- */
float spectrum_sample01(float u){
    int n = max(1, bar_count);
    float x = clamp(u, 0.0, 1.0) * float(n - 1);
    float xf = (floor(x) + 0.5) / float(n);
    float v = texture(spectrum_tex, vec2(xf, 0.5)).r;
    return clamp(v, 0.0, 1.0);
}
float amp_for_cell(float n01){
    if (!enable_audio){
        return 0.0;
    }
    float a0 = spectrum_sample01(n01);
    float a1 = spectrum_sample01(clamp(n01 + 1.0 / max(8.0, float(bar_count)), 0.0, 1.0));
    float a2 = spectrum_sample01(clamp(n01 - 1.0 / max(8.0, float(bar_count)), 0.0, 1.0));
    float a = (a0 + 0.5 * (a1 + a2)) / 2.0;
    return a;
}

/* ---------- From original ---------- */
// segment distance along x-oriented capsule
float segmentx(vec2 p, float l, float w){
    p = abs(p);
    p.x -= l * 0.5 - w;
    float d0 = length(p) - w;
    float d1 = p.y - w;
    float d = p.x > 0.0 ? d0 : d1;
    return d;
}

// polar repetition; returns cell index (we normalize to 0..1 later)
float modPolar(inout vec2 p, float aa, float rep_local){
    float angle = 2.0 * PI / rep_local;
    float a = aa + angle * 0.5;
    float r = length(p);
    float c = floor(a / angle);
    a = mod(a, angle) - angle * 0.5;
    p = vec2(cos(a), sin(a)) * r;
    if (abs(c) >= (rep_local * 0.5)) c = abs(c);
    return c;
}

vec2 hextile(inout vec2 p){
    vec2 sz = vec2(1.0, sqrt(3.0));
    vec2 hsz = 0.5 * sz;
    vec2 p1 = mod(p, sz) - hsz;
    vec2 p2 = mod(p - hsz, sz) - hsz;
    vec2 p3 = dot(p1, p1) < dot(p2, p2) ? p1 : p2;
    vec2 n = ((p3 - p + hsz) / sz);
    p = p3;
    n -= vec2(0.5);
    return round(n * 2.0) * 0.5;
}

/* Distance fields for rod and endpoint dot.
   OUT n_out: normalized angular cell coordinate (0..1) for spectrum lookup. */
vec2 df(vec2 p, float noff, float a, out float n_out){
    float rep_local = rep;
    float ncell = modPolar(p, a, rep_local);
    float n = ncell / rep_local + noff;  // may exceed 0..1 slightly
    n = fract(n);
    n_out = n;

    float ll = 0.5;
    float ss = 0.0015;
    float bb = ss * 4.0;

    float anim = sin(TAU * TIME / 10.0 + pm * noff * TAU);
    p.x -= 0.75 + 0.25 * anim;
    float l = ll * mix(0.5, 1.0, smoothstep(-0.9, 0.9, anim));
    float s = ss;
    float b = bb;

    // Audio: inflate the endpoint radius slightly per-cell
    if (enable_audio){
        float amp = amp_for_cell(n);
        b *= 1.0 + audio_dot_size * amp;
    }

    vec2 p0 = p;
    vec2 p1 = p;
    p1.x = abs(p1.x);
    p1.x -= l * 0.5 - s;

    float d0 = segmentx(p0, l, s); // rod
    float d1 = length(p1) - b;     // dot (endpoint)
    return vec2(d0, d1);
}

vec3 effect0(vec2 p, float aa){
    float zz = 2.75;
    p /= zz;
    vec2 _hn = hextile(p);
    p *= zz;

    vec3 col = vec3(0.0);
    float a = atan(p.y, p.x);
    float ll = length(p);
    float rep_over = rep * over;
    float astep = TAU / rep_over;
    float nstep = 1.0 / rep_over;

    mat2 rr = rot2(astep);

    for (float i = 0.0; i < over; i += 1.0){
        float noff = i * nstep;
        float aoff = i * astep;

        float n_cell;
        vec2 d = df(p, noff, a - aoff, n_cell);
        d /= aa;

        float g0 = 2.0 / max(max(d.x, 0.0), 0.001);              // rod glow
        float g1 = 8.0 / max((d.y * d.y), 0.000001);             // dot glow

        // Audio: brighten the dots with spectrum
        if (enable_audio){
            float amp = amp_for_cell(n_cell);
            g1 *= 1.0 + audio_dot_brightness * amp;
        }

        vec3 base_hsv = vec3(0.5 * ll + n_cell - 0.1 * TIME, 0.85, g0);
        vec3 dot_hsv  = vec3(0.5 * ll + n_cell - 0.1 * TIME, 0.50, g1);
        col += hsv2rgb(base_hsv);
        col += hsv2rgb(dot_hsv);

        p *= rr;
    }

    col *= smoothstep(0.5 * zz, 0.25 * zz, ll);

    vec3 gcol0 = hsv2rgb(vec3(0.55, 0.75, 10000.0));
    vec3 gcol1 = hsv2rgb(vec3(0.55, 0.95, 0.025));
    col += gcol0 * aa * aa + gcol1 / dot(p, p);
    col /= (600.0 * aa);
    return col;
}

vec2 toSmith(vec2 p){
    float d = (1.0 - p.x) * (1.0 - p.x) + p.y * p.y;
    float x = (1.0 + p.x) * (1.0 - p.x) - p.y * p.y;
    float y = 2.0 * p.y;
    return vec2(x, y) / d;
}
vec2 fromSmith(vec2 p){
    float d = (p.x + 1.0) * (p.x + 1.0) + p.y * p.y;
    float x = (p.x + 1.0) * (p.x - 1.0) + p.y * p.y;
    float y = 2.0 * p.y;
    return vec2(x, y) / d;
}
vec2 transform(vec2 p){
    vec2 off0 = sin(vec2(1.0, sqrt(0.5)) * 0.23 * TIME);
    vec2 off1 = sin(vec2(1.0, sqrt(0.5)) * 0.13 * TIME);
    vec2 sp0 = toSmith(p);
    vec2 sp1 = toSmith(p + off0);
    vec2 sp2 = toSmith(p - off1);
    vec2 pp = fromSmith(sp0 + sp1 - sp2);
    pp += 0.1 * TIME;
    return pp;
}
vec3 effect_main(vec2 p, vec2 np, vec2 pp){
    p = transform(p);
    np = transform(np);
    float aa = distance(p, np) * sqrt(2.0);
    vec3 col = effect0(p, aa);
    return col;
}

/* ---------- Fragment ---------- */
void fragment(){
    vec2 res = vec2(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);
    vec2 fragCoord = UV * res;

    vec2 q = fragCoord / res;
    vec2 p = -1.0 + 2.0 * q;
    vec2 pp = p;

    p.x *= res.x / res.y;
    vec2 np = p + vec2(0.0, 1.0 / res.y);

    vec3 col = effect_main(p, np, pp);

    if (use_aces){
        col = aces_approx(col);
    }
    if (use_srgb){
        col = sRGB(col);
    }

    COLOR = vec4(col, 1.0);
}
