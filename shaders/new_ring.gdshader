shader_type canvas_item;

// ---- Node + ring controls ----
uniform float aspect       = 1.0;     // node width/height
uniform float ring_radius  = 0.45;    // base radius (normalized)
uniform float thickness    = 0.015;   // band half-width

// ---- Audio (0..1) ----
uniform float bass   = 0.0;
uniform float treble = 0.0;

// Gate emission
uniform float bass_thresh   = 0.20;   // outward emits only if bass >= threshold
uniform float treble_thresh = 0.20;   // inward emits only if treble >= threshold

// ---- Color (base ring can drift; pulses freeze at emission) ----
//uniform float hue_period_s = 10.0;    // seconds per hue cycle (0 disables drift)
//uniform float saturation   = 0.95;
//uniform float value        = 1.00;
uniform int   color_mode        = 0;                  // 0: rainbow, 1: palette, 2: solid color
uniform float hue_period_s      = 10.0;               // seconds per hue cycle (0 disables drift)
uniform float saturation        = 0.95;
uniform float value             = 1.00;
uniform vec4  palette_color     = vec4(0.85, 0.55, 0.15, 1.0);
uniform float palette_variation = 0.55;               // 0 keeps pulses at palette_color, 1.0 full variation
uniform vec4  solid_color       = vec4(1.0, 1.0, 1.0, 1.0);
// ---- Ripple trains (max “visible” echoes to draw) ----
uniform int   pulses_max   = 6;       // echoes each direction (0..10)
uniform float falloff      = 0.70;    // per-echo brightness falloff (0..1)
uniform float widen        = 1.20;    // older pulses get wider (>=1)

// ---- Emission frequency (cadence) ----
// We let louder signals emit more frequently by shrinking emit_dt.
uniform float emit_dt_min  = 0.10;    // fastest cadence (loud)
uniform float emit_dt_max  = 0.30;    // slowest cadence (quiet)
uniform float emit_rate_gain = 1.5;   // how aggressively cadence tightens with drive

// ---- Travel speed mapping (magnitude → speed) ----
// effective_speed = base + drive * gain
uniform float speed_out_base = 0.20;
uniform float speed_in_base  = 0.20;
uniform float speed_out_gain = 0.80;
uniform float speed_in_gain  = 0.80;

// ---- Age-based slowdown (distance grows, then eases) ----
// distance(age) = speed * (1 - exp(-slow_k * age)) / slow_k
uniform float slow_k = 1.0;

//const float TAU = 6.2831853;

// Soft band from (r - t) .. (r + t)
float ring_band(vec2 p, float r, float t) {
    float d = length(p);
    float inner = smoothstep(r - t, r,     d);
    float outer = smoothstep(r,     r + t, d);
    return inner - outer;
}

// HSV → RGB
vec3 hsv2rgb(vec3 c) {
    vec3 q = abs(fract(c.xxx + vec3(0.0, 2.0/6.0, 4.0/6.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(q - 1.0, 0.0, 1.0), c.y);
}

vec3 palette_variant(float phase, float mix_strength) {
    vec3 base_rgb = palette_color.rgb;
    float osc = sin(phase * TAU) * 0.5 + 0.5; // 0..1 variation
    vec3 lighter = mix(base_rgb, vec3(1.0), palette_variation);
    vec3 darker  = mix(base_rgb, base_rgb * 0.25, palette_variation);
    vec3 tinted  = mix(darker, lighter, osc);
    return mix(base_rgb, tinted, clamp(mix_strength, 0.0, 1.0));
}

vec3 base_color_from_mode(float around, float drift) {
    if (color_mode == 0) {
        float base_hue = fract(around + drift);
        return hsv2rgb(vec3(base_hue, saturation, value));
    }
    if (color_mode == 1) {
        return palette_color.rgb;
    }
    return solid_color.rgb;
}

vec3 pulse_color_from_mode(float around, float drift, float mix_strength) {
    if (color_mode == 0) {
        float hue = fract(around + drift);
        return hsv2rgb(vec3(hue, saturation, value));
    }
    if (color_mode == 1) {
        return palette_variant(around + drift, mix_strength);
    }
    return solid_color.rgb;
}

// Age → distance with slowdown
float travel_slow(float age, float speed) {
    if (slow_k <= 1e-5) return speed * age; // linear fallback
    return speed * (1.0 - exp(-slow_k * age)) / slow_k;
}

// Map drive to [0..1] “excess over threshold”
float drive_over(float x, float th) { return max(0.0, x - th) / max(1e-5, 1.0 - th); }

// Loudness-aware cadence: smaller emit_dt when drive is high
float emit_dt_from_drive(float drive_norm) {
    float t = clamp(drive_norm * emit_rate_gain, 0.0, 1.0);
    return mix(emit_dt_max, emit_dt_min, t);
}

void fragment() {
    // Centered coords ([-1,1]) and keep circles round
    vec2 p = UV * 2.0 - 1.0;
    p.x *= aspect;

    // Angle for coloring
    float ang    = atan(p.y, p.x);
    float around = fract(ang / TAU);

    // Base ring (anchor)
    float base_r = ring_radius;
    float lum    = ring_band(p, base_r, thickness);

    // Base color may drift slowly; pulses will freeze at emission
    float base_drift = (hue_period_s > 0.0) ? (TIME / hue_period_s) : 0.0;
    //float base_hue   = fract(around + base_drift);
    //vec3  base_rgb   = hsv2rgb(vec3(base_hue, saturation, value));
	vec3  base_rgb   = base_color_from_mode(around, base_drift);
    vec3  col        = base_rgb * lum;

    // --- OUTWARD (bass) ---
    // Gate & drive
    float gate_out  = step(bass_thresh, bass); // 1 if bass >= threshold
    float drive_out = drive_over(bass, bass_thresh); // 0..1 excess over threshold

    // Speed scales with magnitude
    float speed_out = speed_out_base + drive_out * speed_out_gain;

    // Emission cadence tightens with loudness
    float emit_dt_out = emit_dt_from_drive(drive_out);

    // Modulo clock for continuous emission on the bass train
    float ph_out = fract(TIME / emit_dt_out) * emit_dt_out;

    // Draw up to pulses_max echoes
    int N = clamp(pulses_max, 0, 10);
    for (int i = 0; i < 10; i++) {
        if (i >= N) break;

        // Age of this pulse (newest first)
        float age   = ph_out + float(i) * emit_dt_out;

        // Distance traveled with slowdown; outward direction
        float r_i   = base_r + travel_slow(age, speed_out);

        if (r_i > 1.6) continue; // off-screen guard

        float width = thickness * mix(1.0, widen, float(i)/max(1.0,float(N)));
        float w     = pow(falloff, float(i)) * gate_out * drive_out; // visible only over threshold, scaled by magnitude

        if (w <= 0.0) continue;

        // Freeze color at EMISSION time (now - age)
        float t_emit     = TIME - age;
        float drift_emit = (hue_period_s > 0.0) ? (t_emit / hue_period_s) : 0.0;
        //float hue_i      = fract(around + drift_emit);
        //vec3  rgb_i      = hsv2rgb(vec3(hue_i, saturation, value));
        float idx_norm   = 0.0;
        if (N > 1) {
            idx_norm = float(i) / float(N - 1);
        }
        float mix_strength = mix(0.35, 1.0, idx_norm);
        vec3  rgb_i      = pulse_color_from_mode(around, drift_emit, mix_strength);

        col += rgb_i * (ring_band(p, r_i, width) * w);
    }

    // --- INWARD (treble) ---
    float gate_in  = step(treble_thresh, treble);
    float drive_in = drive_over(treble, treble_thresh);
    float speed_in = speed_in_base + drive_in * speed_in_gain;
    float emit_dt_in = emit_dt_from_drive(drive_in);
    float ph_in = fract(TIME / emit_dt_in) * emit_dt_in;

    for (int j = 0; j < 10; j++) {
        if (j >= N) break;

        float age   = ph_in + float(j) * emit_dt_in;
        float r_j   = base_r - travel_slow(age, speed_in);

        if (r_j < 0.02) continue;

        float width = thickness * mix(1.0, widen, float(j)/max(1.0,float(N)));
        float w     = pow(falloff, float(j)) * gate_in * drive_in;

        if (w <= 0.0) continue;

        float t_emit     = TIME - age;
        float drift_emit = (hue_period_s > 0.0) ? (t_emit / hue_period_s) : 0.0;
        //float hue_j      = fract(around + drift_emit);
        //vec3  rgb_j      = hsv2rgb(vec3(hue_j, saturation, value));
        float idx_norm   = 0.0;
        if (N > 1) {
            idx_norm = float(j) / float(N - 1);
        }
        float mix_strength = mix(0.35, 1.0, idx_norm);
        vec3  rgb_j      = pulse_color_from_mode(around, drift_emit, mix_strength);

        col += rgb_j * (ring_band(p, r_j, width) * w);
    }

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
