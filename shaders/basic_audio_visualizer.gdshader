shader_type canvas_item;
render_mode unshaded;

/* From your Visualizer.gd */
uniform sampler2D spectrum_tex;   // 1 x bar_count, R = current, G = peak
uniform int   bar_count = 64;
uniform float aspect    = 1.7777;

/* Small controls */
uniform float time_scale = 1.0;   // speed multiplier
uniform float width      = 1.0;   // replaces #define WIDTH 1.0
uniform float audio_gain = 1.0;   // scale the audio response
uniform bool  audio_enabled = true;

/* --- helper: sample your 1×N spectrum at normalized u in [0..1] --- */
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

/* Shadertoy helpers mapped to our spectrum */
float audio_freq(float f) { return spec_at(f); }
/* Shadertoy used a separate “amplitude over time” row; we approximate with spectrum too. */
float audio_ampl(float t) { return spec_at(t); }

/* B-spline from the original */
vec3 B2_spline(vec3 x) { // returns 3 B-spline functions of degree 2
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

void fragment(){
    // Shadertoy: uv = fragCoord / iResolution; here UV is already 0..1
    vec2 uv = UV;

    // Centered coords; scale X by aspect like original did with iResolution.x/y
    vec2 centered = 2.0 * uv - 1.0;
    centered.x *= aspect;

    float dist2 = dot(centered, centered);
    float clamped_dist = smoothstep(0.0, 1.0, dist2);
    float arclength    = abs(atan(centered.y, centered.x) / radians(360.0)) + 0.01;

    // Color variation
    float tt = TIME * time_scale / 100.0;               // iTime/100
    float polychrome = (1.0 + sin(tt * 10.0)) * 0.5;    // 0 -> uniform, 1 -> spectrum
    vec3 spline_args = fract(vec3(polychrome * uv.x - tt) + vec3(0.0, -1.0/3.0, -2.0/3.0));
    vec3 spline = B2_spline(spline_args);

    float f = abs(centered.y);
    vec3 base_color  = vec3(1.0) - f * spline;
    vec3 flame_color = pow(base_color, vec3(3.0));
    vec3 disc_color  = 0.20 * base_color;
    vec3 wave_color  = 0.10 * base_color;
    vec3 flash_color = 0.05 * base_color;

    /* Audio samples (mapped to your spectrum) */
    float s1 = audio_freq(abs((uv.x - 0.5) / max(1e-6, width)) + 0.01);
    float s2 = audio_ampl(clamped_dist);
    float s3 = audio_ampl(arclength);

    if (!audio_enabled){
        // gentle static look if no audio is connected
        s1 = 0.35; s2 = 0.25; s3 = 0.15;
    }
    s1 *= audio_gain;
    s2 *= audio_gain;
    s3 *= audio_gain;

    float v = abs(uv.y - 0.5);

    float disp_dist = smoothstep(-0.2, -0.1, s3 - dist2);
    disp_dist *= (1.0 - disp_dist);

    vec3 color = vec3(0.0);
    color += flame_color * smoothstep(v, v * 8.0, s1);
    color += disc_color  * smoothstep(0.5, 1.0, s2) * (1.0 - clamped_dist);
    color += flash_color * smoothstep(0.5, 1.0, s3) * clamped_dist;
    color += wave_color  * disp_dist;

    // Gamma approx from original (pow 0.4545 ~= 1/2.2)
    color = pow(color, vec3(0.4545));
    COLOR = vec4(color, 1.0);
}
