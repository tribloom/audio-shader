shader_type canvas_item;
render_mode unshaded;

/* ---------- Visualizer bindings ---------- */
uniform sampler2D spectrum_tex;   // 1 x bar_count, R=current, G=peak
uniform int   bar_count = 64;
uniform float aspect    = 1.7777;

/* ---------- Controls ---------- */
uniform float time_scale = 1.0;     // global speed
uniform bool  audio_enabled = true;
uniform float audio_gain = 1.0;

/* Optional time scrub (replaces iMouse.x) */
uniform bool  use_scrub = false;
uniform float scrub_x   = 0.0;      // 0..1 (mouse.x / viewport.x)
uniform float scrub_strength = 100.0;

/* ---------- Constants ---------- */
//const float PI   = 3.14159265359;
const float HPI  = 1.57079633;
const float SURF_DIST = 0.001;
const int   MAX_STEPS = 72;       // a bit more headroom
const float FAR_DIST  = 10.0;

/* ---------- Helpers ---------- */
float SINf(float x){ return sin(x)*0.5 + 0.5; }
float COSf(float x){ return cos(x)*0.5 + 0.5; }
float S(float x){ return smoothstep(0.0, 1.0, x); }

float spec_at(float u){
    float fb = max(2.0, float(bar_count));
    float idx = clamp(u, 0.0, 1.0) * (fb - 1.0);
    float i0 = floor(idx);
    float t  = fract(idx);
    float tx0 = (i0 + 0.5) / fb;
    float tx1 = (min(i0 + 1.0, fb - 1.0) + 0.5) / fb;
    float h0 = texture(spectrum_tex, vec2(tx0, 0.5)).r;
    float h1 = texture(spectrum_tex, vec2(tx1, 0.5)).r;
    return mix(h0, h1, t);
}

float Fade(float a, float b, float c, float d) {
    float t = TIME * time_scale;
    t = mod(t, 315.0);
    return smoothstep(a, b, t) * smoothstep(d, c, t);
}

mat2 Rot(float a){
    float s = sin(a), c = cos(a);
    return mat2(vec2(c, s), vec2(-s, c)); // column-major
}

vec3 RayDir(vec2 uv, vec3 p, vec3 l, vec3 up, float z){
    vec3 f = normalize(l - p);
    vec3 r = normalize(cross(up, f));
    vec3 u = cross(f, r);
    vec3 c = p + f * z;
    vec3 i = c + uv.x * r + uv.y * u;
    return normalize(i - p);
}

/* Torus SDF & helpers */
float TorusSDF(vec3 p, float bigR, float smallR){
    float circle = length(vec2(length(p.xz) - bigR, p.y));
    return -(circle - smallR); // negative inside
}

float GlowDist(vec3 p, float bigR){
    // distance to animated "neon" circle around torus
    float x = atan(p.x, p.z) + PI;                 // [0..2π]
    float u = fract(x / (2.0*PI) + 0.5);           // [0..1]
    float fft = (audio_enabled ? (audio_gain * spec_at(u)) : 0.0);

    p.y += (fft - 0.5) * 0.4;

    float s = 1.0 + sin(x * 4.0 + TIME * time_scale) * 0.05;
    float circle = length(vec2(length(p.xz * s) - bigR, p.y));
    return circle + 0.8 * 0.001; // thin ring
}

vec3 Nrm(vec3 p, float eps, float bigR, float smallR){
    vec2 e = vec2(eps, 0.0);
    return normalize(vec3(
        TorusSDF(p + e.xyy, bigR, smallR) - TorusSDF(p - e.xyy, bigR, smallR),
        TorusSDF(p + e.yxy, bigR, smallR) - TorusSDF(p - e.yxy, bigR, smallR),
        TorusSDF(p + e.yyx, bigR, smallR) - TorusSDF(p - e.yyx, bigR, smallR)
    ));
}

vec2 TorusUV(vec3 p, float bigR){
    float y = atan(length(p.xz) - bigR, p.y);
    float x = atan(p.x, p.z);
    return vec2(x, y);
}

/* ---------- Main ---------- */
void fragment(){
    vec2 uv = UV - 0.5;
    uv.x *= aspect;

    // time + optional scrub
    float t = TIME * time_scale * 2.0;
    if (use_scrub) t -= scrub_x * scrub_strength;

    float t4  = t / 4.0;
    float t8  = t / 8.0;
    float t16 = t / 16.0;
    float t32 = t / 32.0;

    float fft_pick = audio_enabled ? (audio_gain * spec_at(0.7)) : 0.0;

    // torus radii
    const float BIG_R = 1.0;
    float smallR = mix(0.18, 0.8, S(SINf(t8)));

    // screen twist
    float d_scr = 1.0 - dot(uv, uv);
    float twist = Fade(0.0, 100.0, 200.0, 300.0);
    uv *= Rot(d_scr * 2.0 * twist * sin(t16) * (1.0 - COSf(t32)));

    // camera
    vec3 ro = vec3(0.0, sin(t8) * 0.25 * smallR, -BIG_R - sin(t4) * smallR * 0.3);
    float lookAngle = SINf(-t8);
    vec3 lookDir = vec3(0.0, 0.0, 1.0);
    lookDir.xz *= Rot(lookAngle * HPI);
    float fov = mix(0.5, 0.1 + COSf(t32), Fade(30.0, 60.0, 250.0, 300.0));

    vec2 uv_rot = (Rot(t * 0.1) * uv);
    vec3 rd = RayDir(uv_rot, ro, ro + lookDir, vec3(0,1,0), fov);

    // -------- Sphere tracing (union step) --------
    float dO = 0.0;
    float minGlow = 1e6;
    vec3  glowPos = ro;
    bool  hit = false;

    for (int i = 0; i < MAX_STEPS; i++){
        vec3 p = ro + dO * rd;

        float dS = abs(TorusSDF(p, BIG_R, smallR)); // signed -> unsigned for stepping
        float dG = GlowDist(p, BIG_R);

        // remember closest glow sample for continuous ring
        if (dG < minGlow){
            minGlow = dG;
            glowPos = p;
        }

        float stepd = max(min(dS, dG) * 0.9, 0.0015); // union step + small floor
        dO += stepd;

        if (dS < SURF_DIST){ hit = true; break; }
        if (dO > FAR_DIST)   break;
    }

    // common post
    float vign = 1.0 - dot(uv, uv);
    float bw   = 1.0 - clamp(sin(length(uv) - t * 0.1) * 3.0, 0.0, 1.0);

    vec3 col = vec3(0.0);

    if (hit) {
        vec3 p = ro + dO * rd;
        float eps = max(0.004, dO * 0.002);
        vec3 n = Nrm(p, eps, BIG_R, smallR);

        vec2 tv = TorusUV(p, BIG_R) / (2.0*PI) + 0.5;

        // texture motif
        float tt = (TIME * time_scale);
        tv.y += (tt * 0.05) * Fade(143.5, 143.51, 220.0, 230.0);
        float d_tex = fract((tv.y + tv.x) * 10.0);
        float outline = smoothstep(0.30, 0.28, abs(d_tex - 0.5));
        float swirl   = smoothstep(0.25, 0.20, abs(d_tex - 0.5));
        float hatchUv = (tv.y - tv.x) * 10.0 * PI;
        float hatch   = sin(hatchUv * 20.0 + t4) * SINf(t4);
        hatch        += sin(hatchUv + t) * SINf(t8);

        col += (outline - swirl * hatch) * 0.5;

        // vignette & inversion pulse
        col *= vign;
        col  = mix(col, 1.0 - col, bw);

        // fresnel pop
        float fresnel = -dot(n, rd); fresnel *= fresnel;
        col *= mix(1.0, fresnel * fresnel, SINf(t8 * 0.5674));

        // rainbow phase
        vec3 c = cross(rd, n);
        c.xy *= Rot(t);
        c.zy *= Rot(t4);
        c = c * 0.5 + 0.5;
        c = pow(c, vec3(1.0 + SINf(t4) * 3.0));

        float taste = 0.0;
        taste += Fade(82.0, 83.0, 100.0, 120.0);
        taste += Fade(143.5, 144.5, 170.0, 200.0);
        taste += Fade(205.0, 206.0, 230.0, 260.0);
        col = mix(col, col * c * 3.0, taste);
    } else {
        // if we miss, keep a soft base so the frame doesn't look empty
        col *= vign * 0.0; // essentially black base; ring will add below
    }

    // -------- Continuous neon ring (no dots) --------
    // Gaussian on the closest glow distance we saw along the ray
    float glow_sharp = 80.0;              // higher = thinner ring
    float glow = exp(-minGlow * glow_sharp);
    // subtle color tilt by angle to avoid flat white
    float ax = atan(glowPos.x, glowPos.z) + PI;
    float u  = fract(ax / (2.0*PI));
    vec3 ring_tint = mix(vec3(1.0,0.85,0.8), vec3(0.7,0.85,1.1), u);
    float audio_boost = 0.6 + 0.8 * fft_pick;

    col += ring_tint * glow * audio_boost;

    // optional lightning windowing (kept subtle to avoid speckles)
    float lightning = (fft_pick) * (0.03 / max(minGlow, 1e-4));
    vec3 lightningCol = lightning * mix(vec3(1.0, 0.1, 0.1), vec3(0.1, 0.1, 1.0), bw);

    float fade = 0.0;
    fade += Fade(21.0, 25.0, 50.0, 70.0);
    fade += Fade(82.0, 83.0, 100.0, 120.0);
    fade += Fade(143.5, 144.5, 170.0, 200.0);
    fade += Fade(215.0, 216.0, 230.0, 260.0);
    col += lightningCol * fade;

    // global fade + gamma
    col *= Fade(0.0, 10.0, 290.0, 315.0);
    col *= (1.0 - 0.12 * (1.0 - vign));  // mild vignette
    col = pow(col, vec3(0.4545));
    COLOR = vec4(col, 1.0);
}
