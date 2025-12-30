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
uniform float grid_scale      : hint_range(4.0, 40.0) = 18.0; // cells across screen
uniform float line_sharpness  : hint_range(2.0, 20.0) = 10.0; // how crisp lines are
uniform float diagonal_mix    : hint_range(0.0, 1.0)  = 0.4;  // diagonal vs axis lines
uniform float scanline_amount : hint_range(0.0, 1.0)  = 0.2;  // horizontal scanlines
uniform float glow_radius     : hint_range(0.0, 1.0)  = 0.4;  // radial falloff from center
uniform float brightness      : hint_range(0.0, 2.0)  = 1.1;  // global brightness
uniform float color_shift     : hint_range(0.0, 2.0)  = 0.4;  // how fast hues drift

//const float PI  = 3.14159265;
//const float TAU = 6.28318530;

/* === helpers === */
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 x)  { return clamp(x, vec3(0.0), vec3(1.0)); }

/* IQ-style Zucconi palette */
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

/* sample spectrum with your usual shaping */
float sample_spectrum(float u) {
    float s = texture(spectrum_tex, vec2(saturate(u), 0.0)).r;
    s = max(audio_floor, s);
    s = pow(s, audio_gamma);
    return s * audio_gain;
}

void fragment() {
    vec2 res = buffer_a_size;
    if (res.x <= 0.0 || res.y <= 0.0) {
        res = vec2(1.0, 1.0);
    }

    vec2 frag = UV * res;
    vec2 uv   = frag / res;

    // aspect-correct coords centered at 0
    float aspect = res.x / res.y;
    vec2 p = uv - 0.5;
    p.x *= aspect;

    float r = length(p);

    // audio bands
    float spec_low  = sample_spectrum(0.06);
    float spec_mid  = sample_spectrum(0.25);
    float spec_high = sample_spectrum(0.55);

    float low_n  = saturate(spec_low  * 0.30);
    float mid_n  = saturate(spec_mid  * 0.30);
    float high_n = saturate(spec_high * 0.30);

    // base grid coordinates, gently scrolling
    float scroll = TIME * 0.15;
    vec2 g = p * grid_scale;
    g.x += scroll;
    g.y += scroll * 0.6;

    // axis-aligned grid
    vec2 cell = fract(g) - 0.5;
    float line_x = exp(-abs(cell.x) * line_sharpness);
    float line_y = exp(-abs(cell.y) * line_sharpness);
    float axis_grid = max(line_x, line_y);

    // diagonal grid (45° rotated)
    float cs = 0.70710678;
    vec2 gr = vec2(
        g.x * cs - g.y * cs,
        g.x * cs + g.y * cs
    );
    vec2 cell_d = fract(gr) - 0.5;
    float d1 = exp(-abs(cell_d.x) * line_sharpness);
    float d2 = exp(-abs(cell_d.y) * line_sharpness);
    float diag_grid = max(d1, d2);

    float grid_lines = mix(axis_grid, max(axis_grid, diag_grid), diagonal_mix);

    // scanline effect, tied to highs
    float scan = 0.0;
    if (scanline_amount > 0.0) {
        float sl = fract(uv.y * res.y * 0.5 + TIME * 30.0);
        float stripe = exp(-sl * sl * 40.0);
        scan = stripe * scanline_amount * high_n;
    }

    // radial glow from center, driven by low + mid
    float glow = exp(-r * r * 8.0 * (1.0 - glow_radius * 0.7));
    glow *= 0.4 + low_n + 0.5 * mid_n;

    // combine signals
    float grid_intensity = grid_lines * (0.5 + 1.5 * (low_n + high_n));
    float intensity = grid_intensity + glow + scan;

    // clamp and give a bit of baseline so it never dies
    intensity = saturate(intensity);
    intensity = 0.15 + intensity * 0.9;

    // color: hue from x-position + audio + time
    float hue = uv.x + TIME * color_shift * 0.02 + mid_n * 0.2;
    hue = fract(hue);

    vec3 base_color = spectral_zucconi6(hue);

    float loud = saturate(0.6 * low_n + 0.4 * mid_n);
    float gain = brightness * (0.5 + loud * 1.2);
    vec3 col = base_color * intensity * gain;

    COLOR = vec4(saturate(col), 1.0);
}
