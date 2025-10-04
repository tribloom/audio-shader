shader_type canvas_item;

/* =================== Controls =================== */
uniform float time_scale : hint_range(0.0, 5.0) = 1.0;
uniform float gamma_power : hint_range(0.2, 2.2) = 0.65;
uniform float aspect = 1.7777778;                  // width / height (set from GDScript)

/* Animation (choose how time behaves) */
uniform int   anim_mode = 2;                       // 0=LOOP, 1=PINGPONG, 2=INFINITE
uniform float cycle_len = 62.8318;                 // seconds (used by modes 0/1)

/* Optional audio tint */
uniform bool use_audio = false;                    // off by default
uniform sampler2D spectrum_tex : hint_default_black;
uniform int   audio_bands = 64;                    // bins to read across X
uniform float audio_gain  : hint_range(0.0, 4.0) = 1.2;
uniform float audio_lo    : hint_range(0.0, 1.0) = 0.00; // 0=bass edge
uniform float audio_hi    : hint_range(0.0, 1.0) = 1.00; // 1=treble edge
uniform bool  audio_use_max = true;                // true = dominant band, false = centroid
uniform float hue_lo = 0.00;                       // red
uniform float hue_hi = 0.83;                       // violet (~300°)

/* =================== Constants =================== */
const float EPS = 0.0005;

/* =================== Math Helpers =================== */
mat2 r2(float r) {
    float c = cos(r);
    float s = sin(r);
    // column-major rotation
    return mat2(vec2(c, s), vec2(-s, c));
}

float bo(vec3 p, vec3 r) {
    vec3 ap = abs(p) - r;
    float mx = max(ap.x, ap.y);
    mx = max(mx, ap.z);
    return mx;
}

/* =================== Time (no hard reset) =================== */
void compute_anim(float iTime, out float tt, out float cam_blend) {
    float t = iTime;
    if (anim_mode == 0) {
        tt = t;                         // LOOP
    } else if (anim_mode == 1) {
        float u = fract(t / max(cycle_len, 0.0001));
        float tri = 1.0 - abs(u * 2.0 - 1.0); // 1..0..1
        tt = tri * cycle_len;                // PING-PONG
    } else {
        tt = t;                         // INFINITE
    }
    float phase = (anim_mode == 2) ? t * 0.5 : tt * 0.5;
    cam_blend = 0.5 + 0.5 * sin(phase); // 0..1 smooth
}

/* =================== Audio Helpers =================== */
vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(0.0, 0.6666667, 0.3333333)) * 6.0 - 3.0);
    vec3 rgb = clamp(p - 1.0, 0.0, 1.0);
    return c.z * mix(vec3(1.0, 1.0, 1.0), rgb, c.y);
}

/* Reads the spectrum and outputs a tint color + strength (0..1).
   Bass → red (hue_lo), Treble → violet (hue_hi). */
void compute_audio_tint(out vec3 tint_rgb, out float strength) {
    if (!use_audio) {
        tint_rgb = vec3(1.0, 0.75, 0.2); // gold default
        strength = 0.0;
        return;
    }

    int   N  = max(audio_bands, 4);
    float lo = clamp(audio_lo, 0.0, 1.0);
    float hi = clamp(audio_hi, lo + 0.001, 1.0);

    float sum  = 0.0;
    float wsum = 0.0;
    float vmax = 0.0;
    float umax = 0.0;

    // Sample middle row (v=0.5) across X
    for (int i = 0; i < 256; i++) {
        if (i >= N) break;
        float u = (N > 1) ? float(i) / float(N - 1) : 0.0;
        float x = mix(lo, hi, u);
        float v = texture(spectrum_tex, vec2(x, 0.5)).r;

        v = max(v, 0.0);
        v = sqrt(v);          // mild companding to reveal mids/highs

        sum  += v;
        wsum += v * u;

        if (v > vmax) {
            vmax = v;
            umax = u;
        }
    }

    float u_sel = audio_use_max ? umax : ((sum > 0.0) ? (wsum / sum) : 0.0);
    float hue   = mix(hue_lo, hue_hi, u_sel);

    float loud = (N > 0) ? (sum / float(N)) : 0.0;
    strength   = clamp(loud * audio_gain, 0.0, 1.0);

    tint_rgb = hsv2rgb(vec3(hue, 1.0, 1.0));
}

/* =================== Scene SDF + mats + glow =================== */
/* Returns:
   x = distance, y = material id, z = glow g_accum, w = glow g2_accum */
vec4 mp_full(vec3 p, float tt) {
    float b = 0.0;
    float bb = 0.0;

    vec3 pp = p;
    vec3 bp = p;

    // Twist
    vec2 yz1 = r2(sin(pp.x * 0.3 - tt * 0.5) * 0.4) * p.yz;
    p.y = yz1.x;
    p.z = yz1.y;
    bp.y = p.y;     // bp picks up twist (matches original intent)
    bp.z = p.z;

    // Rotate whole scene
    vec2 yz2 = r2(1.57) * p.yz;
    p.y = yz2.x;
    p.z = yz2.y;

    b  = sin(pp.x * 0.2 + tt);
    bb = cos(pp.x * 0.2 + tt);

    // Tiling along X
    p.x = mod(p.x - tt * 2.0, 10.0) - 5.0;

    // Mandelbox-ish fold with scale tracker in .w
    vec4 np4 = vec4(p * 0.4, 0.4);
    for (int i = 0; i < 4; i++) {
        np4.xyz = abs(np4.xyz) - vec3(1.0, 1.2, 0.0);
        np4.xyz = 2.0 * clamp(np4.xyz, -vec3(0.0, 0.0, 0.0), vec3(2.0, 0.0, 4.3 + bb)) - np4.xyz;
        float d2 = clamp(dot(np4.xyz, np4.xyz), 0.1, 0.92);
        np4 = np4 * 1.3 / d2;
    }

    // fb() inline — stack (distance, mat)
    vec3 q = abs(np4.xyz) - vec3(2.0, 0.0, 0.0);
    vec3 p_fb = q;
    p_fb.y += bb * 0.05;

    vec2 t = vec2(bo(p_fb, vec3(5.0, 1.0, 3.0)), 3.0);
    t.x = max(t.x, -(length(p_fb) - 2.5));
    t.x = max(abs(t.x) - 0.2, (p_fb.y - 0.4));

    vec2 h = vec2(bo(p_fb, vec3(5.0, 1.0, 3.0)), 6.0);
    h.x = max(h.x, -(length(p_fb) - 2.5));
    h.x = max(abs(h.x) - 0.1, (p_fb.y - 0.5));
    t = (t.x < h.x) ? t : h;

    h = vec2(bo(p_fb + vec3(0.0, 0.4, 0.0), vec3(5.4, 0.4, 3.4)), 5.0);
    h.x = max(h.x, -(length(p_fb) - 2.5));
    t = (t.x < h.x) ? t : h;

    h = vec2(length(p_fb) - 2.0, 5.0);
    t = (t.x < h.x) ? t : h;

    t.x *= 0.7;
    t.x /= np4.w;
    t.x = max(t.x, bo(p, vec3(5.0, 5.0, 10.0)));

    // Second larger fractal
    np4 *= 0.5;
    vec2 yz3 = r2(0.785) * np4.yz;
    np4.y = yz3.x;
    np4.z = yz3.y;
    np4.yz += 2.5;

    vec3 q2 = abs(np4.xyz) - vec3(0.0, 4.5, 0.0);
    vec3 p_fb2 = q2;
    p_fb2.y += bb * 0.05;

    vec2 h2 = vec2(bo(p_fb2, vec3(5.0, 1.0, 3.0)), 7.0);
    h2.x = max(h2.x, -(length(p_fb2) - 2.5));
    h2.x = max(abs(h2.x) - 0.1, (p_fb2.y - 0.5));

    vec2 t2 = h2;
    t2.x = max(t2.x, -bo(p, vec3(20.0, 5.0, 5.0)));
    t2.x /= (np4.w * 1.5);
    t = (t.x < t2.x) ? t : t2;

    // Sweeper glow (adds to g2)
    vec2 h3 = vec2(bo(np4.xyz, vec3(0.0, b * 20.0, 0.0)), 6.0);
    h3.x /= (np4.w * 1.5);
    float g2_add = 0.1 / (0.1 * h3.x * h3.x * (1000.0 - b * 998.0));
    t = (t.x < h3.x) ? t : h3;

    // Terrain (uses bp for twisted Y)
    vec2 h4 = vec2(0.6 * bp.y + sin(p.y * 5.0) * 0.03, 6.0);
    t = (t.x < h4.x) ? t : h4;

    // Particles (adds to g)
    vec2 h5 = vec2(length(cos(bp * 0.6 + vec3(tt, tt, 0.0))) + 0.003, 6.0);
    float g_add = 0.1 / (0.1 * h5.x * h5.x * 4000.0);
    t = (t.x < h5.x) ? t : h5;

    return vec4(t.x, t.y, g_add, g2_add);
}

/* Distance-only (for normals/AO/SSS) */
vec2 mp_dist(vec3 p, float tt) {
    float b = 0.0;
    float bb = 0.0;

    vec3 pp = p;

    vec2 yz1 = r2(sin(pp.x * 0.3 - tt * 0.5) * 0.4) * p.yz;
    p.y = yz1.x;
    p.z = yz1.y;

    vec2 yz2 = r2(1.57) * p.yz;
    p.y = yz2.x;
    p.z = yz2.y;

    b  = sin(pp.x * 0.2 + tt);
    bb = cos(pp.x * 0.2 + tt);

    p.x = mod(p.x - tt * 2.0, 10.0) - 5.0;

    vec4 np4 = vec4(p * 0.4, 0.4);
    for (int i = 0; i < 4; i++) {
        np4.xyz = abs(np4.xyz) - vec3(1.0, 1.2, 0.0);
        np4.xyz = 2.0 * clamp(np4.xyz, -vec3(0.0, 0.0, 0.0), vec3(2.0, 0.0, 4.3 + bb)) - np4.xyz;
        float d2 = clamp(dot(np4.xyz, np4.xyz), 0.1, 0.92);
        np4 = np4 * 1.3 / d2;
    }

    vec3 q = abs(np4.xyz) - vec3(2.0, 0.0, 0.0);
    vec3 p_fb = q;
    p_fb.y += bb * 0.05;

    float d = bo(p_fb, vec3(5.0, 1.0, 3.0));
    d = max(d, -(length(p_fb) - 2.5));
    d = max(abs(d) - 0.2, (p_fb.y - 0.4));

    float d2b = bo(p_fb, vec3(5.0, 1.0, 3.0));
    d2b = max(d2b, -(length(p_fb) - 2.5));
    d2b = max(abs(d2b) - 0.1, (p_fb.y - 0.5));
    d = min(d, d2b);

    float d3 = bo(p_fb + vec3(0.0, 0.4, 0.0), vec3(5.4, 0.4, 3.4));
    d3 = max(d3, -(length(p_fb) - 2.5));
    d = min(d, d3);

    float d4 = length(p_fb) - 2.0;
    d = min(d, d4);

    d *= 0.7;
    d /= np4.w;
    d = max(d, bo(p, vec3(5.0, 5.0, 10.0)));

    np4 *= 0.5;
    vec2 yz3 = r2(0.785) * np4.yz;
    np4.y = yz3.x;
    np4.z = yz3.y;
    np4.yz += 2.5;

    float d5 = bo(abs(np4.xyz) - vec3(0.0, 4.5, 0.0), vec3(5.0, 1.0, 3.0));
    d5 = max(d5, -(length(abs(np4.xyz) - vec3(0.0, 4.5, 0.0)) - 2.5));
    d5 = max(d5, -bo(p, vec3(20.0, 5.0, 5.0)));
    d5 /= (np4.w * 1.5);
    d = min(d, d5);

    float d6 = bo(np4.xyz, vec3(0.0, b * 20.0, 0.0));
    d6 /= (np4.w * 1.5);
    d = min(d, d6);

    float d7 = 0.6 * p.y + sin(p.y * 5.0) * 0.03;
    d = min(d, d7);

    float d8 = length(cos(p * 0.6 + vec3(tt, tt, 0.0))) + 0.003;
    d = min(d, d8);

    return vec2(d, 0.0);
}

/* =================== bp.y for color mixes =================== */
float compute_bp_y(vec3 p, float tt) {
    vec2 yz1 = r2(sin(p.x * 0.3 - tt * 0.5) * 0.4) * p.yz;
    return yz1.x;
}

/* =================== Raymarch =================== */
vec4 tr(vec3 ro, vec3 rd, float tt) {
    float t = 0.1;
    float mat_id = 0.0;
    float g_sum = 0.0;
    float g2_sum = 0.0;

    for (int i = 0; i < 128; i++) {
        vec3 pos = ro + rd * t;
        vec4 h = mp_full(pos, tt);
        float d = h.x;
        g_sum += h.z;
        g2_sum += h.w;
        if (d < 0.0001 || t > 40.0) {
            mat_id = h.y;
            break;
        }
        t += d;
        mat_id = h.y;
    }

    if (t > 40.0) {
        mat_id = 0.0;
    }
    return vec4(t, mat_id, g_sum, g2_sum);
}

/* =================== AO / SSS =================== */
float ao_func(vec3 pos, vec3 nor, float tt, float d) {
    float m = mp_dist(pos + nor * d, tt).x / d;
    float c = clamp(m, 0.0, 1.0);
    return c;
}

float sss_func(vec3 pos, vec3 ldir, float tt, float d) {
    float m = mp_dist(pos + ldir * d, tt).x / d;
    float s = smoothstep(0.0, 1.0, m);
    return s;
}

/* =================== Fragment =================== */
void fragment() {
    // Centered UV, Y-up, aspect-corrected
    vec2 uv = UV - 0.5;
    uv.y = -uv.y;
    uv.x *= aspect;

    float iTime = TIME * time_scale;
    float tt = 0.0;
    float cam_blend = 0.0;
    compute_anim(iTime, tt, cam_blend);

    // Camera (continuous blend)
    vec3 cam_a = vec3(1.0, 1.0, 1.0);
    vec3 cam_b = vec3(-0.5, 1.0, -1.0);
    vec3 cam_base = mix(cam_a, cam_b, cam_blend);

    float cam_y = 2.8 + 0.75 * smoothstep(-1.5, 1.5, 1.5 * cos(tt + 0.2));
    float cam_z = cos(tt * 0.3) * 3.1;
    vec3 ro = cam_base * vec3(10.0, cam_y, cam_z);

    vec3 target = vec3(0.0, 0.0, 0.0);
    vec3 cw = normalize(target - ro);
    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 cu = normalize(cross(cw, up));
    vec3 cv = normalize(cross(cu, cw));
    vec3 rd = normalize(mat3(cu, cv, cw) * vec3(uv, 0.5));

    vec3 ld = normalize(vec3(0.2, 0.4, -0.3));

    // Background
    float vign = length(uv) * 0.1;
    vec3 fo = vec3(0.1, 0.2, 0.3) - vign - rd.y * 0.2;
    vec3 co = fo;

    // Trace
    vec4 cast = tr(ro, rd, tt);
    float t = cast.x;
    float mat_id = cast.y;
    float g_sum = cast.z;
    float g2_sum = cast.w;

    if (mat_id > 0.0) {
        vec3 po = ro + rd * t;

        // Central-difference normal
        float dx1 = mp_dist(po + vec3(EPS, 0.0, 0.0), tt).x;
        float dx2 = mp_dist(po - vec3(EPS, 0.0, 0.0), tt).x;
        float dy1 = mp_dist(po + vec3(0.0, EPS, 0.0), tt).x;
        float dy2 = mp_dist(po - vec3(0.0, EPS, 0.0), tt).x;
        float dz1 = mp_dist(po + vec3(0.0, 0.0, EPS), tt).x;
        float dz2 = mp_dist(po - vec3(0.0, 0.0, EPS), tt).x;
        vec3 no = normalize(vec3(dx1 - dx2, dy1 - dy2, dz1 - dz2));

        float bp_y = compute_bp_y(po, tt);

        // Base albedo by material id
        vec3 al = mix(vec3(0.1, 0.2, 0.4), vec3(0.1, 0.4, 0.7), 0.5 + 0.5 * sin(bp_y * 7.0));
        if (mat_id < 5.0) {
            al = vec3(0.0, 0.0, 0.0);
        }
        if (mat_id > 5.0) {
            al = vec3(1.0, 1.0, 1.0);
        }
        if (mat_id > 6.0) {
            // GOLD material with optional audio color surge
            vec3 c1 = vec3(1.0, 0.5, 0.0);
            vec3 c2 = vec3(0.9, 0.3, 0.1);
            vec3 gold = mix(c1, c2, 0.5 + 0.5 * sin(bp_y * 7.0));

            vec3 audio_tint = gold;
            float audio_strength = 0.0;
            compute_audio_tint(audio_tint, audio_strength);

            // Strong but tasteful mix; raise gain if you want more punch
            al = mix(gold, audio_tint, clamp(audio_strength, 0.0, 1.0));
        }

        float dif = max(0.0, dot(no, ld));
        float fr = pow(1.0 + dot(no, rd), 4.0);
        float sp = pow(max(dot(reflect(-ld, no), -rd), 0.0), 40.0);

        vec3 dir_tint = mix(vec3(0.8, 0.8, 0.8), vec3(1.0, 1.0, 1.0), abs(rd));
        float ao = ao_func(po, no, tt, 0.1) * ao_func(po, no, tt, 0.2) + 0.2;
        float sss = sss_func(po, ld, tt, 2.0);

        vec3 lit = sp + dir_tint * al * ao * (dif + sss);
        co = mix(fo, lit, min(fr, 0.2));

        float fog = exp(-0.0003 * t * t * t);
        co = mix(fo, co, fog);
    }

    /* ---- Glow color (also audio-reactive) ---- */
    float bp_y_for_glow = 0.0;
    if (mat_id > 0.0) {
        bp_y_for_glow = compute_bp_y(ro + rd * t, tt);
    }
    vec3 base_glow = mix(vec3(1.0, 0.5, 0.0), vec3(0.9, 0.3, 0.1),
                         0.5 + 0.5 * sin(bp_y_for_glow * 3.0));

    vec3 glow_audio_tint = base_glow;
    float glow_audio_strength = 0.0;
    compute_audio_tint(glow_audio_tint, glow_audio_strength);

    // Slightly milder influence on glow
    vec3 glow_tint = mix(base_glow, glow_audio_tint, clamp(glow_audio_strength * 0.9, 0.0, 1.0));

    // Final compose
    vec3 final_rgb = co + g_sum * 0.2 + g2_sum * glow_tint;
    final_rgb = pow(final_rgb, vec3(gamma_power));
    COLOR = vec4(final_rgb, 1.0);
}
