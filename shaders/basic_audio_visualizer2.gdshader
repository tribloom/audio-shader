shader_type canvas_item;
render_mode unshaded;

/* From your Visualizer.gd */
uniform sampler2D spectrum_tex;   // 1 x bar_count (R=current, G=peak)
uniform int   bar_count = 64;
uniform float aspect    = 1.7777;

/* Waterfall history (NEW) */
uniform bool  use_waterfall = true;      // toggle to use the 2D audio history
uniform sampler2D waterfall_tex;         // rows x bar_count (R8)
uniform int   wf_rows = 256;             // number of rows in the waterfall
uniform float head_norm = 0.0;           // normalized y of NEXT write row [0,1)
uniform float ampl_span = 0.12;          // how far back in time t∈[0..1] maps to
uniform float ampl_low_bias = 0.55;      // 0..1 prefer lows near center

/* Small controls */
uniform float time_scale  = 1.0;         // speed multiplier
uniform float width       = 1.0;         // Shadertoy's #define WIDTH
uniform float audio_gain  = 1.0;         // scale audio response
uniform bool  audio_enabled = true;      // quick disable (static look)

/* ---------------- Spectrum helpers ---------------- */
float spec_at(float u){
    float fb = max(2.0, float(bar_count));
    float idx = clamp(u, 0.0, 1.0) * (fb - 1.0);
    float i0 = floor(idx);
    float t  = fract(idx);
    float tx0 = (i0 + 0.5) / fb;
    float tx1 = (min(i0 + 1.0, fb - 1.0) + 0.5) / fb;
    float h0 = texture(spectrum_tex, vec2(tx0, 0.5)).r;
    float h1 = texture(spectrum_tex, vec2(tx1, 0.5)).r;
    return mix(h0, h1, t);
}

float audio_freq(float f) { return spec_at(f); }

/* ---------------- Waterfall “amplitude over time” ----------------
   We read a row from waterfall_tex at y = (head_norm - t*ampl_span - 1/rows).
   Then we average a few X taps (low..high). A bias emphasizes lows near center.
------------------------------------------------------------------- */
float wf_row_avg(float y_norm, float low_bias){
    // 5 taps across x (low→high), weights skewed by low_bias
    float w0 = 0.35*low_bias + 0.05;
    float w1 = 0.25*low_bias + 0.08;
    float w2 = 0.18;
    float w3 = 0.15*(1.0-low_bias) + 0.05;
    float w4 = 0.10*(1.0-low_bias) + 0.02;
    float W  = (w0+w1+w2+w3+w4);

    float v =
        w0 * texture(waterfall_tex, vec2(0.08, y_norm)).r +
        w1 * texture(waterfall_tex, vec2(0.25, y_norm)).r +
        w2 * texture(waterfall_tex, vec2(0.50, y_norm)).r +
        w3 * texture(waterfall_tex, vec2(0.75, y_norm)).r +
        w4 * texture(waterfall_tex, vec2(0.92, y_norm)).r;

    return v / max(W, 1e-6);
}

float audio_ampl_wf(float t_norm){
    float inv_rows = 1.0 / max(1.0, float(wf_rows));
    // sample just behind the head (latest written row), and move back with t
    float y = head_norm - t_norm * ampl_span - 0.5 * inv_rows;
    y = y - floor(y); // fract() but positive and stable
    // bias lows near center (t~0) and mix toward neutral away from center
    float low_bias = mix(1.0, clamp(ampl_low_bias, 0.0, 1.0), clamp(t_norm, 0.0, 1.0));
    return wf_row_avg(y, low_bias);
}

/* Fallback if waterfall disabled/unbound: just reuse spectrum */
float audio_ampl_fb(float t_norm){
    return spec_at(t_norm);
}

/* ---------------- B-spline (as in original) ---------------- */
vec3 B2_spline(vec3 x) {
    vec3 t = 3.0 * x;
    vec3 b0 = step(0.0, t)     * step(0.0, 1.0 - t);
    vec3 b1 = step(0.0, t-1.0) * step(0.0, 2.0 - t);
    vec3 b2 = step(0.0, t-2.0) * step(0.0, 3.0 - t);
    return 0.5 * (
        b0 * (t*t) +
        b1 * (-2.0*(t*t) + 6.0*t - 3.0) +
        b2 * pow(3.0 - t, vec3(2.0))
    );
}

/* ---------------- Main ---------------- */
void fragment(){
    vec2 uv = UV;

    // center and aspect-correct X
    vec2 centered = 2.0 * uv - 1.0;
    centered.x *= aspect;

    float dist2 = dot(centered, centered);
    float clamped_dist = smoothstep(0.0, 1.0, dist2);
    float arclength    = abs(atan(centered.y, centered.x) / radians(360.0)) + 0.01;

    // Color variation
    float tt = TIME * time_scale / 100.0;             // iTime/100
    float polychrome = (1.0 + sin(tt * 10.0)) * 0.5;  // 0 uniform → 1 spectrum
    vec3 spline_args = fract(vec3(polychrome * uv.x - tt) + vec3(0.0, -1.0/3.0, -2.0/3.0));
    vec3 spline = B2_spline(spline_args);

    float f = abs(centered.y);
    vec3 base_color  = vec3(1.0) - f * spline;
    vec3 flame_color = pow(base_color, vec3(3.0));
    vec3 disc_color  = 0.20 * base_color;
    vec3 wave_color  = 0.10 * base_color;
    vec3 flash_color = 0.05 * base_color;

    // Audio: freq from spectrum, amplitude from waterfall (or fallback)
    float s1 = audio_freq(abs((uv.x - 0.5) / max(1e-6, width)) + 0.01);
    float s2 = use_waterfall ? audio_ampl_wf(clamped_dist) : audio_ampl_fb(clamped_dist);
    float s3 = use_waterfall ? audio_ampl_wf(arclength)    : audio_ampl_fb(arclength);

    if (!audio_enabled){
        s1 = 0.35; s2 = 0.25; s3 = 0.15;
    }
    s1 *= audio_gain; s2 *= audio_gain; s3 *= audio_gain;

    float v = abs(uv.y - 0.5);

    float disp_dist = smoothstep(-0.2, -0.1, s3 - dist2);
    disp_dist *= (1.0 - disp_dist);

    vec3 color = vec3(0.0);
    color += flame_color * smoothstep(v, v * 8.0, s1);
    color += disc_color  * smoothstep(0.5, 1.0, s2) * (1.0 - clamped_dist);
    color += flash_color * smoothstep(0.5, 1.0, s3) * clamped_dist;
    color += wave_color  * disp_dist;

    // Gamma approx (~1/2.2)
    color = pow(color, vec3(0.4545));
    COLOR = vec4(color, 1.0);
}
