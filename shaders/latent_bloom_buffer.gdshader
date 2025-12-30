shader_type canvas_item;
render_mode unshaded, blend_mix;

/* === pipeline uniforms (match your setup) === */
uniform sampler2D spectrum_tex;
uniform sampler2D history_tex : hint_screen_texture, filter_linear;
uniform vec2 buffer_a_size = vec2(1920.0, 1080.0);

/* audio shaping */
uniform float audio_gamma = 2.2;
uniform float audio_gain  = 3.5;
uniform float audio_floor = 0.02;

/* look controls */
uniform float cell_scale       : hint_range(2.0, 32.0) = 12.0; // size of latent blobs
uniform float warp_strength    : hint_range(0.0, 1.0)  = 0.35; // how “melty” the shapes are
uniform float color_shift_speed: hint_range(0.0, 2.0)  = 0.35; // how fast hues drift
uniform float feedback_mix     : hint_range(0.0, 1.0)  = 0.90; // 0=fresh, 1=ghosty
uniform float noise_amount     : hint_range(0.0, 0.2)  = 0.04; // jitter for history

const float ZUCCONI_OFFSET = 1.05;

/* === helpers (same flavor as espial/orbit) === */
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 x)  { return clamp(x, vec3(0.0), vec3(1.0)); }

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

    return bump3y(c1 * (x - x1), y1) +
           bump3y(c2 * (x - x2), y2);
}

/* simplex noise */
vec4 permute(vec4 x) { return mod(x * x * 34.0 + x, 289.0); }

float snoise(vec3 v) {
    const vec2 C = vec2(0.16666666666, 0.33333333333);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

    vec3 i = floor(C.y * (v.x + v.y + v.z) + v);
    vec3 x0 = v - i + C.x * (i.x + i.y + i.z);

    vec3 g = step(vec3(x0.y, x0.z, x0.x), x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, vec3(l.z, l.x, l.y));
    vec3 i2 = max(g.xyz, vec3(l.z, l.x, l.y));

    vec3 x1 = x0 - i1 + C.x;
    vec3 x2 = x0 - i2 + C.y;
    vec3 x3 = x0 - D.yyy;

    i = mod(i, 289.0);
    vec4 p = permute(
        permute(
            permute(i.z + vec4(0.0, i1.z, i2.z, 1.0)) +
            i.y + vec4(0.0, i1.y, i2.y, 1.0)
        ) +
        i.x + vec4(0.0, i1.x, i2.x, 1.0)
    );

    vec3 ns = 0.142857142857 * D.wyz - D.xzx;
    vec4 j = -49.0 * floor(p * ns.z * ns.z) + p;

    vec4 x_ = floor(j * ns.z);
    vec4 x = x_ * ns.x + ns.yyyy;

    vec4 y_ = floor(j - 7.0 * x_);
    vec4 y = y_ * ns.x + ns.yyyy;

    vec4 h = 1.0 - abs(x) - abs(y);

    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);

    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));

    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);

    vec4 norm = inversesqrt(vec4(
        dot(p0, p0), dot(p1, p1),
        dot(p2, p2), dot(p3, p3)
    ));

    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    vec4 m = max(
        0.6 - vec4(
            dot(x0, x0), dot(x1, x1),
            dot(x2, x2), dot(x3, x3)
        ),
        0.0
    );

    return 0.5 + 12.0 * dot(
        m * m * m,
        vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3))
    );
}

/* audio radius mapping – same idea as orbit */
float spatialize_audio(float dist) {
    float fft_domain = dist * dist;
    float fft_u = clamp(fft_domain * 0.09, 0.0, 1.0);
    float fft = texture(spectrum_tex, vec2(fft_u, 0.0)).r;
    fft = max(audio_floor, pow(max(fft, 0.0), audio_gamma));
    return fft * audio_gain;
}

/* === MAIN === */
void fragment() {
    vec2 resolution = buffer_a_size;
    if (resolution.x <= 0.0 || resolution.y <= 0.0) {
        resolution = vec2(1.0, 1.0);
    }

    vec2 frag_coord = UV * resolution;
    vec2 uv  = frag_coord / resolution;
    vec2 st  = (2.0 * frag_coord - resolution) / min(resolution.x, resolution.y);

    float dist = length(st);

    // audio along radius (smooth – no transient trickery here)
    float audio_signal = spatialize_audio(dist);
    float a = clamp(audio_signal, 0.0, 4.0);
    float audio_norm = saturate(a / 4.0); // 0..1 normalized

    // === latent “blob” field ===
    // base UV field with slight swirl from audio
    float theta = atan(st.y, st.x);
    float swirl = theta + audio_norm * 0.6;

    vec2 swirl_uv = vec2(
        st.x * cos(swirl) - st.y * sin(swirl),
        st.x * sin(swirl) + st.y * cos(swirl)
    );

    float scale = cell_scale / 10.0; // remap to friendlier range
    vec3 p1 = vec3(swirl_uv * scale, TIME * 0.18);
    vec3 p2 = vec3(swirl_uv * (scale * 1.7), TIME * 0.23);

    float n1 = snoise(p1);
    float n2 = snoise(p2);

    // combine noises into a pseudo-latent value 0..1
    float latent = saturate(0.5 * n1 + 0.5 * n2);

    // warp latent by audio so louder sections are more contrasty
    float contrast = mix(0.8, 1.5, audio_norm);
    float latent_c = saturate((latent - 0.5) * contrast + 0.5);

    // use spectrum along X to introduce subtle “directional” flavor
    float spec_x = texture(spectrum_tex, vec2(uv.x, 0.0)).r;
    float spec_t = saturate(spec_x * 4.0);

    // final palette domain: latent + audio + slow time shift
    float t = latent_c
            + spec_t * 0.15
            + TIME * color_shift_speed * 0.15;

    // center bias keeps edges a bit calmer
    float center_bias = 1.0 - saturate(dist * 0.9);
    t += center_bias * 0.15 * audio_norm;

    vec3 base_color = spectral_zucconi6(t);

    // scale by audio overall (so silence dims naturally)
    vec3 color = base_color * (0.3 + audio_norm * 1.2);

    // === feedback: gentle echo from history_tex ===
    float noise_scale = 1.0 + sin(TIME * 0.5) * 0.2;
    vec2 noise_domain = st * noise_scale;

    vec2 jitter = (vec2(
        snoise(vec3(noise_domain, TIME * 0.30)),
        snoise(vec3(noise_domain + vec2(1000.0), TIME * 0.30))
    ) - vec2(0.5)) * noise_amount * 2.0;

    vec2 history_uv = uv + jitter;
    history_uv = clamp(history_uv, vec2(0.001), vec2(0.999));

    vec3 prev_color = texture(history_tex, history_uv).rgb;

    color = mix(color, prev_color, feedback_mix);

    COLOR = vec4(saturate(color), 1.0);
}
