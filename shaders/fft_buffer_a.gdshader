shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D history_tex : hint_screen_texture, filter_linear;
uniform vec2 buffer_a_size = vec2(1920.0, 1080.0);

uniform float kick = 0.0;
uniform float kick_env = 0.0;
uniform float drive_gain : hint_range(0.0, 8.0) = 2.0;
uniform float drive_floor : hint_range(0.0, 1.0) = 0.08;
uniform float drive_ceiling : hint_range(0.0, 1.0) = 0.5;
uniform float advect_strength : hint_range(0.0, 0.3) = 0.055;
uniform float fade_strength : hint_range(0.0, 2.0) = 0.42;

const float FRAME_DT = 1.0 / 60.0;
//const float PI = 3.14159265359;

float hash13(vec3 p3) {
        p3 = fract(p3 * 0.1031);
        p3 += dot(p3, p3.zyx + 31.32);
        return fract((p3.x + p3.y) * p3.z);
}

float gyroid(vec3 seed) {
        return dot(sin(seed), cos(seed.yzx));
}

float fbm(vec3 seed) {
        float result = 0.0;
        float amp = 0.5;
        for (int i = 0; i < 4; i++) {
                seed += result * 0.5;
                seed.y -= 0.1 * TIME / max(amp, 1e-4);
                result += gyroid(seed / max(amp, 1e-4)) * amp;
                amp /= 3.0;
        }
        return result;
}

float sample_prev(vec2 uv) {
        vec2 sample_uv = clamp(uv, vec2(0.0), vec2(1.0));
        return texture(history_tex, sample_uv).r;
}

vec2 decode_velocity(vec2 packed_v) {
        return packed_v * 2.0 - vec2(1.0);
}

vec2 encode_velocity(vec2 v) {
        return clamp(v * 0.5 + vec2(0.5), vec2(0.0), vec2(1.0));
}

vec4 compute_drive() {
        float drive_in = max(kick, kick_env);
        float norm = clamp(drive_in * drive_gain, 0.0, 1.0);
        float gate = smoothstep(drive_floor, drive_ceiling, norm);
        float eased = smoothstep(0.0, drive_floor, norm);
        float pulse = max(gate, norm * 0.6);
        float lift = max(eased * 0.35, norm * 0.2);
        return vec4(norm, gate, pulse, lift);
}

void fragment() {
        vec2 resolution = buffer_a_size;
        if (resolution.x <= 0.0 || resolution.y <= 0.0) {
                resolution = vec2(textureSize(history_tex, 0));
        }
        if (resolution.x <= 0.0 || resolution.y <= 0.0) {
                resolution = vec2(1920.0, 1080.0);
        }

        vec2 base_uv = vec2(UV.x, 1.0 - UV.y);
        vec2 frag_coord = base_uv * resolution;
        vec2 p = (2.0 * frag_coord - resolution) / max(resolution.y, 1.0);

        float frame_index = floor(TIME * 60.0);
        float rng = hash13(vec3(frag_coord, frame_index));
        vec4 drive = compute_drive();
        float drive_norm = drive.x;
        float drive_gate = drive.y;
        float drive_pulse = drive.z;
        float drive_lift = drive.w;

        vec3 seed = vec3(p, length(p) + TIME) * 2.0;
        float noise = fbm(seed);
        float angle = noise * PI;

        vec3 unit = vec3(vec2(max(0.0025, 0.05 * rng)), 0.0);
        vec2 normal_sample_x = unit.xz;
        vec2 normal_sample_y = unit.zy;
        vec3 normal_vec = vec3(
                sample_prev(base_uv - normal_sample_x) - sample_prev(base_uv + normal_sample_x),
                sample_prev(base_uv - normal_sample_y) - sample_prev(base_uv + normal_sample_y),
                max(unit.y, 1e-3)
        );
        float norm_len = max(length(normal_vec), 1e-4);
        vec3 normal = normal_vec / norm_len;

        vec2 mask = vec2(1.0 - abs(base_uv.x - 0.5), base_uv.y);

        float emitter = smoothstep(0.18, 0.02, base_uv.y);
        float center = smoothstep(0.05, 0.42, mask.x);
        float puff_core = emitter * center * drive_pulse;
        float puff = puff_core * mix(0.8, 1.2, rng);

        vec2 offset = vec2(0.0);
        float turbulence = fbm(seed + vec3(0.195));
        offset -= vec2(cos(angle), sin(angle)) * turbulence * (1.0 - mask.y);
        offset -= normal.xy * mask.y * 0.6;

        vec2 velocity = vec2(0.0);
        vec2 prev_vel_uv = clamp(base_uv, vec2(0.0), vec2(1.0));
        vec2 prev_velocity = decode_velocity(texture(history_tex, prev_vel_uv).yz);
        velocity = clamp(prev_velocity * 0.9, vec2(-1.0), vec2(1.0));

        float impulse = max(puff_core, emitter * (drive_norm * 0.2 + drive_lift * 0.4));
        float swirl = mix(0.3, 0.52, rng);
        velocity += vec2(cos(angle), sin(angle)) * impulse * swirl;
        velocity += vec2(0.0, 1.0) * impulse * mix(0.65, 0.95, rng);
        velocity = clamp(velocity, vec2(-1.0), vec2(1.0));

        offset -= vec2(0.0, 1.0) * (1.0 - mask.y);
        offset += velocity;

        float advect_drive = mix(0.35, 0.95, drive_pulse);
        vec2 advect_uv = clamp(base_uv + advect_strength * offset * advect_drive, vec2(0.0), vec2(1.0));
        vec4 frame = texture(history_tex, advect_uv);

        float fade = FRAME_DT * fade_strength * mix(0.3, 1.0, drive_gate);
        float seeded = max(puff, emitter * (drive_norm * 0.18 + drive_lift * 0.32));
        float shape_val = max(seeded, frame.r - fade);
        shape_val = clamp(shape_val, 0.0, 1.0);

        COLOR = vec4(shape_val, encode_velocity(velocity), 1.0);
        if (frag_coord.x < 1.0 && frag_coord.y < 1.0) {
                COLOR = vec4(0.0, 0.0, 0.0, 1.0);
        }
}