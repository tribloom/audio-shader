shader_type canvas_item;
render_mode unshaded;

/* --------- Inputs you provide --------- */
uniform vec2  iResolution = vec2(1920.0, 1080.0); // set from GDScript each frame
uniform float aspect      = 1.7777778;             // width / height (you already set this)

/* Replace iChannel* bits from Shadertoy */
uniform bool  audio_enabled = false;  // acts like (iChannelTime[0] > 0.)
uniform float audio_a       = 0.60;   // ~ texelFetch(iChannel0, ivec2(128,0), 0).r
uniform float audio_b       = 1.00;   // ~ texelFetch(iChannel0, ivec2(32, 0), 0).r
uniform float music_time    = 0.0;    // if > 0, used instead of TIME for “mt”

/* March tuning (exposed so you can tame banding) */
uniform int   max_iter       = 120;              // more = smoother, slower
uniform float pixel_epsilon  = 0.0006666666666666667;     // orig was 1/1000; smaller reduces stepping
uniform float jitter_strength= 0.0006;           // 0 to disable tiny per-pixel jitter

/* Constants from the source */
const float FAR  = 1e3;
const float INFY = 1e32;
const float FOV  = 70.0;

/* ---------------- Noise / FBM (exact smoothing as source) ---------------- */
float hash12(vec2 p) {
    float h = dot(p, vec2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

/* Exact interpolation used in 4t2cR1:
   u = 1 + (fract(p)-1)^5  (replaces the GLSL --f trick) */
float noise_3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);

    vec3 g = f - 1.0;
    vec3 u = 1.0 + g*g*g*g*g;

    vec2 ii = i.xy + i.z * vec2(5.0);

    float a = hash12(ii + vec2(0.0, 0.0));
    float b = hash12(ii + vec2(1.0, 0.0));
    float c = hash12(ii + vec2(0.0, 1.0));
    float d = hash12(ii + vec2(1.0, 1.0));
    float v1 = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);

    ii += vec2(5.0);
    a = hash12(ii + vec2(0.0, 0.0));
    b = hash12(ii + vec2(1.0, 0.0));
    c = hash12(ii + vec2(0.0, 1.0));
    d = hash12(ii + vec2(1.0, 1.0));
    float v2 = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);

    return max(mix(v1, v2, u.z), 0.0);
}

float fbm(vec3 x) {
    float r = 0.0;
    float w = 1.0, s = 1.0;
    for (int i = 0; i < 4; i++) {
        w *= 0.25;
        s *= 3.0;
        r += w * noise_3(s * x);
    }
    return r;
}

float yC(float x) {
    return cos(x * -0.134) * sin(x * 0.13) * 15.0
         + fbm(vec3(x * 0.1, 0.0, 0.0) * 55.4);
}

void pR(inout vec2 p, float a) { p = cos(a)*p + sin(a)*vec2(p.y, -p.x); }

/* ---------------- Scene (as source) ---------------- */
float fCylinderInf(vec3 p, float r) { return length(p.xz) - r; }

float map_sdf(vec3 p) {
    p.x -= yC(p.y * 0.1) * 3.0;
    p.z += yC(p.y * 0.01) * 4.0;

    float n = pow(abs(fbm(p * 0.06)) * 12.0, 1.3);
    float s = fbm(p * 0.01 + vec3(0.0, TIME * 0.14, 0.0)) * 128.0;

    float d = max(0.0, -fCylinderInf(p, s + 18.0 - n));

    p.x -= sin(p.y * 0.02) * 34.0 + cos(p.z * 0.01) * 62.0;

    d = max(d, -fCylinderInf(p, s + 28.0 + n * 2.0));
    return d; // ≥ 0 inside, 0 at the wall
}

/* ---------------- SOR/adaptive stepper (ported) ---------------- */
const float T_MIN = 10.0;
const float T_MAX = FAR;

vec2 trace_tunnel(vec3 o, vec3 d, float px_eps) {
    float omega = 1.3;
    float t = T_MIN;
    float candidate_error = INFY;
    float candidate_t = T_MIN;
    float previousRadius = 0.0;
    float stepLength = 0.0;

    float functionSign = (map_sdf(o) < 0.0) ? -1.0 : 1.0;
    float iters = 0.0;

    for (int i = 0; i < max_iter; ++i) {
        iters = float(i);
        float signedRadius = functionSign * map_sdf(d * t + o);
        float radius = abs(signedRadius);

        bool sorFail = (omega > 1.0) && ((radius + previousRadius) < stepLength);

        if (sorFail) { stepLength -= omega * stepLength; omega = 1.0; }
        else         { stepLength  = signedRadius * omega; }

        previousRadius = radius;

        float error = radius / max(t, 1e-6);

        if (!sorFail && error < candidate_error) { candidate_t = t; candidate_error = error; }

        if ((!sorFail && error < px_eps) || t > T_MAX) break;

        t += stepLength * 0.5; // as in source
    }

    if (t > T_MAX || candidate_error > px_eps) return vec2(INFY, iters);
    return vec2(candidate_t, iters);
}

/* ---------------- Main ---------------- */
void fragment() {
    // Pixel coords like Shadertoy
    vec2 fragCoord = UV * iResolution;
    vec2 ouv = fragCoord / iResolution;
    vec2 uv  = ouv - 0.5;

    // optional tiny jitter to hide residual stepping
    if (jitter_strength > 0.0) {
        float j = hash12(fragCoord) - 0.5;
        uv += j * jitter_strength;
    }

    // FOV mapping (same as source)
    uv *= tan(radians(FOV) * 0.5) * 4.0;

    float T = TIME;
    vec3 vuv = normalize(vec3(cos(T), sin(T * 0.11), sin(T * 0.41))); // up
    vec3 ro  = vec3(0.0, 30.0 + T * 100.0, -0.1);

    // match map offsets (critical to stay centered)
    ro.x += yC(ro.y * 0.1) * 3.0;
    ro.z -= yC(ro.y * 0.01) * 4.0;

    vec3 vrp = vec3(0.0, 50.0 + T * 100.0, 2.0);
    vrp.x += yC(vrp.y * 0.1) * 3.0;
    vrp.z -= yC(vrp.y * 0.01) * 4.0;

    vec3 vpn = normalize(vrp - ro);
    vec3 u   = normalize(cross(vuv, vpn));
    vec3 v   = cross(vpn, u);

    vec3 vcv = ro + vpn;
    vec3 scr = vcv + uv.x * u * (iResolution.x / iResolution.y) + uv.y * v;
    vec3 rd  = normalize(scr - ro);

    // pixel-space epsilon (scaled a bit by resolution for consistency)
    float px_eps = pixel_epsilon * (1920.0 / max(1.0, iResolution.x));

    // march
    vec2 tr     = trace_tunnel(ro, rd, px_eps);
    float t_hit = tr.x;
    float iters = tr.y;
    vec3  hit   = ro + rd * t_hit;

    // shading (ported)
    vec3 col = vec3(1.0, 0.5, 0.4) * fbm(hit.xzy * 0.01) * 20.0;
    col.b   *= fbm(hit * 0.01) * 10.0;

    vec3 scene = vec3(0.0);
    scene += min(0.8, iters / 90.0) * col + col * 0.03;
    scene *= 1.0 + 0.9 * (abs(fbm(hit * 0.002 + 3.0) * 10.0) * fbm(vec3(0.0, 0.0, TIME * 0.05) * 2.0));

    // audio gates replacing iChannel0 sampling
    float mt = (music_time > 0.0) ? music_time : TIME;
    float audio_gate = audio_enabled ? (audio_a * min(1.0, mt * 0.1)) : 0.6;
    scene = pow(scene, vec3(1.0)) * audio_gate;

    // steam pass (ported)
    vec3 steamColor1 = vec3(0.0, 0.4, 0.5);
    vec3 rro;
    vec3 ro2 = hit;

    float distC = t_hit, f = 0.0;
    for (int i = 0; i < 24; i++) {
        rro = ro2 - rd * distC;
        f  += fbm(rro * vec3(0.1, 0.1, 0.1) * 0.3) * 0.1;
        distC -= 3.0;
        if (distC < 3.0) break;
    }

    steamColor1 *= audio_enabled ? audio_b : 1.0;
    scene += steamColor1 * pow(abs(f * 1.5), 3.0) * 4.0;

    // vignette-ish fade like source
    vec2 uv_fov = uv; // post-jitter, post-FOV
    vec3 out_col = clamp(scene * (1.0 - length(uv_fov) / 2.0), 0.0, 1.0);

    // final grade (guard against INFY/NaN)
    float denom = max(t_hit, 1.0);
    vec4 frag = vec4(out_col, 1.0);
    frag = pow(abs(frag / denom * 130.0), vec4(0.8));

    COLOR = frag;
}
