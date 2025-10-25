shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D spectrum_tex;
uniform int bar_count = 64;

uniform sampler2D history_tex : hint_screen_texture, filter_linear_mipmap;

uniform bool use_audio = true;
uniform float audio_gain = 4.0;
uniform float feedback = 0.955;
uniform float rise_speed = 0.32;
uniform float swirl_strength = 0.95;
uniform float flow_scale = 1.35;
uniform float source_height = 0.5;
uniform float source_width = 0.7;
uniform float source_softness = 2.1;
uniform float blue_mix = 0.68;
uniform float grain_amount = 0.015;
uniform float gamma_correction = 1.1;
uniform float aspect = 1.7777;
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform vec2 rect_pos = vec2(0.0, 0.0);

const mat3 FBM_MAT = mat3(
        vec3(0.00, -0.80, -0.60),
        vec3(0.80,  0.36, -0.48),
        vec3(0.60, -0.48,  0.64)
);

float hashf(float n) { return fract(sin(n) * 43758.5453); }

float noise(vec3 x) {
        vec3 p = floor(x);
        vec3 f = fract(x);
        f = f * f * (3.0 - 2.0 * f);
        float n = p.x + p.y * 57.0 + 113.0 * p.z;
        float res = mix(mix(mix(hashf(n + 0.0), hashf(n + 1.0), f.x),
                               mix(hashf(n + 57.0), hashf(n + 58.0), f.x), f.y),
                         mix(mix(hashf(n + 113.0), hashf(n + 114.0), f.x),
                               mix(hashf(n + 170.0), hashf(n + 171.0), f.x), f.y), f.z);
        return res;
}

float snoise(vec3 x) { return noise(x) * 2.0 - 1.0; }

float fbm(vec3 p) {
        float f = 0.0;
        f += 0.5000 * snoise(p);       p = FBM_MAT * p * 2.02;
        f += 0.2500 * snoise(p);       p = FBM_MAT * p * 2.01;
        f += 0.1250 * snoise(p);       p = FBM_MAT * p * 1.99;
        f += 0.0625 * snoise(p);
        return f;
}

float hash21(vec2 p){
        vec3 p3 = fract(vec3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
}

float bar_at(int idx){
        if (bar_count <= 0) return 0.0;
        idx = clamp(idx, 0, bar_count - 1);
        float fb = float(bar_count);
        float u = (float(idx) + 0.5) / fb;
        return textureLod(spectrum_tex, vec2(u, 0.5), 0.0).r;
}

float band_avg(float a, float b){
        if (bar_count <= 0) return 0.0;
        int ia = int(floor(a * float(bar_count)));
        int ib = int(ceil(b * float(bar_count))) - 1;
        ia = clamp(ia, 0, max(0, bar_count - 1));
        ib = clamp(ib, ia, max(0, bar_count - 1));
        float accum = 0.0;
        int count = 0;
        for (int i = 0; i < 256; i++) {
                if (i < ia) continue;
                if (i > ib) break;
                if (i >= bar_count) break;
                accum += bar_at(i);
                count++;
        }
        return (count > 0) ? accum / float(count) : 0.0;
}

void fragment(){
        vec2 px = SCREEN_PIXEL_SIZE;
        if (px.x <= 0.0 || px.y <= 0.0) {
                px = vec2(1.0 / max(rect_size.x, 1.0), 1.0 / max(rect_size.y, 1.0));
        }

        vec2 uv = UV;
        vec2 screen_uv = SCREEN_UV;
        vec2 p = uv * 2.0 - 1.0;
        p.x *= aspect;

        float t = TIME;

        float low  = band_avg(0.0, 0.12);
        float mid  = band_avg(0.12, 0.36);
        float high = band_avg(0.36, 1.0);
        float energy_raw = (low * 2.35 + mid * 1.18 + high * 0.58) * audio_gain;
        float peak = max(low * 2.45, max(mid * 1.5, high * 1.08)) * audio_gain;
        float sparkle_drive = clamp(high * audio_gain * 1.95, 0.0, 3.8);
        if (!use_audio) {
                energy_raw = audio_gain * 0.55;
                peak = audio_gain * 0.5;
                sparkle_drive = audio_gain * 0.35;
        }
        float energy = clamp(energy_raw, 0.0, 9.0);
        peak = clamp(peak, 0.0, 5.5);

        float swell = smoothstep(0.02, 1.05, energy);
        float crest = smoothstep(0.08, 0.58, peak);
        float hit = smoothstep(0.12, 0.68, peak);
        float surge = smoothstep(0.04, 0.32, energy);
        hit = pow(hit, 1.1);
        float burst = clamp(max(hit, crest) * (0.92 + 0.7 * surge), 0.0, 1.8);
        float spark = pow(clamp(sparkle_drive, 0.0, 1.2), 1.15);

        vec3 flow_p = vec3(p * flow_scale, t * rise_speed * 0.25);
        vec2 swirl = vec2(
                fbm(flow_p + vec3(13.2, 7.1, 1.3)),
                fbm(flow_p + vec3(-9.5, 4.2, -1.7))
        );
        swirl = swirl * 2.0 - 1.0;

        float swirl_amp = swirl_strength * (0.36 + 0.52 * swell + 0.42 * burst);
        swirl_amp = clamp(swirl_amp, 0.0, 6.0);
        vec2 adv = vec2(
                swirl.x * swirl_amp * px.x * 90.0,
                swirl.y * swirl_amp * px.y * 55.0
        );
        float up = rise_speed * (0.4 + 0.7 * swell + 0.5 * burst);
        adv.y += px.y * up * 94.0;

        vec2 sample_uv = clamp(screen_uv + adv, vec2(0.0), vec2(1.0));
        vec3 prev = texture(history_tex, sample_uv).rgb;
        vec3 color = prev * feedback;

        float height_mask = smoothstep(-1.0 + source_height, 0.95, p.y);
        vec2 source_vec = vec2(
                p.x / max(source_width, 1e-4),
                (p.y + 1.0 - source_height) / max(0.52, 1e-4)
        );
        float radius_mask = exp(-pow(length(source_vec), source_softness));
        float base_mask = pow(clamp(height_mask * radius_mask, 0.0, 1.0), 1.2);
        float plume_noise = clamp(0.5 + 0.5 * fbm(flow_p * vec3(1.25, 1.65, 1.05) + vec3(0.0, t * 0.24, 1.9)), 0.0, 1.0);
        float sheet_noise = clamp(0.5 + 0.5 * fbm(flow_p * vec3(1.8, 2.2, 1.4) + vec3(2.4, -1.8, t * 0.32)), 0.0, 1.0);
        float column = base_mask * mix(0.75, 2.4, plume_noise * (0.65 + 0.35 * sheet_noise));

        float center_boost = exp(-pow(abs(p.x) * 1.8, 1.45));
        float bloom_boost = smoothstep(-0.95, -0.15, p.y);
        float mist_drive = surge * mix(0.04, 0.42, swell);
        float plume_drive = burst * (0.6 + 0.85 * plume_noise) * (0.9 + 0.65 * swell);
        float plume_gate = smoothstep(0.2, 0.75, peak) * (0.7 + 0.5 * hit);
        float source = column * (mist_drive + plume_gate * plume_drive);

        vec3 cool_base = mix(vec3(0.04, 0.09, 0.16), vec3(0.18, 0.38, 0.74), clamp(blue_mix + 0.45 * plume_noise + 0.2 * burst, 0.0, 1.0));
        vec3 cool = mix(cool_base, vec3(0.28, 0.55, 0.9), clamp(0.3 * plume_noise + 0.35 * swell, 0.0, 1.0));
        vec3 warm = mix(vec3(0.32, 0.24, 0.18), vec3(0.86, 0.71, 0.46), clamp(bloom_boost * 0.9 + plume_noise * 0.28, 0.0, 1.0));
        float warm_mix = clamp(center_boost * (0.45 + 0.28 * plume_noise) + bloom_boost * 0.35 + plume_gate * 0.35, 0.0, 0.8);
        vec3 plume_col = mix(cool, warm, warm_mix);

        vec3 highlight = vec3(0.92, 0.88, 0.78);
        float sparkle = pow(clamp(fbm(flow_p * 1.6 + vec3(3.2, -2.5, t * 0.5)), 0.0, 1.0), 2.6);

        float mist = column * mist_drive;
        float burst_gain = 0.9 + 1.2 * burst;
        vec3 injection = plume_col * source * (0.85 + 0.55 * plume_noise) * burst_gain;
        injection += cool * column * mist_drive * (0.55 + 0.5 * plume_noise);
        float tip_shine = (0.24 + 0.85 * bloom_boost) * (0.3 + 0.7 * plume_noise);
        float shine_gate = pow(clamp(plume_gate, 0.0, 1.0), 1.25) * (0.42 + 0.7 * spark);
        injection += highlight * column * plume_gate * sparkle * tip_shine * shine_gate;

        color += injection;

        float top_fog = smoothstep(-0.2, 0.9, p.y);
        vec3 fog_col = vec3(0.02, 0.03, 0.045);
        vec3 depth_tint = mix(vec3(0.008, 0.01, 0.02), vec3(0.05, 0.07, 0.09), smoothstep(-1.0, 0.6, p.y));
        color = mix(depth_tint, color, mix(0.7, 0.96, top_fog));

        vec2 res = vec2(1.0);
        if (px.x > 0.0 && px.y > 0.0) {
                res = vec2(1.0 / px.x, 1.0 / px.y);
        }
        float grain = hash21((uv * res) + vec2(t * 12.7, t * 19.1)) - 0.5;
        color += grain_amount * grain;

        color = max(color, vec3(0.0));
        color = pow(color, vec3(1.0 / max(gamma_correction, 1e-3)));
        COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}