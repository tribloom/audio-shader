shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D spectrum_tex;
uniform sampler2D history_tex : hint_screen_texture, filter_linear;
uniform vec2 buffer_a_size = vec2(1920.0, 1080.0);
uniform float feedback = 0.9;
uniform float audio_gain = 1.0;

vec2 tile(vec2 v) {
        vec2 f = fract(v);
        vec2 parity = sign(fract(0.5 * v) * 2.0 - 1.0 + vec2(1e-5));
        return ((f * 2.0 - 1.0) * parity) * 0.5 + 0.5;
}

vec2 complex_mul(vec2 a, vec2 b) {
        return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

vec4 sample_history(vec2 uv) {
        vec2 tiled = tile(uv);
        return texture(history_tex, tiled);
}

float sample_spectrum(float x) {
        float domain = clamp(0.3 * x, 0.0, 1.0);
        return texture(spectrum_tex, vec2(domain, 0.0)).r * audio_gain;
}

void fragment() {
        vec2 resolution = buffer_a_size;
        if (resolution.x <= 0.0 || resolution.y <= 0.0) {
                resolution = vec2(textureSize(history_tex, 0));
        }
        vec2 uv = UV;

        float spectrum_value = sample_spectrum(uv.x);
        float base = 0.5 + 0.25 * ((spectrum_value * 2.0) - 1.0);
        float gaussian = exp(-5000.0 * (uv.y - base) * (uv.y - base));
        vec4 color = vec4(vec3(gaussian), gaussian);

        float t = 1.3 * sin(TIME);
        vec2 a = sin(vec2(t, t) + vec2(0.0, 1.5707963));
        mat2 rot = mat2(vec2(a.x, -a.y), vec2(a.y, a.x));

        vec2 st = uv * 2.0 - 1.0;
        float scale = 1.5 + 0.25 * cos(5.0 * t + 5.0 * TIME);
        st = scale * complex_mul(st, st);
        st += 0.3 * vec2(sin(1.235 * TIME), cos(2.25 * TIME));
        st = rot * st;
        st = st * 0.5 + 0.5;

        vec4 history = sample_history(st);
        color += history * feedback;

        COLOR = color;
}