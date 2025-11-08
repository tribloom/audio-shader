shader_type canvas_item;
render_mode unshaded;

uniform bool audio_enabled = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;

uniform float aspect = 1.7778;

uniform int ribbon_count = 3;
uniform float ribbon_scale = 1.3;
uniform float orbit_speed = 0.18;

uniform float width_px = 42.0;
uniform float length_px = 260.0;

uniform float exposure = 1.12;

uniform vec3 color_a = vec3(0.35, 0.08, 0.55);
uniform vec3 color_b = vec3(0.95, 0.35, 0.70);
uniform vec3 color_c = vec3(0.70, 0.95, 1.10);

uniform vec2 viewport_size = vec2(1920.0, 1080.0);

const float TAU = 6.28318530718;

int clamp_int(int v, int lo, int hi) {
    return min(max(v, lo), hi);
}

float sample_band(float lo, float hi) {
    if (!audio_enabled || bar_count <= 0) {
        return 0.0;
    }
    float lo_clamped = clamp(min(lo, hi), 0.0, 1.0);
    float hi_clamped = clamp(max(lo, hi), lo_clamped + 0.001, 1.0);
    int bar_count_safe = max(bar_count, 1);
    int idx_lo = int(floor(lo_clamped * float(bar_count_safe)));
    int idx_hi = int(ceil(hi_clamped * float(bar_count_safe)));
    idx_lo = clamp_int(idx_lo, 0, max(bar_count_safe - 1, 0));
    idx_hi = clamp_int(idx_hi, idx_lo + 1, bar_count_safe);

    float accum = 0.0;
    int count = 0;
    for (int i = 0; i < 512; i++) {
        if (i >= bar_count_safe) {
            break;
        }
        if (i < idx_lo) {
            continue;
        }
        if (i >= idx_hi) {
            break;
        }
        float u = (float(i) + 0.5) / float(bar_count_safe);
        accum += texture(spectrum_tex, vec2(u, 0.5)).r;
        count += 1;
    }

    if (count == 0) {
        return 0.0;
    }
    return (accum / float(count)) * audio_gain;
}

vec2 ndc_from_uv(vec2 uv) {
    vec2 p = uv * 2.0 - 1.0;
    p.x *= aspect;
    return p;
}

vec3 palette_for_index(int idx) {
    int m = idx % 3;
    if (m == 0) {
        return color_a;
    } else if (m == 1) {
        return color_b;
    } else {
        return color_c;
    }
}

void fragment() {
    vec2 safe_viewport = max(viewport_size, vec2(1.0, 1.0));
    float safe_aspect = max(aspect, 0.0001);
    vec2 ndc_to_pixel = vec2(safe_viewport.x / (2.0 * safe_aspect), safe_viewport.y / 2.0);

    vec2 frag_ndc = ndc_from_uv(UV);

    float bass = audio_enabled ? sample_band(0.0, 0.12) : 0.35 + 0.25 * sin(TIME * 0.6 + 0.2);
    float mid = audio_enabled ? sample_band(0.16, 0.45) : 0.3 + 0.2 * sin(TIME * 0.45 + 2.1);
    float treble = audio_enabled ? sample_band(0.55, 0.95) : 0.28 + 0.22 * sin(TIME * 1.15 + 1.7);

    bass = clamp(bass, 0.0, 4.0);
    mid = clamp(mid, 0.0, 4.0);
    treble = clamp(treble, 0.0, 4.0);

    float width_mod = max(width_px * (1.0 + 0.5 * bass), 1.0);
    float length_mod = max(length_px * (1.0 + 0.3 * treble), width_mod * 1.25);

    vec3 col = vec3(0.01, 0.012, 0.02);
    col += vec3(0.01, 0.015, 0.02) * pow(clamp(1.0 - length(frag_ndc) * 0.55, 0.0, 1.0), 2.0);

    int ribbon_total = int(clamp(float(ribbon_count), 1.0, 6.0));

    for (int i = 0; i < 6; i++) {
        if (i >= ribbon_total) {
            break;
        }

        float fi = float(i);
        float offset = (TAU / 3.0) * fi;
        float phase = TIME * orbit_speed * (1.0 + 0.15 * fi);
        float dphase = orbit_speed * (1.0 + 0.15 * fi);

        vec2 center_ndc;
        center_ndc.x = 0.55 * ribbon_scale * sin(phase + 0.7 + offset);
        center_ndc.y = 0.40 * ribbon_scale * sin(phase * 1.6 + 1.3 + offset);

        vec2 vel_ndc;
        vel_ndc.x = 0.55 * ribbon_scale * cos(phase + 0.7 + offset) * dphase;
        vel_ndc.y = 0.40 * ribbon_scale * 1.6 * cos(phase * 1.6 + 1.3 + offset) * dphase;

        vec2 vel_px = vel_ndc * ndc_to_pixel;
        float vel_len = length(vel_px);
        vec2 dir = vel_len > 1e-4 ? vel_px / vel_len : vec2(0.0, 1.0);
        vec2 perp = vec2(-dir.y, dir.x);

        vec2 d_px = (frag_ndc - center_ndc) * ndc_to_pixel;

        float u = dot(d_px, dir);
        float v = dot(d_px, perp);

        float body = exp(-pow(v / width_mod, 2.0) * 4.0) * exp(-pow(u / length_mod, 2.0) * 1.2);
        float halo = exp(-pow(v / (width_mod * 2.6), 2.0) * 2.0) * exp(-pow(u / (length_mod * 1.6), 2.0) * 0.6);
        float ridge = exp(-abs(v) / (width_mod * 0.55)) * exp(-pow(u / (length_mod * 0.65), 2.0));

        float response = body + halo * 0.35 + ridge * (0.15 + 0.55 * treble);

        vec3 ribbon_color = palette_for_index(i);
        float audio_lift = 0.8 + 0.35 * bass + 0.25 * mid;
        float twinkle = 0.2 + 0.8 * pow(clamp(ridge, 0.0, 1.0), 1.5);
        float pulse = 0.6 + 0.4 * sin(phase * 0.8 + fi * 1.7 + u / (length_mod + 1.0));

        vec3 contribution = ribbon_color * response * audio_lift * pulse;
        contribution += vec3(1.0, 0.95, 0.9) * twinkle * body * 0.25;

        col += contribution;
    }

    float vignette = 1.0 - smoothstep(0.75, 1.25, length(frag_ndc));
    col *= vignette;

    col = vec3(1.0) - exp(-col * exposure);

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}