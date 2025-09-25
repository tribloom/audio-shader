shader_type canvas_item;

// UV wrapping fallback (if your texture can't be set to Repeat)
uniform bool wrap_uv = true;

// Gate controls (instead of 0.33..0.66 hard-coded)
uniform float gate_center : hint_range(0.0,1.0) = 0.50;
uniform float gate_width  : hint_range(0.01,1.0) = 0.24;  // broader = smoother
uniform float gate_curve  : hint_range(0.2,4.0) = 1.0;    // >1 hardens, <1 softens

// --- City shaping for the base (from height_tex) ---
uniform float base_thresh_lo    : hint_range(0.0,1.0) = 0.52; // where buildings start
uniform float base_thresh_hi    : hint_range(0.0,1.0) = 0.65; // tighten to reduce “rolling”
uniform float base_sharp        : hint_range(0.5,6.0) = 3.0;  // sharpen after threshold
uniform float base_quant_steps  : hint_range(1.0,32.0) = 12.0;// terrace/voxel steps
uniform float base_gain         : hint_range(0.0,2.0) = 1.2;  // scale base after shaping

/* Bind these from GDScript */
uniform sampler2D height_tex   : hint_default_black; // your "iChannel1"
uniform sampler2D spectrum_tex : hint_default_black; // your audio strip ("iChannel2")

/* View */
uniform float aspect = 1.7777; // set from script

/* Tiny audio controls (keep defaults for "original") */
uniform float audio_weight = 0.8;                 // replaces the hard 0.8
uniform float audio_gate_lo = 0.33;               // replaces 0.33 in smoothstep
uniform float audio_gate_hi = 0.66;               // replaces 0.66 in smoothstep
uniform int   fft_smooth = 0;                     // 0 = raw, 1..6 = mild smoothing

/* ==== Original constants (unchanged) ==== */
#define PI   3.141592654
#define TAU  (2.0*PI)
const vec3  LightDir0  = normalize(vec3(2.0, 2.0, 1.0));
const int   MaxIter    = 40;
const float Bottom     = 0.0;
const float MinHeight  = 0.25;
const float MaxHeight  = 7.0;
const float sz         = 0.475;
const float eps        = 1e-3;

vec2 WRAP(vec2 uv){ return wrap_uv ? fract(uv) : uv; }



/* ==== Original helpers ==== */
float tanh_approx(float x) {
    float x2 = x*x;
    return clamp(x*(27.0 + x2)/(27.0 + 9.0*x2), -1.0, 1.0);
}
vec2 rayBox(vec3 ro, vec3 rd, vec3 boxSize, out vec3 outNormal )  {
    vec3 m = 1.0/rd;
    vec3 n = m*ro;
    vec3 k = abs(m)*boxSize;
    vec3 t1 = -n - k;
    vec3 t2 = -n + k;
    float tN = max( max( t1.x, t1.y ), t1.z );
    float tF = min( min( t2.x, t2.y ), t2.z );
    if( tN>tF || tF<0.0) return vec2(-1.0);
    outNormal = (tN>0.0) ? step(vec3(tN),t1) : step(t2,vec3(tF));
    outNormal *= -sign(rd);
    return vec2( tN, tF );
}

/* ==== Texture reads ==== */
float tex1(vec2 uv){ return texture(height_tex, WRAP(uv)).r; }
float tex2_raw(vec2 uv){ return texture(spectrum_tex, WRAP(uv)).r; }
float tex2_smooth(vec2 uv) {
    if (fft_smooth <= 0) return tex2_raw(uv);
    float du = 1.0 / 512.0; // typical; fine if different
    int N = min(fft_smooth, 6);
    float acc = 0.0, w = 0.0;
    for (int i = -6; i <= 6; i++) {
        if (i < -N || i > N) continue;
        float wi = 1.0;
        acc += wi * tex2_raw(vec2(clamp(uv.x + float(i)*du, 0.0, 1.0), uv.y));
        w   += wi;
    }
    return (w > 0.0) ? acc / w : tex2_raw(uv);
}

/* ==== Original field & shading with tiny audio knobs ==== */
float select(vec2 p) {
    p *= 0.00125;
    float h = tex1(p);
    return (h - 0.5) * 2.0;
}
vec3 baseCol(vec2 p) {
    float h = select(p);
    vec3 sc = h > 0.0 ? vec3(0.1) : vec3(1.0, 0.0, 0.0);
    return mix(vec3(1.0), sc, smoothstep(0.33, 0.66, abs(h)));
}

float height_fn(vec2 p) {
    float s = select(p);

    // ----- BASE (city) from height_tex -----
    // sample like the original
    float c = clamp(gate_center, 0.0, 1.0);
    float w = max(gate_width, 0.001);
    float fs = smoothstep(c - 0.5*w, c + 0.5*w, abs(s));
    vec2  ps = p * 0.001;
    float h0 = tex1(ps);          // 0..1 gray noise
    h0 *= h0;                     // original squaring
    h0 *= smoothstep(-2.0, 0.9, w);
    h0  = smoothstep(0.0, 0.75, h0);

    // city shaping: threshold -> sharpen -> quantize (terraces)
    float b  = smoothstep(base_thresh_lo, base_thresh_hi, h0);
    b = pow(b, base_sharp);
    if (base_quant_steps > 1.0) {
        b = floor(b * base_quant_steps) / base_quant_steps;
    }
    b *= base_gain;                         // slight lift
    b = clamp(b, 0.0, 1.0);

    // ----- AUDIO (same sampling path, mild shaping) -----

    fs = pow(fs, gate_curve);  // optional shaping


    vec2  fp = 20.0 * ps;
    float u  = 0.1 + 0.8 * fract(fp.x + 0.25*fp.y + 0.25*sign(s));
    float fft = tex2_smooth(vec2(u, 0.25));   // your smoothed spectrum
    fft = max(fft - 0.3, 0.0);
    fft *= fft;                               // emphasize peaks
    fft = 1.25 * smoothstep(0.0, 0.28, fft);  // original knee

    // blend: city base with occasional audio peaks on top
    float h = max(b, mix(b, fft, audio_weight * fs));

    // map to world, keep the original *0.5 scale
    return mix(MinHeight, MaxHeight, clamp(h, 0.0, 1.0)) * 0.5;
}


float cellTrace(
    vec3 ro, vec3 rd, float nearT, float farT,
    out int   iter,
    out vec2  cell,
    out vec2  boxi,
    out vec3  boxn
) {
    vec2 rd2  = rd.xz;
    vec2 ird2 = 1.0/rd.xz;
    vec2 stp  = step(vec2(0.0), rd2);

    float ct = nearT;
    iter = MaxIter;
    vec2 bi = vec2(-1.0);
    vec3 bn = vec3(0.0);
    vec2 np2 = vec2(0.0);
    float ft = farT;

    for (int i = 0; i < MaxIter; ++i) {
        vec3 cp = ro+rd*ct;
        np2 = floor(cp.xz);
        float h = height_fn(np2);
        vec3 bdim = vec3(sz, h, sz);
        vec3 coff = vec3(np2.x+0.5, h, np2.y+0.5);
        vec3 bro = ro-coff;
        bi = rayBox(bro, rd, bdim, bn);

        if (bi.x> 0.0) {
            float bt = bi.x;
            if (bt >= farT) break;
            ft = bt;
            iter = i;
            break;
        }

        vec2 dif = np2 - cp.xz;
        dif += stp;
        dif *= ird2;
        float dt = min(dif.x, dif.y);
        ct += dt+eps;

        if (ct >= farT) break;
    }
    cell = np2;
    boxi = bi;
    boxn = bn;
    return ft;
}

vec3 render(vec3 ro, vec3 rd) {
    vec3 sky = vec3(1.0);

    float skyt = 1e3;
    float bottom  = -(ro.y-Bottom)/rd.y;
    float nearT   = -(ro.y-(MaxHeight))/rd.y;
    float farT    = bottom >= 0.0 ? bottom : skyt;

    int iter; vec2 cell; vec2 boxi; vec3 boxn;
    float ct = cellTrace(ro, rd, nearT, farT, iter, cell, boxi, boxn);
    if (ct == skyt) return sky;

    vec3 p = ro + ct*rd;

    int siter; vec2 scell; vec2 sboxi; vec3 sboxn;
    float sfar  = -(p.y-MaxHeight)/LightDir0.y;
    float sct   = cellTrace((p-2.0*eps*rd), LightDir0, eps, sfar, siter, scell, sboxi, sboxn);

    vec3 n = vec3(0.0, 1.0, 0.0);
    vec3 bcol = vec3(0.5);

    if (iter < MaxIter) {
        n = boxn;
        bcol = baseCol(cell);
        bcol *= smoothstep(0.0, 0.1, boxi.y-boxi.x);
    }
    float dif0 = max(dot(n, LightDir0), 0.0);
    dif0 = sqrt(dif0);
    float sf = siter < MaxIter ? tanh_approx(0.066*sct) : 1.0;
    bcol *= mix(0.3, 1.0, dif0*sf);

    vec3 col = bcol;
    col = mix(col, sky, 1.0-exp(-0.125*max(ct-50.0, 0.0)));
    return col;
}

/* ==== Camera (same math as source) ==== */
vec3 effect(vec2 p, vec2 pp) {
    float fov = tan(TAU/6.0);

    // ABOVE the grid (same forward), Shadertoy style
    vec3 ro = 4.0 * vec3(0.0, 4.0, -4.0);
    ro.z += 2.0 * TIME;

    const vec3 up = vec3(0.0, 1.0, 0.0);
    const vec3 ww = normalize(vec3(0.5,-1., 1.0));
    vec3 uu = normalize(cross(up, ww));
    vec3 vv = cross(ww,uu);
    vec3 rd = normalize(-p.x*uu + p.y*vv + fov*ww);

    vec3 col = render(ro, rd);
    col -= 0.1;
    col *= 1.1;
    col = clamp(col, 0.0, 1.0);
    col = sqrt(col);
    return col;
}

void fragment() {
    // *** IMPORTANT: flip Y to match Shadertoy’s bottom-left origin ***
    vec2 q = vec2(UV.x, 1.0 - UV.y);

    vec2 p = -1.0 + 2.0 * q;
    vec2 pp = p;
    p.x *= aspect;

    COLOR = vec4(effect(p, pp), 1.0);
}
