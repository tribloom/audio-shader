shader_type canvas_item;
render_mode unshaded;

// Ported from Shadertoy "Julia Grid" style audio-reactive shader.
// Audio input arrives via spectrum_tex (R=current magnitude, 0..1 along X).

uniform sampler2D spectrum_tex : hint_default_black;
uniform bool audio_enabled = true;
uniform float audio_gain = 1.0;

uniform float time_speed = 1.5;
uniform float motion_blur = 0.15;
uniform int fibonacci_index = 5;
uniform int julia_iterations = 64;
uniform vec2 grid_scale = vec2(25.0, 25.0);
uniform vec2 bass_band = vec2(0.0, 0.008);
uniform vec2 treble_band = vec2(0.7, 1.0);
uniform float bass_threshold = 0.94;
uniform float treble_threshold = 0.4;

const float ESCAPE_RADIUS = 4.0;
const int MAX_JULIA_ITER = 128;
const int MAX_FIB_SAMPLES = 64;

ivec2 fib(int f) {
    int n0 = 1;
    int n1 = 1;
    int fi = 0;
    for (int i = 0; i < f; i++) {
        fi = n0 + n1;
        n0 = n1;
        n1 = fi;
    }
    return ivec2(n0, n1);
}

float rand(vec2 n) {
    return fract(sin(dot(n, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 rotate(vec2 v, float t) {
    float ct = cos(t);
    float st = sin(t);
    return vec2(ct * v.x - st * v.y, st * v.x + ct * v.y);
}

float sample_fft(vec2 uv) {
    float enabled = audio_enabled ? 1.0 : 0.0;
    vec2 suv = clamp(uv, vec2(0.0), vec2(1.0));
    return textureLod(spectrum_tex, suv, 0.0).r * audio_gain * enabled;
}

float avg_frq(vec2 band) {
    float from = min(band.x, band.y);
    float to = max(band.x, band.y);
    float span = to - from;
    if (span <= 0.0001) {
        return sample_fft(vec2(from, 0.25));
    }
    float step = span / 3.0;
    float sum = 0.0;
    sum += sample_fft(vec2(from, 0.25));
    sum += sample_fft(vec2(from + step, 0.25));
    sum += sample_fft(vec2(from + 2.0 * step, 0.25));
    sum += sample_fft(vec2(to, 0.25));
    return sum * 0.25;
}

vec2 julia(vec2 a, float t) {
    float mess = cos(t) * 0.06;
    float sqrz_x = a.x * a.x - a.y * a.y + 0.40 + sin(t) * 0.01;
    float sqrz_y = 2.0 * a.x * a.y + 0.40 + mess;
    return vec2(sqrz_x, sqrz_y);
}

float px_func(vec2 st, float t) {
    vec2 z = st;
    int limit = clamp(julia_iterations, 1, MAX_JULIA_ITER);
    int escape_iter = limit;
    for (int j = 0; j < MAX_JULIA_ITER; j++) {
        if (j >= limit) {
            break;
        }
        z = julia(z, t);
        if (dot(z, z) > ESCAPE_RADIUS) {
            escape_iter = j;
            break;
        }
    }
    return float(escape_iter) / float(limit);
}

float grid(vec2 frag_pos, vec2 grid_uv_scale, float time_value, vec2 resolution) {
    vec2 mid = resolution * 0.5;
    vec2 g_scale = vec2(2.0 + sin(time_value * 0.1), 2.0 + cos(time_value * 0.1)) * grid_uv_scale;
    g_scale = max(g_scale, vec2(1e-4));

    vec2 uv = frag_pos / resolution;
    vec2 pos = (frag_pos - mid) / resolution;

    pos = rotate(pos + sin(time_value * 0.1) * 0.5, time_value * 0.01);

    float wave_x = sample_fft(vec2(uv.x, 0.75));
    float wave_y = sample_fft(vec2(uv.y, 0.75));

    float bass = avg_frq(bass_band);
    float treble = avg_frq(treble_band);

    float bass_gate = step(bass_threshold, bass);
    float treble_gate = step(treble_threshold, treble);

    float jul = px_func(pos, time_value);

    float wave_y_clamp = clamp(wave_x, 0.0, bass_gate);

    pos = rotate(pos, jul);
    pos = rotate(pos, -jul * wave_y_clamp);

    vec2 cell = mod(pos, g_scale);

    float color = 0.1;
    float grid_color = 0.8;

    float mod_x = mod(pos.x, g_scale.x);
    float mod_y = mod(pos.y, g_scale.y);

    vec2 border = g_scale / 50.0;

    vec2 spacing = vec2(6.0);
    if (bass_gate > 0.5) {
        spacing.x -= (5.0 * abs(sin(time_value)) * bass);
    }
    if (treble_gate > 0.5) {
        spacing.y -= (12.0 * treble);
    }
    spacing = max(spacing * 2.0, vec2(1.0));

    vec2 cell_max = vec2(ceil(cell.x / g_scale.x) * g_scale.x, ceil(cell.y / g_scale.y) * g_scale.y);
    vec2 pattern_mod = vec2(mod(pos.x, g_scale.x * spacing.x), mod(pos.y, g_scale.y * spacing.y));

    if (cell_max.x > pattern_mod.x && cell_max.x < pattern_mod.x + g_scale.x &&
        cell_max.y > pattern_mod.y && cell_max.y < pattern_mod.y + g_scale.y) {
        color = 1.0;
    }

    float wave_x_clamp = clamp(wave_y / 40.0, 0.0, treble_gate);
    if (mod_x < border.x + wave_x_clamp || mod_y < border.y) {
        color = grid_color;
    }

    return color;
}

void fragment() {
    vec2 resolution = vec2(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);
    vec2 frag_coord = UV * resolution;

    int fib_steps = max(fibonacci_index, 2);
    ivec2 fib_pair = fib(fib_steps - 2);
    int sample_count = clamp(fib_pair.x, 1, MAX_FIB_SAMPLES);
    float ffN = max(float(fib_pair.x), 1.0);
    float ffk = float(fib_pair.y);

    vec3 sum = vec3(0.0);

    vec2 grid_param = grid_scale / resolution;

    float random_seed = rand(FRAGCOORD.xy / resolution);
    float base_time = TIME;

    for (int i = 0; i < MAX_FIB_SAMPLES; i++) {
        if (i >= sample_count) {
            break;
        }
        float fi = float(i);
        vec2 samp = vec2(fi / ffN, fract(ffk * (fi / ffN)));
        float time_map = base_time + (fi + random_seed) / ffN * motion_blur;
        sum += vec3(grid(frag_coord + samp, grid_param, time_map * time_speed, resolution));
    }

    vec3 color = (sample_count > 0) ? sum / float(sample_count) : vec3(0.0);
    COLOR = vec4(color, 1.0);
}