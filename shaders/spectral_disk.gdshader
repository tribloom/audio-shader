shader_type canvas_item;
render_mode unshaded;

// Port of provided Shadertoy-style audio shader.
// Adapts the iChannel0 FFT+waveform sampling to the Visualizer's
// spectrum_tex and waveform_tex inputs.

uniform sampler2D spectrum_tex : hint_default_black;
uniform sampler2D waveform_tex : hint_default_black;
uniform int bar_count = 64;
uniform float aspect = 1.7778;
uniform float audio_gain = 1.0;
uniform bool enable_audio = true;
uniform vec3 spectrum_color = vec3(1.0);
uniform vec3 waveform_color = vec3(1.0);

float sample_spectrum(float u) {
    float count = float(max(bar_count, 1));
    float idx = clamp(u, 0.0, 1.0) * max(count - 1.0, 1.0);
    float base = floor(idx);
    float frac = fract(idx);
    float tx0 = (base + 0.5) / count;
    float tx1 = (min(base + 1.0, count - 1.0) + 0.5) / count;
    float s0 = texture(spectrum_tex, vec2(tx0, 0.5)).r;
    float s1 = texture(spectrum_tex, vec2(tx1, 0.5)).r;
    return mix(s0, s1, frac);
}

float sample_wave(float u) {
    return texture(waveform_tex, vec2(clamp(u, 0.0, 1.0), 0.5)).r * 2.0 - 1.0;
}

void fragment() {
    vec2 centered = UV * 2.0 - 1.0;
    centered.y = -centered.y;
    vec2 uv = centered;
    uv.x *= aspect;

    float fft = sample_spectrum(abs(uv.x * uv.y));
    float wave_u = 0.5 + 0.5 * clamp(uv.x / max(aspect, 1.0), -1.0, 1.0);
    float wave = sample_wave(wave_u);

    if (!enable_audio) {
        fft = 0.35;
        wave = 0.0;
    } else {
        fft = clamp(fft * audio_gain, 0.0, 1.0);
        wave = clamp(wave * audio_gain, -1.0, 1.0);
    }

    vec3 pixel = vec3(fft);
    vec3 gradient = vec3(fft, 4.0 * fft * (1.0 - fft), 1.0 - fft) * fft;
    float wave_band = 1.0 - smoothstep(0.0, 0.15, abs(wave - uv.y));

    pixel += gradient * spectrum_color;
    pixel += wave_band * waveform_color;

    if (length(uv) < fft) {
        pixel = vec3(0.0);
    }

    vec3 final_color = clamp(pixel - 0.2, 0.0, 1.0);
    COLOR = vec4(final_color, 1.0);
}