shader_type canvas_item;
render_mode unshaded;

uniform float aspect = 1.7777;

uniform bool audio_enabled = true;
uniform sampler2D waveform_tex : hint_default_black;

uniform float audio_level = 0.0;
uniform float audio_bass = 0.0;
uniform float audio_treble = 0.0;
uniform float kick_env = 0.0;

uniform float line_thickness = 0.020;
uniform float line_taper = 0.050;
uniform float line_separation = 0.055;

uniform float blur_base = 0.010;
uniform float blur_edge_boost = 0.018;
uniform float blur_audio_boost = 0.80;
uniform float waveform_drive = 0.35;

uniform float phase_audio_boost = 6.0;
uniform float phase_kick_boost = 2.5;

uniform float wave1_speed = 3.0;
uniform float wave1_phase = 10.0;
uniform float wave1_wobble = 1.5;

uniform float wave2_speed = 4.0;
uniform float wave2_phase = 13.0;
uniform float wave2_wobble = 3.0;

uniform float wave3_speed = 5.0;
uniform float wave3_phase = 20.0;
uniform float wave3_wobble = 3.0;

uniform vec3 color_line_1 = vec3(1.0, 0.1, 0.2);
uniform vec3 color_line_2 = vec3(0.8, 0.4, 0.2);
uniform vec3 color_line_3 = vec3(0.3, 0.2, 0.9);

uniform float quiet_brightness = 0.35;
uniform float loud_brightness = 4.0;
uniform vec3 background_color = vec3(0.01, 0.01, 0.02);
uniform float vignette_power = 0.85;

float line_mask(vec2 uv, float center, float thickness){
    float extra = line_taper * (smoothstep(0.6, 1.0, uv.x) + smoothstep(0.3, 0.0, uv.x));
    float width = max(1e-4, thickness + extra);
    float half_w = 0.5 * width;
    float top = center + half_w;
    float bottom = center - half_w;
    float aa = max(1e-4, fwidth(uv.y));
    float upper = smoothstep(top, top + aa, uv.y);
    float lower = smoothstep(bottom, bottom + aa, uv.y);
    return clamp(lower - upper, 0.0, 1.0);
}

float waveform_signed(float u){
    int width = textureSize(waveform_tex, 0).x;
    if (width <= 0){
        return sin(u * 6.28318 + TIME * 0.6);
    }
    float sample = texture(waveform_tex, vec2(clamp(u, 0.0, 1.0), 0.5)).r;
    return clamp((sample - 0.5) * 2.0, -1.0, 1.0);
}

float apply_vignette(vec2 uv){
    vec2 centered = uv - 0.5;
    centered.x *= aspect;
    float dist = length(centered);
    return pow(smoothstep(0.92, 0.18, dist), vignette_power);
}

float wave_line(vec2 uv, float speed, float base_phase, float wobble, float wobble_offset, float center_offset, float audio_sample){
    vec2 p = uv;

    float wob = wobble != 0.0 ? wobble * sin(TIME + wobble_offset) : 0.0;
    float dyn_phase = base_phase + wob;
    if (audio_enabled){
        dyn_phase += phase_audio_boost * audio_sample;
        dyn_phase += phase_kick_boost * kick_env;
    }else{
        dyn_phase += 1.5;
    }
    dyn_phase = max(dyn_phase, 0.1);

    float wave = sin(TIME * speed + p.x * dyn_phase);
    float wf = waveform_drive * waveform_signed(p.x);
    if (!audio_enabled){
        wf *= 0.5;
    }

    float falloff = smoothstep(0.5, 0.0, abs(p.x - 0.5));
    float blur = blur_base + blur_edge_boost * falloff;
    if (audio_enabled){
        blur *= (1.0 + blur_audio_boost * audio_sample);
        blur *= (1.0 + 0.25 * kick_env);
    }else{
        blur *= (1.0 + 0.35 * blur_audio_boost);
    }

    float swing = wave + wf;
    p.y += dyn_phase * blur * swing;

    return line_mask(p, 0.5 + center_offset, line_thickness);
}

void fragment(){
    vec2 uv = SCREEN_UV;

    float bass_sample = audio_enabled ? audio_bass : 0.32;
    float mid_sample = audio_enabled ? audio_level : 0.35;
    float treb_sample = audio_enabled ? audio_treble : 0.34;
    float loudness = audio_enabled ? audio_level : 0.45;

    float sep = clamp(line_separation, 0.0, 0.25);
    float mask1 = wave_line(uv, wave1_speed, wave1_phase, wave1_wobble, 0.0,  sep, bass_sample);
    float mask2 = wave_line(uv, wave2_speed, wave2_phase, wave2_wobble, 2.0, 0.0, mid_sample);
    float mask3 = wave_line(uv, wave3_speed, wave3_phase, wave3_wobble, 3.0, -sep, treb_sample);

    float brightness = mix(quiet_brightness, loud_brightness, clamp(loudness, 0.0, 1.0));
    vec3 lines = vec3(0.0);
    lines += color_line_1 * mask1 * (0.6 + 0.8 * bass_sample) * brightness;
    lines += color_line_2 * mask2 * (0.6 + 0.8 * mid_sample)  * brightness;
    lines += color_line_3 * mask3 * (0.6 + 0.8 * treb_sample) * brightness;

    float vign = apply_vignette(uv);
    vec3 col = background_color * vign + lines;

    col = pow(clamp(col, 0.0, 8.0), vec3(0.95));
    COLOR = vec4(col, 1.0);
}