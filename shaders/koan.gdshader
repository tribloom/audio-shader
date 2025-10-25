shader_type canvas_item;
render_mode unshaded;

// Port of the "wave threads" audio shader from Shadertoy.
// The original used iResolution/iTime/iMouse/iChannel0.
// Inputs here are wired by Visualizer.gd.
uniform sampler2D spectrum_tex : hint_default_black;
uniform float audio_gain = 1.0;
uniform float time_scale = 1.0;
uniform float wave_layers = 5.0;
uniform float wave_amplitude = 0.01;
uniform float wave_denominator = 50.0;
uniform float level_gain = 0.5;
uniform float level_bias = 0.2;
uniform float level_exponent = 6.0;
uniform float layer_tint_gain = 0.03;
uniform float streak_intensity = 1.2;
uniform float mouse_x = 0.0;
uniform float mouse_scale = 0.001;

const int MAX_WAVE_LAYERS = 16;

float sample_audio(float x) {
    float u = clamp(x, 0.0, 1.0);
    return texture(spectrum_tex, vec2(u, 0.5)).r;
}

void fragment() {
    vec2 uv = UV;
    float x = clamp(uv.x, 0.0, 1.0);
    float y = (1.0 - uv.y) - 0.5;

    float layers = clamp(wave_layers, 1.0, float(MAX_WAVE_LAYERS));

    float sample = sample_audio(x) * audio_gain;
    float level = clamp(sample * level_gain + level_bias, 0.0, 4.0);

    float time_drive = TIME * time_scale * exp(0.1 * mouse_x * mouse_scale);
    vec3 color = vec3(0.0);

    float y_accum = y;
    for (int idx = 1; idx < MAX_WAVE_LAYERS; idx++) {
        if (float(idx) >= layers) {
            break;
        }

        float fi = float(idx);
        float wave = sin(x * exp(fi) - time_drive);
        y_accum += exp(level_exponent * level) * wave * wave_amplitude;

        float denom = abs(y_accum) + 1e-4;
        float f_temp = abs(1.0 / (wave_denominator * layers) / denom);

        vec3 contribution = vec3(
            f_temp * (fi * layer_tint_gain),
            f_temp * fi / layers,
            pow(f_temp, 0.93) * streak_intensity
        );
        color += contribution;
    }

    COLOR = vec4(color, 1.0);
}