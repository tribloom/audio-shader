shader_type canvas_item;
render_mode unshaded;

/* ---------- Screen / camera ---------- */
uniform float aspect = 1.7777778;                 // set from GDScript if you want
uniform vec2  viewport_size = vec2(1920.0,1080.0); // set to your viewport each frame

/* ---------- March / volume ---------- */
uniform int   steps        = 144;   // 100..180 (RTX 3080: 144–160)
uniform float max_dist     = 3.4;
uniform float density_coef = 1.7;
uniform float step_jitter  = 0.03;  // 0.02..0.04
uniform float flow_speed   = 0.12;

/* ---------- Noise shaping ---------- */
uniform float noise_scale  = 1.55;
uniform float threshold    = 0.47;  // lower = more fog
uniform float shape_power  = 1.22;
uniform float warp_amp     = 0.50;
uniform float warp_scale   = 1.15;

/* ---------- Color ---------- */
uniform vec3  color_low    = vec3(0.08, 0.52, 0.92);
uniform vec3  color_high   = vec3(0.92, 0.28, 0.95);
uniform float brightness    = 1.8;
uniform float ambient_mix   = 0.38;

/* ---------- RNG / Noise utils ---------- */
float hash31(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float value_noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n000 = hash31(i + vec3(0,0,0));
    float n100 = hash31(i + vec3(1,0,0));
    float n010 = hash31(i + vec3(0,1,0));
    float n110 = hash31(i + vec3(1,1,0));
    float n001 = hash31(i + vec3(0,0,1));
    float n101 = hash31(i + vec3(1,0,1));
    float n011 = hash31(i + vec3(0,1,1));
    float n111 = hash31(i + vec3(1,1,1));

    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);
    return mix(nxy0, nxy1, f.z);
}

float fbm(vec3 p) {
    float s = 0.0;
    float a = 0.5;
    float f = 1.0;
    for (int i = 0; i < 6; i++) {
        s += a * value_noise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

/* Stable per-step RNG (seed passed from fragment) */
float rng_step(vec2 pix, int i) {
    vec3 s = vec3(pix, float(i));
    return fract(sin(dot(s, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

/* ---------- Density field (with domain warp) ---------- */
float fog_density(vec3 p) {
    vec3 w = p * warp_scale;
    float w1 = fbm(w + vec3(0.0, 0.0, TIME * flow_speed * 1.1));
    float w2 = fbm(w + vec3(5.2, 3.7, TIME * flow_speed * 0.9));
    p += warp_amp * vec3(w1, w2, w1 - w2);

    float n = fbm(p);
    float d = smoothstep(threshold, 1.0, n);
    return pow(d, shape_power);
}

/* ---------- Main ---------- */
void fragment() {
    // per-pixel integer coords for RNG seed
    vec2 pix = floor(UV * viewport_size);

    // camera ray in a fake 3D volume
    vec2 uv = UV * 2.0 - 1.0;
    uv.x *= aspect;
    vec3 ro = vec3(0.0, 0.0, -0.5);
    vec3 rd = normalize(vec3(uv, 1.25));

    float T = 1.0;
    vec3  acc = vec3(0.0);

    float t  = 0.0;
    float dt = max_dist / float(max(1, steps));

    // small per-pixel base jitter
    float base_j = (rng_step(pix, -1) - 0.5) * step_jitter * 0.5;

    for (int i = 0; i < 200; i++) {
        if (i >= steps) break;
        if (T < 0.01)   break;

        float ji = (rng_step(pix, i) - 0.5) * step_jitter;

        // two-tap (trapezoid) integration
        float ta = t + base_j + ji;
        float tb = ta + 0.5 * dt;

        vec3 posA = ro + rd * ta;
        vec3 posB = ro + rd * tb;

        vec3 npA = posA * noise_scale + vec3(0.0, 0.0, TIME * flow_speed);
        vec3 npB = posB * noise_scale + vec3(0.0, 0.0, TIME * flow_speed);

        float densA = fog_density(npA);
        float densB = fog_density(npB);
        float dens  = 0.5 * (densA + densB);

        float sigma = density_coef * dens;
        float a = 1.0 - exp(-sigma * dt);

        vec3 c = mix(color_low, color_high, dens);
        acc += T * a * (ambient_mix + (1.0 - ambient_mix) * dens) * c;
        T   *= (1.0 - a);

        t += dt;
    }

    vec3 col = brightness * acc;

    // tiny dither from the same RNG
    float n = (rng_step(pix, -7) - 0.5) * (1.0 / 255.0);
    col += vec3(n);

    COLOR = vec4(col, 1.0);
}
