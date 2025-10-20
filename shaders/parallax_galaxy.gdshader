shader_type canvas_item;

/* ---------- Audio controls ---------- */
uniform bool use_audio = false;                            // enable spectrum sampling
uniform sampler2D spectrum_tex : hint_default_black;       // audio texture
uniform vec4 audio_bins = vec4(0.01, 0.07, 0.15, 0.30);    // x positions to sample
uniform float audio_row = 0.25;                            // y row used by the renderer
uniform float audio_gain : hint_range(0.0, 3.0) = 1.0;     // optional gain

/* ---------- Look controls ---------- */
uniform float star_mix : hint_range(0.0, 2.0) = 1.0;       // strength of sparkling stars
uniform float layer_offset = 0.0;                          // tweaks the secondary layer zoom
uniform float exposure   : hint_range(0.1, 3.0) = 1.0;     // brightness multiplier

/* ---------- Helpers ---------- */
vec4 sample_audio_bins(){
    vec4 freq = vec4(0.0);
    if (use_audio){
        freq.x = texture(spectrum_tex, vec2(audio_bins.x, audio_row)).r;
        freq.y = texture(spectrum_tex, vec2(audio_bins.y, audio_row)).r;
        freq.z = texture(spectrum_tex, vec2(audio_bins.z, audio_row)).r;
        freq.w = texture(spectrum_tex, vec2(audio_bins.w, audio_row)).r;
        freq *= audio_gain;
    } else {
        vec4 phase = vec4(0.0, 1.7, 3.1, 4.6);
        vec4 rate  = vec4(0.65, 0.5, 0.38, 0.26);
        freq = 0.55 + 0.35 * sin(rate * TIME + phase);
    }
    return clamp(freq, 0.0, 2.0);
}

float field(vec3 p, float s){
    float strength = 7.0 + 0.03 * log(1e-6 + fract(sin(TIME) * 4373.11));
    float accum = s * 0.25;
    float prev = 0.0;
    float tw = 0.0;
    for (int i = 0; i < 26; i++){
        float mag = dot(p, p);
        p = abs(p) / mag + vec3(-0.5, -0.4, -1.5);
        float w = exp(-float(i) / 7.0);
        accum += w * exp(-strength * pow(abs(mag - prev), 2.2));
        tw += w;
        prev = mag;
    }
    return max(0.0, 5.0 * accum / max(tw, 1e-6) - 0.7);
}

float field2(vec3 p, float s){
    float strength = 7.0 + 0.03 * log(1e-6 + fract(sin(TIME) * 4373.11));
    float accum = s * 0.25;
    float prev = 0.0;
    float tw = 0.0;
    for (int i = 0; i < 18; i++){
        float mag = dot(p, p);
        p = abs(p) / mag + vec3(-0.5, -0.4, -1.5);
        float w = exp(-float(i) / 7.0);
        accum += w * exp(-strength * pow(abs(mag - prev), 2.2));
        tw += w;
        prev = mag;
    }
    return max(0.0, 5.0 * accum / max(tw, 1e-6) - 0.7);
}

vec3 nrand3(vec2 co){
    vec3 a = fract(cos(co.x * 8.3e-3 + co.y) * vec3(1.3e5, 4.7e5, 2.9e5));
    vec3 b = fract(sin(co.x * 0.3e-3 + co.y) * vec3(8.1e5, 1.0e5, 0.1e5));
    return mix(a, b, 0.5);
}

void fragment(){
    vec2 iResolution = vec2(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);

    vec2 uv01 = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
    vec2 uv = 2.0 * uv01 - 1.0;
    float aspect = iResolution.x / max(iResolution.y, 1.0);
    vec2 uvs = vec2(uv.x, uv.y / aspect);

    vec4 freqs = sample_audio_bins();

    vec3 p = vec3(uvs / 4.0, 0.0) + vec3(1.0, -1.3, 0.0);
    p += 0.2 * vec3(sin(TIME / 16.0), sin(TIME / 12.0), sin(TIME / 128.0));

    float t = field(p, freqs.z);
    float v = (1.0 - exp((abs(uv.x) - 1.0) * 6.0)) * (1.0 - exp((abs(uv.y) - 1.0) * 6.0));

    float layer_zoom = 4.0 + sin(TIME * 0.11) * 0.2 + 0.2 + sin(TIME * 0.15) * 0.3 + 0.4 + layer_offset;
    vec3 p2 = vec3(uvs / layer_zoom, 1.5) + vec3(2.0, -1.3, -1.0);
    p2 += 0.25 * vec3(sin(TIME / 16.0), sin(TIME / 12.0), sin(TIME / 128.0));

    float t2 = field2(p2, freqs.w);
    vec4 c2 = mix(0.4, 1.0, v) * vec4(1.3 * t2 * t2 * t2,
                                      1.8 * t2 * t2,
                                      t2 * freqs.x,
                                      t2);

    vec2 seed = p.xy * 2.0;
    seed = floor(seed * iResolution.x);
    vec3 rnd = nrand3(seed);
    vec4 starcolor = vec4(pow(rnd.y, 40.0));

    vec2 seed2 = p2.xy * 2.0;
    seed2 = floor(seed2 * iResolution.x);
    vec3 rnd2 = nrand3(seed2);
    starcolor += vec4(pow(rnd2.y, 40.0));

    starcolor *= star_mix;

    vec4 base = mix(freqs.w - 0.3, 1.0, v) * vec4(1.5 * freqs.z * t * t * t,
                                                  1.2 * freqs.y * t * t,
                                                  freqs.w * t,
                                                  1.0);

    vec3 col = (base.rgb + c2.rgb + starcolor.rgb) * exposure;
    col = clamp(col, 0.0, 1.0);

    COLOR = vec4(col, 1.0);
}
