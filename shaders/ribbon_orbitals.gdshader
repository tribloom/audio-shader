shader_type canvas_item;
render_mode unshaded;

/* ---------- Audio ---------- */
uniform bool       audio_enabled = true;
uniform sampler2D  spectrum_tex;
uniform int        bar_count = 64;
uniform float      audio_gain = 1.0;

/* ---------- Layout ---------- */
uniform float aspect = 1.7778;   // 16:9 default

/* ---------- Ribbons ---------- */
uniform int   ribbon_count = 3;  // 1..6 (compiled loop upper-bound below)
uniform float ribbon_width = 0.032; // base thickness in NDC (0..~0.08)
uniform float ribbon_scale = 1.25;  // orbit radius scale
uniform float orbit_speed  = 0.18;  // global angular speed

/* ---------- Trails (real motion streaks) ---------- */
uniform int   trail_steps = 24;     // 8..48 (performance vs quality)
uniform float trail_time  = 0.70;   // seconds of history integrated
uniform float trail_decay = 0.50;   // 0..1 : lower = brighter/longer trail

/* ---------- Look ---------- */
uniform float core_gain = 1.20;     // strength of ribbon body
uniform float halo_gain = 0.45;     // soft outer glow
uniform float bg_lift  = 0.020;     // lifts blacks so trails are visible
uniform float exposure = 1.12;      // overall filmic lift

/* ---------- Colors ---------- */
uniform vec3 color_a = vec3(0.35, 0.08, 0.55); // violet
uniform vec3 color_b = vec3(0.95, 0.35, 0.70); // rose
uniform vec3 color_c = vec3(0.70, 0.95, 1.10); // ice blue

/* ---------- Helpers ---------- */
float sample_spectrum(float x) {
    if (!audio_enabled) return 0.0;
    float u = clamp(x, 0.0, 0.999);
    return texture(spectrum_tex, vec2(u, 0.5)).r * audio_gain;
}

vec3 pick_color(int i){
    if (i == 0) return color_a;
    if (i == 1) return color_b;
    return color_c;
}

/* Parametric orbit (Lissajous-ish, nice for trance)
   bass -> radius breathing, highs -> shimmer/width */
vec2 orbit_center(float t, float idx, float bass){
    float a = t * (1.0 + 0.15*idx);
    // ellipse radii (scaled by ribbon_scale)
    float rx = 0.55 * ribbon_scale * (1.0 + 0.25*bass);
    float ry = 0.40 * ribbon_scale * (1.0 + 0.20*bass);
    // gentle frequency mismatch + per-ribbon phase
    float px = sin(a * 1.00 + 0.70 + idx*2.09439510239);
    float py = sin(a * 1.60 + 1.30 + idx*2.09439510239);
    return vec2(rx*px, ry*py);
}

void fragment() {
    vec2 uv = UV * 2.0 - 1.0;  // NDC
    uv.x *= aspect;

    float t = TIME;

    // basic bands
    float bass  = sample_spectrum(0.06);
    float highs = sample_spectrum(0.78);

    vec3 col = vec3(0.0);

    // clamp uniforms for safety
    int rc  = clamp(ribbon_count, 1, 6);
    int ts  = clamp(trail_steps,  4, 64);
    float dt = trail_time / float(ts);

    for (int i = 0; i < 6; i++) {               // upper bound 6, use rc to early-out
        if (i >= rc) break;
        vec3 tint = pick_color(i);
        float idx = float(i);

        // integrate history to create a true ribbon/streak
        for (int k = 0; k < 64; k++) {          // upper bound 64, use ts to early-out
            if (k >= ts) break;

            float age = float(k) * dt;          // seconds back in time
            float tt  = t - age;

            // center of the ribbon at that past time
            float ang = tt * orbit_speed;
            vec2  c   = orbit_center(ang, idx, bass);

            // distance to current pixel
            float d = length(uv - c);

            // width breathes slightly with bass, and grows for older samples
            float w = ribbon_width * (1.0 + 0.80*bass) * (1.0 + 0.35 * (float(k)/float(ts)));

            // gaussian core + soft halo
            float core = exp(-pow(d / w, 2.0) * 4.0) * core_gain;
            float halo = exp(-pow(d / (w*2.2), 2.0)) * halo_gain;

            // trail falloff by time index (exponential)
            float tf = pow(1.0 - trail_decay, float(k));

            // highs add sparkle to recent samples only
            float sparkle = mix(1.0, 1.0 + 0.35*highs, 1.0 - float(k)/float(ts));

            col += tint * (core + halo) * tf * sparkle;
        }
    }

    // soft vignette to keep focus central
    float r = length(vec2(uv.x/aspect, uv.y));
    float vig = smoothstep(1.20, 0.12, r);
    col = max(col * vig, vec3(bg_lift));

    // simple filmic-ish exposure
    col = 1.0 - exp(-col * exposure);
    COLOR = vec4(col, 1.0);
}
