shader_type canvas_item;
render_mode unshaded, blend_mix;

// Port of "Julie's Dunes study" buffer A pass by Kazimierz Pogoda
// https://www.shadertoy.com/view/md3Sz4
const float ZUCCONI_OFFSET = 1.05;

uniform sampler2D spectrum_tex;
uniform sampler2D history_tex : hint_screen_texture, filter_linear;
uniform vec2 buffer_a_size = vec2(1920.0, 1080.0);

float saturate(float x) {
        return clamp(x, 0.0, 1.0);
}

vec3 saturate(vec3 x) {
        return clamp(x, vec3(0.0), vec3(1.0));
}

vec3 bump3y(vec3 x, vec3 yoffset) {
        vec3 y = vec3(1.0) - x * x;
        y = saturate(y - yoffset);
        return y;
}

vec3 spectral_zucconi6(float x) {
        const vec3 c1 = vec3(3.54585104, 2.93225262, 2.41593945);
        const vec3 x1 = vec3(0.69549072, 0.49228336, 0.27699880);
        const vec3 y1 = vec3(0.02312639, 0.15225084, 0.52607955);

        const vec3 c2 = vec3(3.90307140, 3.21182957, 3.96587128);
        const vec3 x2 = vec3(0.11748627, 0.86755042, 0.66077860);
        const vec3 y2 = vec3(0.84897130, 0.88445281, 0.73949448);

        return bump3y(c1 * (x - x1), y1) + bump3y(c2 * (x - x2), y2);
}

vec4 permute(vec4 x) {
        return mod(x * x * 34.0 + x, 289.0);
}

float snoise(vec3 v) {
        const vec2 C = vec2(0.16666666666, 0.33333333333);
        const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

        vec3 i = floor(C.y * (v.x + v.y + v.z) + v);
        vec3 x0 = C.x * (i.x + i.y + i.z) + (v - i);
        vec3 g = step(x0.yzx, x0);
        vec3 l = (1.0 - g).zxy;
        vec3 i1 = min(g, l);
        vec3 i2 = max(g, l);

        vec3 x1 = x0 - i1 + C.x;
        vec3 x2 = x0 - i2 + C.y;
        vec3 x3 = x0 - D.yyy;

        i = mod(i, 289.0);
        vec4 p = permute(permute(permute(
                i.z + vec4(0.0, i1.z, i2.z, 1.0))
                + i.y + vec4(0.0, i1.y, i2.y, 1.0))
                + i.x + vec4(0.0, i1.x, i2.x, 1.0));

        vec3 ns = 0.142857142857 * D.wyz - D.xzx;
        vec4 j = -49.0 * floor(p * ns.z * ns.z) + p;

        vec4 x_ = floor(j * ns.z);
        vec4 x = x_ * ns.x + ns.yyyy;
        vec4 y = floor(j - 7.0 * x_) * ns.x + ns.yyyy;
        vec4 h = 1.0 - abs(x) - abs(y);

        vec4 b0 = vec4(x.xy, y.xy);
        vec4 b1 = vec4(x.zw, y.zw);

        vec4 sh = -step(h, vec4(0.0));
        vec4 a0 = b0.xzyw + (floor(b0) * 2.0 + 1.0).xzyw * sh.xxyy;
        vec4 a1 = b1.xzyw + (floor(b1) * 2.0 + 1.0).xzyw * sh.zzww;

        vec3 p0 = vec3(a0.xy, h.x);
        vec3 p1 = vec3(a0.zw, h.y);
        vec3 p2 = vec3(a1.xy, h.z);
        vec3 p3 = vec3(a1.zw, h.w);

        vec4 norm = inversesqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
        p0 *= norm.x;
        p1 *= norm.y;
        p2 *= norm.z;
        p3 *= norm.w;

        vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
        return 0.5 + 12.0 * dot(m * m * m,
                vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

float spatialize_audio(float dist) {
        float fft_domain = pow(dist, 2.0);
        float fft = texture(spectrum_tex, vec2(fft_domain * 0.09, 0.25)).r;
        return pow(fft, 4.0);
}

void fragment() {
        vec2 resolution = buffer_a_size;
        if (resolution.x <= 0.0 || resolution.y <= 0.0) {
                resolution = 1.0 / SCREEN_PIXEL_SIZE;
        }
        vec2 frag_coord = UV * resolution;
        vec2 uv = frag_coord / resolution;
        vec2 st = (2.0 * frag_coord - resolution) / min(resolution.x, resolution.y);
        float dist = length(st);

        float audio_signal = spatialize_audio(dist);
        float zucconi_domain = ZUCCONI_OFFSET - dist;
        vec3 color = spectral_zucconi6(zucconi_domain) * audio_signal * 0.2;

        float noise_scale = 1.0;
        vec2 noise_domain = st * noise_scale;
        vec2 offset = uv + (vec2(
                snoise(vec3(noise_domain, TIME * 0.3)),
                snoise(vec3(noise_domain + vec2(1000.0), TIME * 0.3))
        ) - vec2(0.5)) * 0.04;

        vec3 prev_color = texture(history_tex, offset).rgb;
        color += prev_color * 0.95;

        COLOR = vec4(color, audio_signal);
}