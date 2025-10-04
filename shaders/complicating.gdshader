shader_type canvas_item;

/* =================== Controls =================== */
uniform float time_scale : hint_range(0.0, 5.0) = 1.0;
uniform float aspect = 1.7777778;                 // width/height (set from GDScript)
uniform vec2  p_step = vec2(0.0025, 0.0025);      // ~= (2/width, 2/height) in NDC space

/* Time drive (replaces BPM) */
uniform int   time_drive_mode = 1;                // 0=Constant, 1=Kick (default), 2=Spectrum
uniform float time_drive_const = 1.0;             // used when mode==0
uniform float kick = 0.0;                         // 0..1 (feed your existing kick/level)

/* Spectrum (only used when time_drive_mode == 2) */
uniform sampler2D spectrum_tex : hint_default_black;
uniform int   spectrum_bands = 64;
uniform float spectrum_lo = 0.0;                  // 0=bass
uniform float spectrum_hi = 1.0;                  // 1=treble
uniform float spectrum_gain : hint_range(0.0,4.0) = 1.0;

/* =================== Constants =================== */
const float plane_dist = 0.25;                    // 1.0 - 0.75
const int   furthest = 12;
const int   fade_from = 8;                        // furthest - 4

/* =================== Math Helpers =================== */
mat2 r2(float a) {
    float c = cos(a);
    float s = sin(a);
    return mat2(vec2(c, s), vec2(-s, c));        // column-major
}

float tanh_approx(float x) {
    float x2 = x * x;
    float num = x * (27.0 + x2);
    float den = 27.0 + 9.0 * x2;
    float t = clamp(num / den, -1.0, 1.0);
    return t;
}

vec4 alphaBlend_v4(vec4 back, vec4 front) {
    float w = front.w + back.w * (1.0 - front.w);
    vec3 xyz = front.xyz * front.w + back.xyz * back.w * (1.0 - front.w);
    vec3 col = (w > 0.0) ? (xyz / w) : vec3(0.0);
    return vec4(col, w);
}

vec3 alphaBlend_v3(vec3 back, vec4 front) {
    return mix(back, front.xyz, front.w);
}

/* Pascal Gilcher atan approx, avoids PI defines */
float atan_approx(float y, float x) {
    float cosatan2 = x / (abs(x) + abs(y));
    float half_pi = acos(0.0);                    // π/2
    float t = half_pi - cosatan2 * half_pi;
    return (y < 0.0) ? -t : t;
}

vec2 toPolar(vec2 p) {
    return vec2(length(p), atan_approx(p.y, p.x));
}
vec2 toRect(vec2 p) {
    return vec2(p.x * cos(p.y), p.x * sin(p.y));
}

/* Mercury mod-mirror */
float modMirror1(inout float p, float size) {
    float halfsize = size * 0.5;
    float c = floor((p + halfsize) / size);
    p = mod(p + halfsize, size) - halfsize;
    p *= (mod(c, 2.0) * 2.0 - 1.0);
    return c;
}

/* Smooth helpers */
float pmin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
float pabs(float a, float k) {
    return -pmin(a, -a, k);
}

/* =================== Scene bits =================== */
vec3 offset(float z) {
    float a = z * 0.5;
    vec2 p = -0.25 * (vec2(cos(a), sin(a * sqrt(2.0))) +
                      vec2(cos(a * sqrt(0.75)), sin(a * sqrt(0.6))));
    return vec3(p, z);
}
vec3 doffset(float z) {
    float eps = 0.05;
    return (offset(z + eps) - offset(z - eps)) / (2.0 * eps);
}
vec3 ddoffset(float z) {
    float eps = 0.05;
    return (doffset(z + eps) - doffset(z - eps)) / (2.0 * eps);
}

vec3 skyColor(vec3 ro, vec3 rd) {
    return vec3(0.0);
}

/* Kaleidoscope */
float smoothKaleidoscope(inout vec2 p, float sm, float rep) {
    vec2 hp = p;
    vec2 hpp = toPolar(hp);

    float two_pi = 2.0 * acos(-1.0);
    float step_ang = two_pi / rep;

    float rn = modMirror1(hpp.y, step_ang);

    float pi = acos(-1.0);
    float rep_pi = pi / rep;
    float sa = rep_pi - pabs(rep_pi - abs(hpp.y), sm);
    hpp.y = sign(hpp.y) * sa;

    hp = toRect(hpp);
    p = hp;
    return rn;
}

/* Palette */
vec3 palette(float t) {
    float two_pi = 2.0 * acos(-1.0);
    return 0.5 * (vec3(1.0) + cos(vec3(0.0, 1.0, 2.0) + two_pi * t));
}

/* Kishimisu layer */
vec3 kishimisu(vec3 col, vec2 p, float tm, float n) {
    vec2 p0 = p;
    vec2 p1 = p;
    for (float i = 0.0; i < 4.0; i += 1.0) {
        p1 = fract(p1 * 2.0 + 0.0125 * tm) - 0.5;

        float d = length(p1) * exp(-length(p0));
        vec3 cc = palette(length(p0) + i * 0.4 + tm * 0.2);

        float v = sin(d * 8.0 + tm) / 8.0;
        v = abs(v);
        v -= 0.0025;
        v = max(v, 0.005);
        float inv = 0.0125 / v;
        col += cc * (inv * inv);
    }
    return 0.5 * col;
}

/* Effect inside each plane */
vec3 inner_effect(vec2 p, float tm, float n) {
    vec3 col = vec3(0.0);
    vec2 kp = p;
    float nn = 2.0 * floor(mix(3.0, 16.0, 0.5 + 0.5 * sin(0.1 * n)));
    smoothKaleidoscope(kp, 0.1, nn);
    kp += 0.5 * sin(vec2(1.0, sqrt(0.5)) * tm * 0.21);
    col = kishimisu(col, kp, tm, n);
    col -= 0.75 * vec3(0.0, 1.0, 2.0).zyx * dot(p, p);
    col = clamp(col, 0.0, 4.0);
    return col;
}

vec4 plane(vec3 ro, vec3 rd, vec3 pp, vec3 off, float aa, float n) {
    vec2 p = (pp - off * vec3(1.0, 1.0, 0.0)).xy;
    float l = length(p);
    p *= mix(0.5, 0.75, 0.5 + 0.5 * sin(n * 0.071));
    float tm = 0.5 * 0.125 * TIME + 0.125 * n;
    p = r2(-tm) * p;

    float fade = smoothstep(0.1, 0.15, l);
    if (fade < 0.05) {
        return vec4(0.0);
    }

    vec4 col = vec4(0.0);
    col.xyz = inner_effect(p, tm, n);

    float mx = max(max(col.x, col.y), col.z) * 0.75;
    col.w = tanh_approx(0.5 + l + max(mx, 0.0)) * fade;
    return col;
}

/* =================== Spectrum energy (0..1) =================== */
float spectrum_energy() {
    int N = max(spectrum_bands, 4);
    float lo = clamp(spectrum_lo, 0.0, 1.0);
    float hi = clamp(spectrum_hi, lo + 0.001, 1.0);

    float sum = 0.0;

    // sample middle row (v=0.5) across X
    for (int i = 0; i < 256; i++) {
        if (i >= N) break;
        float u = (N > 1) ? float(i) / float(N - 1) : 0.0;
        float x = mix(lo, hi, u);
        float v = texture(spectrum_tex, vec2(x, 0.5)).r;
        v = max(v, 0.0);
        v = sqrt(v); // mild companding
        sum += v;
    }

    float loud = (N > 0) ? (sum / float(N)) : 0.0;
    float energy = clamp(loud * spectrum_gain, 0.0, 1.0);
    return energy;
}

/* =================== Camera & Accum =================== */
vec3 color_accum(vec3 ww, vec3 uu, vec3 vv, vec3 ro, vec2 p) {
    float lp = length(p);
    vec2 np = p + p_step;

    float rdd_per = 10.0;
    float term = lp + 0.9 * (0.5 * (cos(rdd_per * p.x) + 1.0)) *
                         (0.5 * (cos(rdd_per * p.y) + 1.0));
    float rdd = 1.75 + 0.75 * pow(lp, 1.5) * tanh_approx(term);

    vec3 rd = normalize(p.x * uu + p.y * vv + rdd * ww);
    vec3 nrd = normalize(np.x * uu + np.y * vv + rdd * ww);

    float nz = floor(ro.z / plane_dist);

    vec3 skyCol = skyColor(ro, rd);

    vec4 acol = vec4(0.0);
    float cutOff = 0.975;
    bool cutOut = false;

    for (int i = 1; i <= furthest; i += 1) {
        float pz = plane_dist * nz + plane_dist * float(i);
        float pd = (pz - ro.z) / rd.z;

        if (pd > 0.0 && acol.w < cutOff) {
            vec3 pp = ro + rd * pd;
            vec3 npp = ro + nrd * pd;

            float aa = 3.0 * length(pp - npp);
            vec3 off = offset(pp.z);

            vec4 pcol = plane(ro, rd, pp, off, aa, nz + float(i));

            float dz = pp.z - ro.z;
            float fdIn = smoothstep(plane_dist * float(furthest), plane_dist * float(fade_from), dz);
            float fdOut = smoothstep(0.0, plane_dist * 0.1, dz);
            pcol.w *= fdOut * fdIn;
            pcol = clamp(pcol, 0.0, 1.0);

            acol = alphaBlend_v4(pcol, acol);
        } else {
            cutOut = true;
            acol.w = (acol.w > cutOff) ? 1.0 : acol.w;
            break;
        }
    }

    vec3 col = alphaBlend_v3(skyCol, acol);
    return col;
}

vec3 main_effect(vec2 p, vec2 pp) {
    float iTime = TIME * time_scale;

    // Original tm rate was: plane_dist * TIME * (71.5 / 60.0) ≈ TIME * 0.2979167
    float base_rate = 0.2979167;

    float drive = 1.0;
    if (time_drive_mode == 0) {
        drive = clamp(time_drive_const, 0.0, 2.0);
    } else if (time_drive_mode == 1) {
        drive = clamp(kick, 0.0, 1.0);                 // ← your existing 'kick'
    } else {
        drive = spectrum_energy();                      // ← use spectrum texture
    }

    // Map drive to a reasonable speed range (50%..200% of base)
    float rate = base_rate * mix(0.5, 2.0, drive);
    float tm = iTime * rate;

    vec3 ro = offset(tm);
    vec3 dro = doffset(tm);
    vec3 ddro = ddoffset(tm);

    vec3 ww = normalize(dro);
    vec3 up = normalize(vec3(0.0, 1.0, 0.0) + ddro);
    vec3 uu = normalize(cross(up, ww));
    vec3 vv = cross(ww, uu);

    vec3 col = color_accum(ww, uu, vv, ro, p);
    col *= smoothstep(1.0, 10.0, TIME);
    col = clamp(col, 0.0, 1.0);
    col = sqrt(col);

    return col;
}

/* =================== Fragment =================== */
void fragment() {
    // Shadertoy-style coords:
    vec2 uv = UV - 0.5;
    uv.y = -uv.y;                                  // Y-up like Shadertoy
    vec2 p_base = uv * 2.0;

    vec2 pp = p_base;
    vec2 p = p_base;
    p.x *= aspect;

    vec3 col = main_effect(p, pp);
    COLOR = vec4(col, 1.0);
}
