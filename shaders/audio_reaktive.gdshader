shader_type canvas_item;
render_mode unshaded;

uniform sampler2D spectrum_tex : hint_default_black;
uniform float time_scale = 1.0;
uniform float spectrum_row = 0.25;
uniform vec4 spectrum_uvs = vec4(0.01, 0.07, 0.15, 0.30);

float field(vec3 p, float s, float iTime) {
    float strength = 7.0 + 0.03 * log(1.0e-6 + fract(sin(iTime) * 4373.11));
    float accum = s / 4.0;
    float prev = 0.0;
    float tw = 0.0;
    for (int i = 0; i < 26; i++) {
        float mag = dot(p, p);
        p = abs(p) / mag + vec3(-0.5, -0.4, -1.5);
        float w = exp(-float(i) / 7.0);
        accum += w * exp(-strength * pow(abs(mag - prev), 2.2));
        tw += w;
        prev = mag;
    }
    return max(0.0, 5.0 * accum / tw - 0.7);
}

float field2(vec3 p, float s, float iTime) {
    float strength = 7.0 + 0.03 * log(1.0e-6 + fract(sin(iTime) * 4373.11));
    float accum = s / 4.0;
    float prev = 0.0;
    float tw = 0.0;
    for (int i = 0; i < 18; i++) {
        float mag = dot(p, p);
        p = abs(p) / mag + vec3(-0.5, -0.4, -1.5);
        float w = exp(-float(i) / 7.0);
        accum += w * exp(-strength * pow(abs(mag - prev), 2.2));
        tw += w;
        prev = mag;
    }
    return max(0.0, 5.0 * accum / tw - 0.7);
}

vec3 nrand3(vec2 co) {
    vec3 a = fract(cos(co.x * 8.3e-3 + co.y) * vec3(1.3e5, 4.7e5, 2.9e5));
    vec3 b = fract(sin(co.x * 0.3e-3 + co.y) * vec3(8.1e5, 1.0e5, 0.1e5));
    return mix(a, b, 0.5);
}

void fragment() {
    float iTime = TIME * time_scale;

    vec2 iResolution = vec2(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);
    vec2 fragCoord = vec2(UV.x, 1.0 - UV.y) * iResolution;
    vec2 uv = 2.0 * fragCoord / iResolution - 1.0;
    vec2 uvs = uv * iResolution / max(iResolution.x, iResolution.y);

    vec3 p = vec3(uvs / 4.0, 0.0) + vec3(1.0, -1.3, 0.0);
    p += 0.2 * vec3(sin(iTime / 16.0), sin(iTime / 12.0), sin(iTime / 128.0));

    float freq0 = texture(spectrum_tex, vec2(spectrum_uvs.x, spectrum_row)).r;
    float freq1 = texture(spectrum_tex, vec2(spectrum_uvs.y, spectrum_row)).r;
    float freq2 = texture(spectrum_tex, vec2(spectrum_uvs.z, spectrum_row)).r;
    float freq3 = texture(spectrum_tex, vec2(spectrum_uvs.w, spectrum_row)).r;

    float t = field(p, freq2, iTime);
    float v = (1.0 - exp((abs(uv.x) - 1.0) * 6.0)) * (1.0 - exp((abs(uv.y) - 1.0) * 6.0));

    vec3 p2 = vec3(uvs / (4.0 + sin(iTime * 0.11) * 0.2 + 0.2 + sin(iTime * 0.15) * 0.3 + 0.4), 1.5)
            + vec3(2.0, -1.3, -1.0);
    p2 += 0.25 * vec3(sin(iTime / 16.0), sin(iTime / 12.0), sin(iTime / 128.0));
    float t2 = field2(p2, freq3, iTime);
    vec4 c2 = mix(0.4, 1.0, v) * vec4(1.3 * t2 * t2 * t2, 1.8 * t2 * t2, t2 * freq0, t2);

    vec2 seed = p.xy * 2.0;
    seed = floor(seed * iResolution.x);
    vec3 rnd = nrand3(seed);
    vec4 starcolor = vec4(pow(rnd.y, 40.0));

    vec2 seed2 = p2.xy * 2.0;
    seed2 = floor(seed2 * iResolution.x);
    vec3 rnd2 = nrand3(seed2);
    starcolor += vec4(pow(rnd2.y, 40.0));

    vec4 base = mix(freq3 - 0.3, 1.0, v)
              * vec4(1.5 * freq2 * t * t * t, 1.2 * freq1 * t * t, freq3 * t, 1.0);

    vec3 col = base.rgb + c2.rgb + starcolor.rgb;

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}