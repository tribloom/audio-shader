shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D spectrum_tex;
uniform sampler2D waveform_tex;
uniform sampler2D history_tex : hint_screen_texture, filter_linear;

uniform float feedback = 0.94;
uniform float drive = 0.6;
uniform float waveform_mix = 0.35;
uniform float bias = 0.18;

vec3 spectral_mix(float v) {
        vec3 base = vec3(0.25, 0.5, 1.0);
        vec3 accent = vec3(1.0, 0.45, 0.25);
        return mix(base, accent, clamp(v, 0.0, 1.0));
}

void fragment() {
        vec2 uv = UV;
        vec3 prev = texture(history_tex, SCREEN_UV).rgb;
        vec3 color = prev * feedback;

        float fft = texture(spectrum_tex, vec2(clamp(uv.x, 0.0, 1.0), 0.0)).r;
        float wave = texture(waveform_tex, vec2(clamp(uv.x, 0.0, 1.0), 0.0)).r;
        float signal = pow(max(fft - bias, 0.0), 1.4);
        float wave_component = abs(wave - 0.5) * waveform_mix;

        vec3 pulse = spectral_mix(signal + wave_component) * (signal * drive + wave_component * 0.8);
        color += pulse;

        COLOR = vec4(color, 1.0);
}
