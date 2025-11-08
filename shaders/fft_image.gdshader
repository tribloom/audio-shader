shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D buffer_a_tex : filter_linear;
uniform vec2 buffer_a_size = vec2(1920.0, 1080.0);

uniform float drive_gain : hint_range(0.0, 8.0) = 2.0;
uniform float drive_floor : hint_range(0.0, 1.0) = 0.08;
uniform float drive_ceiling : hint_range(0.0, 1.0) = 0.5;
uniform float signal_gamma : hint_range(0.1, 4.0) = 0.9;
uniform float advect_strength : hint_range(0.0, 0.3) = 0.055;
uniform float fade_strength : hint_range(0.0, 2.0) = 0.42;

uniform float color_strength : hint_range(0.0, 4.0) = 1.1;
uniform float light_strength : hint_range(0.0, 2.0) = 1.0;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.8;

float hash13(vec3 p3) {
        p3 = fract(p3 * 0.1031);
        p3 += dot(p3, p3.zyx + 31.32);
        return fract((p3.x + p3.y) * p3.z);
}

float sample_buffer(vec2 uv) {
        vec2 sample_uv = clamp(uv, vec2(0.0), vec2(1.0));
        return texture(buffer_a_tex, sample_uv).r;
}

vec2 resolve_resolution() {
        vec2 res = vec2(0.0);
        if (buffer_a_size.x > 0.0 && buffer_a_size.y > 0.0) {
                res = buffer_a_size;
        }
        if (res.x <= 0.0 || res.y <= 0.0) {
                res = vec2(textureSize(buffer_a_tex, 0));
        }
        if (res.x <= 0.0 || res.y <= 0.0) {
                res = vec2(1920.0, 1080.0);
        }
        return res;
}

float remap_signal(float raw_value) {
        float denom = max(drive_ceiling - drive_floor, 1e-4);
        float normalized = clamp((raw_value - drive_floor) / denom, 0.0, 1.0);
        float shaped = pow(max(normalized, 0.0), max(signal_gamma, 0.1));
        float boosted = clamp(shaped * drive_gain, 0.0, 1.0);
        float floor_bias = smoothstep(0.0, drive_floor, raw_value) * 0.22;
        float sustain = normalized * 0.35;
        return clamp(max(boosted, sustain) + floor_bias, 0.0, 1.0);
}

void fragment() {
        vec2 resolution = resolve_resolution();
        vec2 base_uv = vec2(UV.x, 1.0 - UV.y);
        vec2 frag_coord = base_uv * resolution;
        vec2 uv = base_uv;

        vec4 data = texture(buffer_a_tex, clamp(uv, vec2(0.0), vec2(1.0)));
        float signal = remap_signal(data.r);

        vec3 palette = 0.5 + 0.5 * cos(vec3(1.0, 2.0, 3.0) * 5.5 + clamp(signal, 0.0, 1.0) * 5.0 - 4.0 * uv.y);
        vec3 color = mix(vec3(0.0), palette, signal);

        float frame_index = floor(TIME * 60.0);
        float rng = hash13(vec3(frag_coord, frame_index));
        float eps = max(0.01, 0.05 * rng);
        vec3 unit = vec3(vec2(eps), 0.0);

        vec2 sample_x = unit.xz;
        vec2 sample_y = unit.zy;
        float sample_dx = sample_buffer(uv - sample_x) - sample_buffer(uv + sample_x);
        float sample_dy = sample_buffer(uv - sample_y) - sample_buffer(uv + sample_y);
        vec3 normal_vec = vec3(sample_dx, sample_dy, max(unit.y, 1e-3));
        float norm_len = max(length(normal_vec), 1e-4);
        vec3 normal = normal_vec / norm_len;

        vec3 light_dir = normalize(vec3(0.0, 4.0, 1.0));
        float light = dot(normal, light_dir) * 0.5 + 0.5;
        color += light_strength * light * signal;

        color = mix(color, color * data.r, shadow_strength);
        color = clamp(color * color_strength, vec3(0.0), vec3(1.0));

        COLOR = vec4(color, 1.0);
}