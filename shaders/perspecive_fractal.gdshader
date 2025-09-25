shader_type canvas_item;

/*
UNIVERSE (faithful port + optional audio)
Original Shadertoy logic preserved. Audio hooks are subtle and OFF by default.

Expects (from your Visualizer.gd):
  - spectrum_tex (1xN; R=current, G=peak)
  - bar_count (int)
  - aspect (viewport width / height)
Optional onset inputs (already sent by your visualizer):
  - kick_in (smoothed bass 0..1)
  - kick_env (onset envelope 0..1)
  - ring_age (0..1)  [only used if ring_enable = true]
*/

// ---- Inputs from script ----
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float aspect = 1.7777;

// ---- Artistic controls ----
uniform float time_scale   = 1.0;
uniform float brightness   = 1.0;
uniform float gamma_curve  = 1.0;

// ---- Iterations (keep defaults to match look) ----
const int MAX_STEPS = 100;
const int MAX_FOLDS = 10;
uniform int steps = 100; // <= 100
uniform int folds = 10;  // <= 10

// ---- Audio (gentle by default) ----
uniform float audio_amount = 0.0;  // 0 = original look; 0.2..0.5 = subtle
uniform float kick_in  = 0.0;
uniform float kick_env = 0.0;
uniform float ring_age = 1.0;

// Optional kick ring (disabled by default to keep look identical)
uniform bool  ring_enable = false;
uniform float ring_near   = 0.10;
uniform float ring_far    = 0.98;
uniform float ring_width  = 0.10;
uniform float ring_gain   = 0.9;
uniform float bloom_gain  = 0.40;  // kick bloom toward white (scaled by audio_amount)

// -------- helpers --------
mat2 rot2(float a){
    float c = cos(a), s = sin(a);
    // Godot 4: mat2 needs columns
    return mat2(vec2(c, s), vec2(-s, c));
}

float spec_at(float u){
    float fb = float(bar_count);
    float idx = clamp(u, 0.0, 1.0) * max(1.0, fb - 1.0);
    float i0 = floor(idx);
    float t  = fract(idx);
    float tx0 = (i0 + 0.5) / fb;
    float tx1 = (min(i0 + 1.0, fb - 1.0) + 0.5) / fb;
    float h0 = texture(spectrum_tex, vec2(tx0, 0.5)).r;
    float h1 = texture(spectrum_tex, vec2(tx1, 0.5)).r;
    return mix(h0, h1, t);
}

float band_max(float u0, float u1){
    // small tap count to avoid changing the look too much
    int taps = 6;
    float m = 0.0;
    for (int i = 0; i < taps; i++){
        float t = float(i) / float(taps - 1);
        m = max(m, spec_at(mix(u0, u1, t)));
    }
    return m;
}

void fragment(){
    // Shadertoy uv mapping:
    // uv = (-iResolution.xy + 2.0 * fragCoord) / iResolution.y;
    // Godot UV in [0,1] -> centered, scaled by aspect, and doubled to match [-aspect..aspect], [-1..1]
    vec2 uv = (UV - 0.5) * vec2(2.0 * aspect, 2.0);

    // Normalized radius for optional ring
    float r_scale = length(vec2(aspect * 0.5, 0.5));
    float r_norm = length(uv) / max(1e-6, r_scale);

    // Original time
    float time = (TIME * time_scale + 29.0) * 60.0;
    float t = time * 0.005;

    // --- Audio bands (gentle drive) ---
    float bass = band_max(0.02, 0.15);
    float mid  = band_max(0.30, 0.60);
    float high = band_max(0.75, 0.98);

    // Original wobble + optional audio nudge (kept subtle)
    uv.x += sin(t) * 0.3
          + audio_amount * (0.10 * bass + 0.08 * kick_env);

    // Squiffy rotation (faithful) + tiny audio shove
    float si = sin(t * 1.5);
    float co = cos(t);
    uv *= mat2(vec2(co, si), vec2(-si, co));

    // Faithful color accumulation
    vec3 col = vec3(0.0);

    // Original init (unchanged)
    vec3 init = vec3(0.25, 0.25 + sin(time * 0.001) * 0.1, time * 0.0008);

    float s = 0.0;
    float v = 0.0;

    for (int r = 0; r < MAX_STEPS; r++){
        if (r >= steps) break;

        vec3 p = init + s * vec3(uv, 0.143);
        p.z = mod(p.z, 2.0);

        for (int i = 0; i < MAX_FOLDS; i++){
            if (i >= folds) break;
            float d = max(dot(p, p), 1e-6); // guard against div by 0
            p = abs(p * 2.04) / d - 0.75;
        }

        v += length(p * p) * smoothstep(0.0, 0.5, 0.9 - s) * 0.002;

        // Original purple/cyan bias
        col += vec3(v * 0.8, 1.1 - s * 0.5, 0.7 + v * 0.5) * v * 0.013;

        // Keep step size faithful; add a tiny audio nudge only if enabled
        s += 0.01 * (1.0 + audio_amount * (0.35 * bass + 0.20 * kick_in));
    }

    // Optional kick bloom (very gentle; 0 by default via audio_amount)
    col = mix(col, vec3(1.0), bloom_gain * audio_amount * clamp(kick_env, 0.0, 1.0));

    // Optional kick ring (OFF by default)
    if (ring_enable) {
        float rr = mix(ring_near, ring_far, clamp(ring_age, 0.0, 1.0));
        float ring = exp(-pow((r_norm - rr) / max(0.02, ring_width), 2.0));
        col += vec3(ring) * (ring_gain * audio_amount * clamp(kick_env, 0.0, 1.0));
    }

    // Final tone map (faithful)
    col = min(pow(max(vec3(0.0), col) * max(1e-3, brightness), vec3(gamma_curve)), vec3(1.0));
    COLOR = vec4(col, 1.0);
}
