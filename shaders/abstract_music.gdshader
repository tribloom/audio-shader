shader_type canvas_item;

/* Inputs */
uniform sampler2D spectrum_tex : hint_default_black; // iChannel0 (1xN strip)
uniform float aspect = 1.7777778;                    // width / height

/* Line crispness */
uniform float body_lo  : hint_range(0.70, 0.99) = 0.90;
uniform float body_hi  : hint_range(0.80, 1.00) = 0.995;
uniform float ring_lo  : hint_range(0.95, 0.99999) = 0.990;
uniform float ring_hi  : hint_range(0.98, 1.00) = 1.000;
uniform float ring_gain: hint_range(0.0, 2.0) = 0.25;

/* --- helpers --- */
mat2 rotate2d(float a) {
    float c = cos(a), s = sin(a);
    return mat2(vec2(c, s), vec2(-s, c));
}

/* Continuous “noise” (no floor/fract). Smooth, time-varying, no cell edges. */
float cnoise(vec2 p) {
    // two rotated dot waves, summed and normalized into [0,1]
    float n1 = sin(dot(p, vec2(12.9898, 78.233)) + TIME * 0.73);
    float n2 = sin(dot(p, vec2(-37.719, 11.135)) + TIME * 0.41);
    return 0.5 + 0.25 * (n1 + n2); // in ~[0,1]
}

void fragment() {
    // Upright and aspect-correct
    vec2 base_uv = vec2(UV.x, 1.0 - UV.y);
    vec2 uv = vec2(base_uv.x, base_uv.y / aspect);

    // Original mapping
    vec2 uv2 = -1.0 + 2.0 * uv;
    uv2.y += 0.45;
    uv2 *= 4.5;

    vec3 col = vec3(0.0);

    mat2 R = rotate2d(TIME);
    vec2 rot_off = R * vec2(1.0, 0.0);

    // 16 “bands”
    for (int i = 0; i < 16; i++) {
        float fx = 0.05 + 0.5 * float(i) / 16.0;
        float freq_i = texture(spectrum_tex, vec2(fx, 0.25)).x;
        freq_i = clamp(1.9 * pow(freq_i, 3.0), 0.0, 1.0);

        // Continuous noise in place of value-noise (no cell seams)
        float n = cnoise(uv * 10.0 + rot_off);

        // same phase structure
        float phase = (-(freq_i * n) * 3.1416) + (uv2.x * uv2.x + uv2.y * uv2.y);

        // full-wave, smooth (no hard half-wave clamp)
        float w = 0.5 + 0.5 * sin(phase);
        w = pow(w, 1.2); // gentle shaping

        vec2 v = R * (uv * 2.0);
        vec3 tint = vec3(v.x, v.y, 1.7 - v.y * v.x) * 0.08;

        float body = smoothstep(body_lo, body_hi, w);
        col += body * tint * freq_i;

        float rim = smoothstep(ring_lo, ring_hi, w);
        col += rim * vec3(0.2) * ring_gain;
    }

    COLOR = vec4(col, 1.0);
}
