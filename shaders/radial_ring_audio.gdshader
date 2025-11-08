shader_type canvas_item;
render_mode unshaded;

const float STEPS = 10000.0;
const float SPECTRUM_V = 0.25;

uniform sampler2D spectrum_tex : hint_default_black;
uniform float aspect = 1.7777778;

uniform float time_scale : hint_range(0.0, 4.0) = 1.0;
uniform float time_audio_drive : hint_range(0.0, 4.0) = 1.0;
uniform float radial_power : hint_range(1.0, 4.0) = 2.0;
uniform float audio_bin_drive : hint_range(0.0, 4.0) = 1.0;
uniform float warp_strength : hint_range(0.0, 2.0) = 0.7;
uniform float warp_frequency : hint_range(0.0, 20.0) = 9.0;
uniform float warp_time_scale : hint_range(0.0, 10.0) = 2.0;
uniform float ring_travel : hint_range(0.0, 0.5) = 0.2;
uniform float base_scale : hint_range(0.0, 0.05) = 0.01;
uniform float accent_scale : hint_range(0.0, 0.05) = 0.005;
uniform float audio_brightness : hint_range(0.0, 5.0) = 1.0;
uniform float audio_gain : hint_range(0.0, 4.0) = 1.0;
uniform float brightness : hint_range(0.0, 4.0) = 1.0;

uniform vec4 base_color : source_color = vec4(0.55, 0.15, 0.9, 1.0);
uniform vec4 accent_color : source_color = vec4(0.95, 0.35, 1.0, 1.0);

void fragment() {
    vec2 uv = UV;
    vec2 pos = uv - 0.5;
    pos.x *= aspect;

    float radial = length(pos);
    float totalsound = texture(spectrum_tex, vec2(0.0, SPECTRUM_V)).r * audio_gain;

    float exponent = radial_power + totalsound * audio_bin_drive;
    float freq_bin = floor(STEPS * pow(radial, exponent)) / STEPS;
    freq_bin = clamp(freq_bin, 0.0, 1.0);
    float sample_u = clamp(1.0 - freq_bin, 0.0, 0.9999);
    float sound = texture(spectrum_tex, vec2(sample_u, SPECTRUM_V)).r * audio_gain;

    float t = TIME * time_scale + sound * time_audio_drive;

    float safe_r = max(radial, 1e-4);
    vec2 dir = pos / safe_r;
    float wave = sin(t) * sin(radial * warp_frequency - t * warp_time_scale);
    vec2 warped_uv = uv + dir * (wave * warp_strength);

    vec2 center = vec2(0.5 + ring_travel * sin(t));
    float dist = max(length(warped_uv - center), 1e-4);
    float amp = 1.0 + audio_brightness * sound;

    float primary = base_scale * amp / dist;
    float secondary = accent_scale * amp / dist;

    vec3 col = base_color.rgb * primary + accent_color.rgb * secondary;
    col *= brightness;

    COLOR = vec4(col, max(base_color.a, accent_color.a));
}