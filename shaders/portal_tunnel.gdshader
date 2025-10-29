shader_type canvas_item;
render_mode unshaded;

uniform bool       audio_enabled = true;
uniform sampler2D  spectrum_tex; // 1xbar_count, sample at y=0.5
uniform int        bar_count = 64;
uniform float      audio_gain = 1.0;

uniform float aspect = 1.7778;
uniform float tunnel_speed = 0.60;   // base Z drift
uniform float radial_count = 12.0;   // number of beams
uniform float warp_amp = 0.25;
uniform float warp_freq = 1.75;
uniform float glow = 1.10;
uniform float exposure = 1.05;

// Colors
uniform vec3 base_tint = vec3(0.20, 0.60, 1.20); // cyan
uniform vec3 accent_tint = vec3(0.95, 0.30, 0.95);

float sample_spectrum(float x) {
    if (!audio_enabled) return 0.0;
    float u = clamp(x, 0.0, 0.999);
    return texture(spectrum_tex, vec2(u, 0.5)).r * audio_gain;
}

void fragment() {
    vec2 uv = UV * 2.0 - 1.0;
    uv.x *= aspect;

    // Polar coords
    float r = length(uv);
    float a = atan(uv.y, uv.x);

    // Time proxy (use SCREEN_UV.y for cheap motion if no TIME)
    float t = TIME;

    // Radial beams driven by spectrum
    float beam_idx_f = (a / (6.28318530718)) * radial_count;
    float beam_frac = fract(beam_idx_f);
    float beam_band = floor((beam_idx_f / radial_count) * float(bar_count)) / float(bar_count);
    float s = sample_spectrum(beam_band);

    // Warp & tunnel depth
    float z = fract(t * tunnel_speed + r * (0.3 + 0.2 * s));
    float warp = sin(a * radial_count + t * warp_freq) * warp_amp * (0.5 + 0.5 * s);
    float ring = exp(-20.0 * abs(fract(z + warp) - 0.5)); // ring envelope
    float beam = smoothstep(0.0, 0.25, 0.25 - abs(beam_frac - 0.5));

    // Mix colors
    vec3 col = base_tint * (0.4 + 0.6 * s) + accent_tint * (0.25 * beam);
    float l = (ring * (0.35 + 0.65 * s)) + (beam * (0.25 + 0.5 * s));

    // Vignette
    float vig = smoothstep(1.25, 0.15, r);
    col *= (l * glow + 0.02) * vig;

    // Simple exposure
    col = 1.0 - exp(-col * exposure);
    COLOR = vec4(col, 1.0);
}
