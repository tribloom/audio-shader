shader_type canvas_item;

// ---- Node + ring controls ----
uniform float aspect = 1.7777778;
uniform float ring_radius = 0.45;
uniform float thickness   = 0.015; // try changing this

// ---- Rainbow controls (color only) ----
uniform float hue_period_s = 10.0;          // How long (in seconds) a full hue drift takes. Bigger = slower drift.
uniform float saturation   = 0.95;          // Color intensity. Lower it for pastel colors.
uniform float value        = 1.00;          // Base brightness of the ring before multiplying by the band.

// ---- Ripple trains (continuous emission) ----
uniform int   pulses       = 6;                          // 8  echoes each direction (0..10)
uniform float emit_dt      = 0.18;                       // 9  seconds between pulses
uniform float speed_out    = 0.55;                       // 10 outward speed (radius units/sec)
uniform float speed_in     = 0.55;                       // 11 inward speed
uniform float falloff      = 0.70;                       // 12 per-echo brightness falloff
uniform float widen        = 1.20;                       // 13 older pulses get wider (>=1)

// ---- Age-based slowdown (bigger = stronger slowdown) ----
// travel(age) = (1 - exp(-slow_k * age)) / slow_k   → linear when slow_k ≈ 0
uniform float slow_k       = 1.0;

float ring_band(vec2 p, float r, float t) {
    float dist = length(p);
    // band from r - t to r + t
    return smoothstep(r - t, r, dist) - smoothstep(r, r + t, dist);
}

// Convert HSV (hue,sat,val) to RGB
vec3 hsv2rgb(vec3 c){                       // 10
    vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0/6.0, 4.0/6.0)) * 6.0 - 3.0); // 11
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);           // 12
}

// Travel distance with age-based slowdown
float travel_slow(float age, float speed) {
    // (1 - e^{-k t}) / k is a nice easing that saturates smoothly.
    // When slow_k ~ 0, fall back to linear speed * age.
    if (slow_k <= 1e-5) {
        return speed * age;
    }
    return speed * (1.0 - exp(-slow_k * age)) / slow_k;
}


// rotate vector by angle a
vec2 rot(vec2 v, float a){
    float c = cos(a), s = sin(a);
    return vec2(c*v.x - s*v.y, s*v.x + c*v.y);
}

void fragment() {
	// 1) Centered, aspect-correct coords (keep circles round)
    vec2 p = (SCREEN_UV - 0.5) * 2.0;
    p.x *= aspect;

	// 2) Color: rainbow around the circle + slow drift over time
	float ang = atan(p.y, p.x);             // Angle around the center in radians (-π..π).
	float around = fract(ang / TAU);        // Map angle to 0..1 around the circle. This will drive the rainbow.

	// 3) Base ring (anchor, doesn’t move)
	float base_r = ring_radius;
    float lum = ring_band(p, base_r, thickness);

	float base_drift = (hue_period_s > 0.0) ? TIME / hue_period_s : 0.0; // Convert time to a slow 0..1 cycle. One full loop every hue_period_s seconds.
	float base_hue = fract(around + base_drift);  // Final hue: position around the circle plus slow drift. It stays periodic.
	vec3  base_rgb = hsv2rgb(vec3(base_hue, saturation, value));                   // Turn HSV into RGB. This gives the ring its rainbow colors.

    // Start color with base ring
    vec3 col = base_rgb * lum;

	// 4) Continuous ripple emission (outward & inward)
    int   N   = clamp(pulses, 0, 10);                    // 32  cap for safety
    float ph  = fract(TIME / emit_dt) * emit_dt;         // 33  newest pulse age ∈ [0, emit_dt)


    // ---- Outward pulses (expand) ----
    for (int i = 0; i < 10; i++) {                       // 34
        if (i >= N) break;                               // 35
        float age   = ph + float(i) * emit_dt;           // 36  older pulses have larger age
		float dist_out = travel_slow(age, speed_out);       // age → distance with slowdown
        float r_i   = base_r + dist_out;          // 37  radius grows with age
        if (r_i > 2.0) continue;                         // 38  offscreen guard
        float width = thickness * mix(1.0, widen, float(i) / max(1.0, float(N))); // 39
        float w     = pow(falloff, float(i));            // 40  fade older echoes


        // Freeze the pulse color at EMISSION time:
        // emission_time = now - age
        float t_emit    = TIME - age;
        float drift_emit = (hue_period_s > 0.0) ? (t_emit / hue_period_s) : 0.0;
        float hue_i     = fract(around + drift_emit);
        vec3  rgb_i     = hsv2rgb(vec3(hue_i, saturation, value));

        col += rgb_i * (ring_band(p, r_i, width) * w);
    }

    // ---- Inward pulses (contract) ----
    for (int j = 0; j < 10; j++) {                       // 42
        if (j >= N) break;                               // 43
        float age   = ph + float(j) * emit_dt;           // 44
		float dist_in  = travel_slow(age, speed_in);
        float r_j   = base_r - dist_in;           // 45  radius shrinks with age
        if (r_j < 0.02) continue;                        // 46  don’t draw super-small rings
        float width = thickness * mix(1.0, widen, float(j) / max(1.0, float(N))); // 47
        float w     = pow(falloff, float(j));            // 48
        // Freeze color at emission time for inward pulse
        float t_emit    = TIME - age;
        float drift_emit = (hue_period_s > 0.0) ? (t_emit / hue_period_s) : 0.0;
        float hue_j     = fract(around + drift_emit);
        vec3  rgb_j     = hsv2rgb(vec3(hue_j, saturation, value));

        col += rgb_j * (ring_band(p, r_j, width) * w);
    }

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);            // Multiply color by luminance and output. Alpha = 1. The ring shows only where lum is > 0.
    //COLOR = vec4(vec3(lum), 1.0);
}