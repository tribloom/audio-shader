shader_type canvas_item;
render_mode unshaded;

/* ---- Density + motion ---- */
uniform float stripes_per_screen : hint_range(10.0, 3000.0) = 1600.0;
uniform float falling_speed : hint_range(0.0, 20.0) = 1.25;
uniform bool move_down = true;
uniform float fade_width : hint_range(0.0, 0.5) = 0.06;

/* ---- Vertical ramp length (lower = longer continuous fade) ---- */
uniform float ramp_factor : hint_range(0.1, 4.0) = 0.5;

/* ---- Glow (at the tip) ---- */
uniform bool show_glow = true;
uniform float glow_radius : hint_range(0.0, 0.15) = 0.040;
uniform float glow_edge : hint_range(0.0, 0.15) = 0.018;
uniform float glow_gain : hint_range(0.0, 4.0) = 1.0;

/* ---- Audio / bar color mapping ---- */
uniform bool use_audio = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform int visible_bars : hint_range(2, 256) = 64;
uniform int bands_per_bar : hint_range(1, 4) = 1;

/* Base rotating color */
uniform float base_hue_speed : hint_range(-1.0, 1.0) = 0.015;
uniform float base_sat : hint_range(0.0, 1.0) = 0.9;
uniform float base_val : hint_range(0.0, 2.0) = 1.0;

/* Bass→red to treble→violet */
uniform float low_freq_hue : hint_range(0.0, 1.0) = 0.00;
uniform float high_freq_hue : hint_range(0.0, 1.0) = 0.78;

/* Dynamics */
uniform float hit_threshold : hint_range(0.0, 1.0) = 0.02;
uniform float audio_gain : hint_range(0.0, 8.0) = 2.6;
uniform float audio_bias : hint_range(0.0, 1.0) = 0.03;
uniform float audio_pow : hint_range(0.2, 3.0) = 0.75;
uniform float color_boost : hint_range(0.0, 3.0) = 1.3;

/* ---- Helpers ---- */
float rand1(float x) { return fract(sin(x) * 43758.5453123); }

vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(vec3(c.x) + vec3(0.0, 1.0/3.0, 2.0/3.0)) * 6.0 - 3.0);
    vec3 a = clamp(p - 1.0, 0.0, 1.0);
    return mix(vec3(1.0), a, c.y) * c.z;
}

float bar_energy(float x, int vis_bars, int bpb) {
    float vb = float(max(vis_bars, 2));
    float bar_idx = clamp(floor(x * vb), 0.0, vb - 1.0);
    float start_bin = bar_idx * float(bpb);
    float bc = vb * float(bpb);
    float inv_bc = 1.0 / max(bc, 1.0);

    float s = 0.0;
    float w = 0.0;
    for (int i = 0; i < 4; i++) {
        if (i >= bpb) break;
        float sx = (start_bin + (float(i) + 0.5)) * inv_bc;
        float v = texture(spectrum_tex, vec2(sx, 0.5)).r;
        s += v; w += 1.0;
    }
    s = (w > 0.0) ? s / w : 0.0;
    s = max(0.0, s * audio_gain + audio_bias);
    return pow(s, audio_pow);
}

void fragment() {
    vec2 uv = UV;

    /* ---- Many vertical stripes (continuous look) ---- */
    float qx = floor(uv.x * stripes_per_screen) / stripes_per_screen;
    float jitter = rand1(qx);
    float speed = falling_speed + jitter / 5.0;

    /* Unified phase. Offset ↑ => visual up, ↓ => visual down. */
    float offset = (move_down ? -(TIME * speed) : (TIME * speed)) + jitter;
    float u = fract(uv.y * ramp_factor + offset);   // 0..1, discontinuity = tip

    /* >>> FLIPPED LUMINANCE <<< 
       We invert the previous mapping so bright always leads the motion:
       - Down: bright falls over dark
       - Up:   bright rises over dark */
    float line_lum = move_down ? (1.0 - u) : u;
    line_lum = 1.0 - line_lum;  // <— flip both directions exactly as requested

    /* Glow: distance to nearest phase discontinuity (the tip) */
    float dx = abs(uv.x - qx);
    float dy_to_tip = min(u, 1.0 - u) / max(ramp_factor, 1e-5);
    float d = length(vec2(dx, dy_to_tip));
    float g = show_glow ? smoothstep(glow_radius, glow_radius - glow_edge, d) : 0.0;

    /* Colors: rotating base × bar hue (bass→red … treble→violet) */
    float base_h = fract(TIME * base_hue_speed);
    vec3 base_rgb = hsv2rgb(vec3(base_h, base_sat, base_val));

    int vis_bars = max(visible_bars, 2);
    float vb = float(vis_bars);
    float bar_center = (floor(uv.x * vb) + 0.5) / vb;
    float freq_h = mix(low_freq_hue, high_freq_hue, bar_center);
    vec3 hit_rgb = hsv2rgb(vec3(freq_h, 1.0, 1.0));

    int bpb = clamp(bands_per_bar, 1, 4);
    float e = use_audio ? bar_energy(bar_center, vis_bars, bpb) : 0.0;
    float k = smoothstep(hit_threshold, 1.0, e);
    vec3 bar_rgb = mix(base_rgb, hit_rgb, k) * (0.6 + 0.8 * e);

    vec3 col = bar_rgb * line_lum;
    col += vec3(g * glow_gain);

    /* Vertical vignette */
    float vv = abs(uv.y - 0.5);
    float fade = exp(-pow(vv, 6.0) / pow(2.0 * fade_width, 2.0));
    col *= fade;

    COLOR = vec4(col * color_boost, 1.0);
}
