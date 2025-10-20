shader_type canvas_item;
render_mode unshaded;

uniform bool audio_enabled = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform sampler2D waveform_tex : hint_default_black;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.7777;
uniform float beat_point = 0.3;
uniform float distort_strength = 1.0;
uniform float noise_overlay = 1.0;

float spec_at(float u){
    if (bar_count <= 0){
        return 0.0;
    }
    float fb = float(bar_count);
    float idx = clamp(u, 0.0, 1.0) * max(fb - 1.0, 1.0);
    float i0 = floor(idx);
    float t = idx - i0;
    float u0 = (i0 + 0.5) / fb;
    float u1 = (min(i0 + 1.0, fb - 1.0) + 0.5) / fb;
    float s0 = texture(spectrum_tex, vec2(u0, 0.5)).r;
    float s1 = texture(spectrum_tex, vec2(u1, 0.5)).r;
    return mix(s0, s1, t);
}

float waveform_raw(float u){
    int width = textureSize(waveform_tex, 0).x;
    if (width < 1){
        return 0.5;
    }
    float tx = clamp(u, 0.0, 1.0);
    return texture(waveform_tex, vec2(tx, 0.5)).r;
}

float waveform_signed(float u){
    float base = waveform_raw(u) - 0.5;
    return clamp(base * audio_gain * 2.0, -1.0, 1.0);
}

float waveform_unsigned(float u){
    return waveform_signed(u) * 0.5 + 0.5;
}

float fallback_wave(vec2 uv, float offset){
    return 0.5 + 0.2 * sin((uv.x + uv.y + offset) * 6.28318 + TIME * 0.4);
}

void fragment(){
    vec2 uv = UV;
    vec2 ouv = uv;

    float beat_val = spec_at(beat_point);
    float hwf_u = waveform_unsigned(uv.x);
    float hwf_s = waveform_signed(uv.x);
    float vwf_s = waveform_signed(fract(uv.y));
    float vwf_u = clamp(vwf_s * 0.5 + 0.5, 0.0, 1.0);

    float gain = clamp(audio_gain, 0.0, 4.0);
    float w1 = clamp(spec_at(0.1) * gain, 0.0, 1.0);
    float w2 = clamp(spec_at(0.2) * gain, 0.0, 1.0);
    float w3 = clamp(spec_at(0.4) * gain, 0.0, 1.0);
    float w4 = clamp(spec_at(0.8) * gain, 0.0, 1.0);

    if (!audio_enabled){
        float alt = fallback_wave(uv, 0.0);
        beat_val = 0.25;
        hwf_u = alt;
        hwf_s = (alt - 0.5) * 1.5;
        vwf_s = (fallback_wave(uv, 1.0) - 0.5) * 1.5;
        vwf_u = vwf_s * 0.5 + 0.5;
        w1 = 0.22;
        w2 = 0.28;
        w3 = 0.34;
        w4 = 0.40;
    }

    beat_val = clamp(beat_val * gain, 0.0, 1.0);
    float beat_drive = beat_val * beat_val;

    vec3 sun = vec3(-cos(TIME),
                    0.7 + 0.3 * cos(uv.x * 6.0 + 20.0 * (uv.y - 0.5) * (beat_val - 0.2) + TIME),
                    0.85 + 0.35 * cos(TIME));
    sun.xy = 0.5 + 0.5 * sun.xy;
    sun = normalize(sun);

    float distort = vwf_s * beat_drive * beat_val * distort_strength;
    float noise = waveform_unsigned(fract(vwf_u));
    if (!audio_enabled){
        noise = vwf_u;
    }

    float warped_x = abs(uv.x + distort);
    if (warped_x > 1.0){
        warped_x = 2.0 - warped_x;
    }
    uv.x = warped_x;

    float hwf = clamp(hwf_u, 0.0, 1.0);

    float coord1 = sin(uv.x + hwf) - cos(uv.y);
    float coord2 = sin(1.0 - uv.x + hwf) - sin(uv.y * 3.0);
    float coord4 = mix(coord1, coord2, hwf);
    float coord5 = mix(coord1, coord2, beat_val);

    float coorda = mix(coord1, coord2, 0.5 + 0.5 * sin(TIME * 0.7));
    float coordb = mix(coord5, coord4, 0.5 + 0.5 * sin(TIME * 0.5));
    float coord = mix(coorda, coordb, 0.5 + 0.5 * sin(TIME * 0.3));

    float j = (spec_at(clamp(abs(coord), 0.0, 1.0)) - 0.5) * 2.0;

    vec3 bg_color = vec3(dot(vec3(uv.x, uv.y, j), sun),
                         dot(vec3(uv.y, j, uv.x), sun),
                         dot(vec3(j, uv.x, uv.y), sun));

    float inv_aspect = 1.0 / max(aspect, 0.001);
    vec2 suv = -1.0 + 2.0 * uv;
    suv.y *= inv_aspect;

    float theta = (w1 - w2 + w3 - w4) * 3.14;
    mat2 m = mat2(vec2(cos(theta * 0.2), sin(theta * 0.5)),
                  vec2(-sin(theta * 0.3), cos(theta * 0.7)));
    suv = m * suv;

    float rad = length(suv) - 0.3;
    float wave_width = 0.0;
    float wave_amp = 0.0;
    float h = 0.0;

    for (int i = 0; i < 10; i++){
        h = sin(suv.x * 8.0 + TIME) * 0.2 * w1 +
            sin(suv.x * 16.0 - 2.0 * TIME) * 0.2 * w2 +
            sin(suv.x * 32.0 + 3.0 * TIME) * 0.2 * w3 +
            sin(suv.x * 64.0 - 4.0 * TIME) * 0.2 * w4;
        rad += h * 0.4;
        float safe_rad = max(abs(rad), 0.001);
        wave_width = abs(1.0 / (100.0 * safe_rad));
        wave_amp += wave_width;
    }

    vec3 wave_color = vec3(0.2 + w2 * 1.5,
                           0.1 + w4 * 2.0 + suv.y * 0.1,
                           0.1 + w3 * 2.0 + suv.x * 0.1);

    wave_amp *= beat_drive * 3.0;
    wave_amp *= clamp(abs(hwf_s), 0.0, 1.0) * 2.0;

    vec3 final_color = bg_color * smoothstep(0.0, 5.0, TIME);
    final_color += 0.12 * wave_color * wave_amp;

    float vignette = 0.5 + 0.5 * pow(16.0 * ouv.x * ouv.y * (1.0 - ouv.x) * (1.0 - ouv.y), 0.2);
    final_color *= vignette;

    final_color += vec3(noise) * distort * 10.0 * noise_overlay;
    final_color = clamp(final_color, 0.0, 1.0);

    COLOR = vec4(final_color, 1.0);
}