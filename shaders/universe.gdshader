shader_type canvas_item;
render_mode unshaded;

/*
Universe (hardened + grading + optional audio)
- Adds time wrap, spectrum guards, fold clamps, NaN guards, capped march speed.
- Adds grading controls to bias back toward blue/green.
*/

/* ===== Inputs ===== */
uniform sampler2D spectrum_tex;     // 1 x bar_count (R=current, G=peak)
uniform int   bar_count = 64;
uniform float aspect    = 1.7777;   // viewport width / height

/* --- Artistic controls --- */
uniform float time_scale = 1.0;     // global speed
uniform float time_wrap  : hint_range(0.0, 1800.0, 10.0) = 720.0; // seconds, 0 = off
uniform float brightness = 1.0;     // final brightness gain
uniform float gamma_curve = 1.2;    // post gamma/exponent

/* Iteration controls */
uniform int steps = 56;             // <= MAX_STEPS (outer)
uniform int folds = 6;              // <= MAX_FOLDS (inner)
const int MAX_STEPS = 72;
const int MAX_FOLDS = 7;

/* --- Optional audio (OFF by default) --- */
uniform float audio_amount = 0.0;   // 0 = off, 0.2..0.5 = subtle
uniform float kick_in  = 0.0;       // smoothed bass (0..1)
uniform float kick_env = 0.0;       // onset envelope (0..1)
uniform float ring_age = 1.0;       // 0..1; 0 right after kick

/* Ring overlay (disabled by default) */
uniform bool  ring_enable = false;
uniform float ring_near  = 0.10;
uniform float ring_far   = 0.98;
uniform float ring_width = 0.12;
uniform float ring_gain  = 0.9;
uniform float bloom_gain = 0.55;

/* --- Grading (NEW) --- */
uniform float hue_shift : hint_range(-0.35, 0.35, 0.005) = -0.06; // radians (~-3.4°)
uniform float saturation : hint_range(0.5, 1.5, 0.01) = 1.05;
uniform vec3  rgb_gain = vec3(0.95, 1.08, 1.12); // boost G/B, trim R

/* ===== Utils ===== */
mat2 rot2(float a){
    float c = cos(a), s = sin(a);
    return mat2(vec2(c, s), vec2(-s, c)); // Godot: column vectors
}

/* Spectrum sampling (guarded) */
float spec_at(float u){
    float fb  = max(2.0, float(bar_count));
    float idx = clamp(u, 0.0, 1.0) * (fb - 1.0);
    float i0  = floor(idx);
    float t   = fract(idx);
    float tx0 = (i0 + 0.5) / fb;
    float tx1 = (min(i0 + 1.0, fb - 1.0) + 0.5) / fb;
    float h0  = textureLod(spectrum_tex, vec2(tx0, 0.5), 0.0).r;
    float h1  = textureLod(spectrum_tex, vec2(tx1, 0.5), 0.0).r;
    return mix(h0, h1, t);
}

float band_max(float u0, float u1){
    const int taps = 8;
    float m = 0.0;
    for (int i = 0; i < taps; i++){
        float t = float(i) / float(taps - 1);
        m = max(m, spec_at(mix(u0, u1, t)));
    }
    return m;
}

/* Hue rotate in YIQ space (stable & cheap) */
vec3 hue_rotate(vec3 c, float a){
    float Y = dot(c, vec3(0.299, 0.587, 0.114));
    float I = dot(c, vec3(0.596,-0.274,-0.322));
    float Q = dot(c, vec3(0.211,-0.523, 0.312));
    float ca = cos(a), sa = sin(a);
    float I2 = I*ca - Q*sa;
    float Q2 = I*sa + Q*ca;
    vec3 outc;
    outc.r = Y + 0.956*I2 + 0.621*Q2;
    outc.g = Y - 0.272*I2 - 0.647*Q2;
    outc.b = Y - 1.106*I2 + 1.703*Q2;
    return outc;
}

void fragment(){
    // Centered coords; fake perspective by widening X (match your port)
    vec2 uv = UV - 0.5;
    vec2 uv_aspect = uv * vec2(aspect, 1.75);

    // Radius for ring/vignette
    float r_scale = length(vec2(aspect * 0.5, 0.5));
    float r_norm  = length(uv_aspect) / max(1e-6, r_scale);
    float len_uv  = length(uv_aspect);

    // Time (wrapped to avoid huge trig args over long runs)
    float iTime = TIME * time_scale;
    if (time_wrap > 0.0) {
        iTime = mod(iTime, time_wrap);
    }

    // --- Audio bands (used gently, scaled by audio_amount) ---
    float bass = band_max(0.02, 0.13);
    float mid  = band_max(0.30, 0.60);
    float high = band_max(0.75, 0.98);

    // --- Rotation term (original + subtle audio) ---
    float t = iTime * 0.1
            + ((0.25 + 0.05 * sin(iTime * 0.1 + audio_amount * (2.0*high)))
               / (len_uv + 0.07)) * 2.2;
    t += audio_amount * (0.10 * bass + 0.20 * kick_env);
    mat2 ma = rot2(t);

    // --- Fractal accumulation (with guards) ---
    float v1 = 0.0;
    float v2 = 0.0;
    float v3 = 0.0;

    float s = 0.0;

    // Reduce work near center to avoid worst-case frames
    int max_s = int(mix(float(steps), float(steps) * 0.65, smoothstep(0.0, 0.25, len_uv)));

    for (int i = 0; i < MAX_STEPS; i++){
        if (i >= max_s) break;

        vec3 p = s * vec3(uv_aspect, 0.0);
        p.xy *= ma;

        // Original Z offset breathing + optional bass depth
        p += vec3(0.22, 0.30, s - 1.5 - sin(iTime * 0.13) * 0.1 - audio_amount * (0.2*bass));
        p = clamp(p, vec3(-64.0), vec3(64.0)); // keep inputs sane

        // Fold (inner iterations)
        for (int j = 0; j < MAX_FOLDS; j++){
            if (j >= folds) break;
            float d = max(dot(p, p), 1e-6);       // avoid div-by-zero
            p = abs(p) / d - 0.659;
            p = clamp(p, vec3(-64.0), vec3(64.0)); // keep outputs sane
        }

        float pp = min(dot(p, p), 256.0);
        if (!(pp >= 0.0)) break; // NaN guard

        // Accumulate
        v1 += pp * 0.0015 * (1.8 + sin(len_uv * 13.0 + 0.5  - iTime * 0.2 + audio_amount * (2.2*bass)));
        v2 += pp * 0.0013 * (1.5 + sin(len_uv * 14.5 + 1.2  - iTime * 0.3 + audio_amount * (1.7*mid )));
        v3 += min(length(p.xy * 10.0), 64.0) * 0.0003 * (1.0 + audio_amount * (0.5*high));

        // March speed (capped)
        s += 0.035 * (1.0 + audio_amount * (0.6*bass + 0.3*kick_in));
        s  = min(s, 3.0);
    }

    // Radial fades (original)
    v1 *= smoothstep(0.75, 0.0, len_uv);
    v2 *= smoothstep(0.55, 0.0, len_uv);
    v3 *= smoothstep(0.95, 0.0, len_uv);

    // Base color (original balance)
    vec3 col = vec3(
        v3 * (1.5 + sin(iTime * 0.2) * 0.4),
        (v1 + v3) * 0.30,
        v2
    );

    col += smoothstep(0.22, 0.0, len_uv) * (0.70 + audio_amount * (0.30*mid));
    col += smoothstep(0.0,  0.60, v3)     * (0.25 + audio_amount * (0.20*high));

    // Optional kick bloom
    col = mix(col, vec3(1.0), bloom_gain * audio_amount * clamp(kick_env, 0.0, 1.0));

    // Optional kick ring
    if (ring_enable){
        float rr = mix(ring_near, ring_far, clamp(ring_age, 0.0, 1.0));
        float ring = exp(-pow((r_norm - rr) / max(0.02, ring_width), 2.0));
        col += vec3(ring) * (ring_gain * audio_amount * clamp(kick_env, 0.0, 1.0));
    }

    /* ---- Grading (NEW) ---- */
    // saturation
    float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(luma), col, saturation);
    // gentle hue tilt toward cyan/green
    col = hue_rotate(col, hue_shift);
    // per-channel bias (boost G/B a bit, trim R)
    col *= rgb_gain;

    // Final tone map (finite-safe)
    col = min(pow(max(vec3(0.0), abs(col)) * max(1e-3, brightness), vec3(gamma_curve)), vec3(1.0));
    COLOR = vec4(col, 1.0);
}
