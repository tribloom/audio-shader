shader_type canvas_item;
render_mode unshaded, blend_mix;

/* === pipeline uniforms === */
uniform sampler2D spectrum_tex;
uniform vec2      buffer_a_size = vec2(1920.0, 1080.0);

/* audio shaping (same pattern as your other shaders) */
uniform float audio_gamma = 2.0;
uniform float audio_gain  = 4.0;
uniform float audio_floor = 0.02;

/* look controls */
uniform float latent_scale      : hint_range(4.0, 40.0) = 16.0; // size of “features”
uniform float warp_amplitude    : hint_range(0.0, 0.5)  = 0.18; // how melty the shapes are
uniform float detail_mix        : hint_range(0.0, 1.0)  = 0.6;  // how much high-freq detail
uniform float brightness        : hint_range(0.0, 2.0)  = 1.0;
uniform float contrast          : hint_range(0.5, 2.0)  = 1.1;

/* === helpers === */
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 x)  { return clamp(x, vec3(0.0), vec3(1.0)); }

/* IQ-style Zucconi spectrum for nice color */
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

/* simplex noise (same as your other shaders) */
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

/* spectrum helper */
float sample_spectrum(float u) {
    float s = texture(spectrum_tex, vec2(saturate(u), 0.0)).r;
    s = max(audio_floor, s);
    s = pow(s, audio_gamma);      // input is positive, so this is safe
    return s * audio_gain;
}

void fragment() {
    vec2 res = buffer_a_size;
    if (res.x <= 0.0 || res.y <= 0.0) {
        res = vec2(1.0, 1.0);
    }

    vec2 frag = UV * res;
    vec2 uv   = frag / res;

    // aspect-correct centered coords in roughly −1..1 space
    float aspect = res.x / res.y;
    vec2 st = uv - 0.5;
    st.x *= aspect;

    float dist = length(st);

    // --- audio bands: low / mid / high ---
    float spec_low  = sample_spectrum(0.05);
    float spec_mid  = sample_spectrum(0.25);
    float spec_high = sample_spectrum(0.55);

    float low_n  = saturate(spec_low  * 0.25);  // 0..≈1
    float mid_n  = saturate(spec_mid  * 0.25);
    float high_n = saturate(spec_high * 0.25);

    // --- latent coordinate warp (like a tiny decoder) ---
    float base_scale = latent_scale / 10.0;
    float warp = warp_amplitude * (0.4 + 0.6 * low_n);

    // displace coordinates using two noise fields
    vec3 ncoord1 = vec3(st * base_scale, TIME * 0.18);
    vec3 ncoord2 = vec3(st * base_scale * 1.7, TIME * 0.23);

    float n1 = snoise(ncoord1);
    float n2 = snoise(ncoord2);

    vec2 disp = vec2(
        (n1 - 0.5) * warp,
        (n2 - 0.5) * warp
    );

    vec2 z = st + disp;

    // secondary detail field (higher frequency, blended in)
    vec3 ncoord3 = vec3(z * base_scale * 2.4, TIME * 0.31);
    float n3 = snoise(ncoord3);

    // combine three “latent channels” into a 3D vector
    vec3 latent = vec3(n1, n2, n3);

    // center around 0 and apply contrast
    latent = (latent - 0.5) * (1.5 + mid_n);

    // A tiny “ML-style” projection: two hidden neurons
    float h1 = dot(latent, vec3( 0.8, -0.3,  0.5));
    float h2 = dot(latent, vec3(-0.4,  0.9,  0.2));

    // squish to −1..1 with tanh-like polynomial
    float s1 = h1 / (1.0 + abs(h1));
    float s2 = h2 / (1.0 + abs(h2));

    // latent scalar: where the blobs are “alive”
    float latent_scalar = 0.5 + 0.35 * s1 + 0.15 * s2;

    // add a touch of high-frequency detail controlled by high band
    latent_scalar += (n3 - 0.5) * detail_mix * (0.3 + 0.7 * high_n);

    // clamp/shape and apply contrast knob
    latent_scalar = saturate(latent_scalar);
    latent_scalar = saturate((latent_scalar - 0.5) * contrast + 0.5);

    // use distance to center to damp edges a bit (keeps focus near center)
    float edge_falloff = 1.0 - saturate(dist * 0.8);
    float field = latent_scalar * (0.6 + 0.4 * edge_falloff);

// --- color mapping: treat field as hue coordinate ---
float hue_shift = TIME * 0.03 + mid_n * 0.15;
float hue = fract(field + hue_shift);   // wrap into [0,1]

    vec3 color = spectral_zucconi6(hue);

    // overall brightness follows low + mid energy
    float loud = saturate(0.6 * low_n + 0.4 * mid_n);
    float gain = brightness * (0.35 + loud * 1.4);
    color *= gain;

    COLOR = vec4(saturate(color), 1.0);
}
