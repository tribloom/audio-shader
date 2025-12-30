shader_type canvas_item;
render_mode unshaded, blend_mix;

/* === pipeline uniforms === */
uniform sampler2D spectrum_tex;
uniform vec2      buffer_a_size = vec2(1920.0, 1080.0);

/* audio shaping */
uniform float audio_gamma = 2.0;
uniform float audio_gain  = 4.0;
uniform float audio_floor = 0.02;

/* look controls */
uniform int   ribbon_count      = 4;                     // 1..6 recommended
uniform float ribbon_width      : hint_range(0.1, 2.0) = 0.6;
uniform float ribbon_twist      : hint_range(0.0, 3.0) = 1.4;
uniform float ribbon_twist_speed: hint_range(0.0, 3.0) = 1.0;
uniform float spin_speed        : hint_range(-2.0, 2.0) = 0.4;
uniform float radial_falloff    : hint_range(0.2, 4.0) = 1.4;
uniform float bg_level          : hint_range(0.0, 1.0) = 0.20;
uniform float brightness        : hint_range(0.0, 2.0) = 1.1;
uniform float band_contrast     : hint_range(0.5, 3.0) = 1.5;

//const float PI  = 3.14159265;
//const float TAU = 6.28318530;
const int   MAX_RIBBONS = 6;

/* === helpers === */
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 x)  { return clamp(x, vec3(0.0), vec3(1.0)); }

/* IQ-style spectral palette */
vec3 bump3y(vec3 x, vec3 yoffset) {
    vec3 y = vec3(1.0) - x * x;
    y = saturate(y - yoffset);
    return y;
}

vec3 spectral_zucconi6(float x) {
    const vec3 c1 = vec3(3.54585104, 2.93225262, 2.41593945);
    const vec3 x1 = vec3(0.69549072, 0.49228336, 0.27699880);
    const vec3 y1 = vec3(0.02312639, 0.15225084, 0.52607955);

    const vec3 c2 = vec3(3.90307140, 3.21182957, 3.96587128);
    const vec3 x2 = vec3(0.11748627, 0.86755042, 0.66077860);
    const vec3 y2 = vec3(0.84897130, 0.88445281, 0.73949448);

    return bump3y(c1 * (x - x1), y1) +
           bump3y(c2 * (x - x2), y2);
}

float sample_spectrum(float u) {
    float s = texture(spectrum_tex, vec2(saturate(u), 0.0)).r;
    s = max(audio_floor, s);
    s = pow(s, audio_gamma);      // safe: s >= 0
    return s * audio_gain;
}

/* wrap angle difference to (-PI, PI) */
float angle_diff(float a, float b) {
    float d = a - b;
    d = mod(d + PI, TAU) - PI;
    return d;
}

void fragment() {
    vec2 res = buffer_a_size;
    if (res.x <= 0.0 || res.y <= 0.0) {
        res = vec2(1.0, 1.0);
    }

    vec2 frag = UV * res;
    vec2 uv   = frag / res;

    // centered, aspect-correct coords
    float aspect = res.x / res.y;
    vec2 st = uv - 0.5;
    st.x *= aspect;

    float r     = length(st);
    float angle = atan(st.y, st.x);

    // global spin
    float spin = TIME * spin_speed;

    // audio overview for global feel
    float spec_low  = sample_spectrum(0.08);
    float spec_mid  = sample_spectrum(0.25);
    float spec_high = sample_spectrum(0.55);

    float low_n  = saturate(spec_low  * 0.30);
    float mid_n  = saturate(spec_mid  * 0.30);
    float high_n = saturate(spec_high * 0.30);

    // background base color (soft, spacey)
    float bg_hue = fract(0.12 + TIME * 0.01 + mid_n * 0.1);
    vec3 bg_col = spectral_zucconi6(bg_hue) * (bg_level * (0.6 + 0.8 * low_n));

    vec3 col = bg_col;

    // use a slightly twisted radius so ribbons bend
    float twist_phase = r * ribbon_twist + TIME * ribbon_twist_speed;

    // clamp ribbon_count
    int count = clamp(ribbon_count, 1, MAX_RIBBONS);

    for (int i = 0; i < MAX_RIBBONS; i++) {
        if (i >= count) {
            break;
        }

        float fi = float(i);

        // each ribbon gets its own spectrum band
        float band_u = (fi + 0.5) / float(count + 1);
        float band   = sample_spectrum(band_u);
        float band_n = saturate(band * 0.35 * band_contrast);

        // base angle of this ribbon, spinning over time
        float base_angle = spin + fi * (TAU / float(count));

        // twist affects where the ribbon "leans"
        float twist = sin(twist_phase + fi * 1.3) * ribbon_twist * 0.4;
        float target_angle = base_angle + twist;

        // distance from pixel's angle to ribbon center
        float d_angle = angle_diff(angle, target_angle);

        // convert angular distance into a soft stripe profile
        float width = max(ribbon_width, 0.05); // avoid div by zero
        float x = d_angle / width;
        float stripe = 1.0 / (1.0 + x * x); // Lorentzian-ish

        // radial falloff so ribbons fade toward screen edge
        float rf = exp(-r * radial_falloff);

        float intensity = stripe * rf * band_n;

        // color per ribbon: hue from band + index + a little time shift
        float hue = fract(band_u + fi * 0.07 + TIME * 0.015 + high_n * 0.1);
        vec3 ribbon_col = spectral_zucconi6(hue);

        // brighten centerline, keep shoulders softer
        float core = saturate(intensity * 2.0);
        vec3 contrib = ribbon_col * (intensity * (0.6 + core * 1.4));

        col += contrib;
    }

    // overall brightness from low + mid energy
    float loud = saturate(0.6 * low_n + 0.4 * mid_n);
    float gain = brightness * (0.4 + loud * 1.3);
    col *= gain;

    COLOR = vec4(saturate(col), 1.0);
}
