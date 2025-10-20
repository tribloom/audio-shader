shader_type canvas_item;

// Multi-lobed aurora bloom with optional audio drive
// Inspired by vibrant petal-like spectral flows.

/* ---- Audio inputs ---- */
uniform bool use_audio = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float u_bass : hint_range(0.0, 1.0) = 0.18;
uniform float u_mid : hint_range(0.0, 1.0) = 0.45;
uniform float u_high : hint_range(0.0, 1.0) = 0.78;
uniform float audio_gain : hint_range(0.0, 4.0) = 1.5;
uniform float audio_bias : hint_range(0.0, 1.0) = 0.12;

/* ---- Visual controls ---- */
uniform float petal_count : hint_range(3.0, 12.0) = 7.0;
uniform float swirl_strength : hint_range(0.0, 6.0) = 3.2;
uniform float swirl_speed : hint_range(0.0, 4.0) = 1.1;
uniform float ribbon_sharpness : hint_range(0.5, 6.0) = 2.8;
uniform float glow_width : hint_range(0.1, 1.2) = 0.55;
uniform float color_cycle : hint_range(0.0, 4.0) = 0.35;
uniform float background_dim : hint_range(0.0, 1.0) = 0.25;
uniform float star_density : hint_range(0.0, 2.0) = 0.55;
uniform float star_shimmer : hint_range(0.0, 4.0) = 1.2;
uniform float kick_flash_gain : hint_range(0.0, 4.0) = 1.4;
uniform float aspect : hint_range(0.1, 4.0) = 1.7777;

/* ---- Optional injected uniforms from Visualizer ---- */
uniform float kick_env : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p){
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float samp(float u){
    float du = 0.005;
    float acc = 0.0;
    float w = 0.0;
    for(int i = -2; i <= 2; i++){
        float uu = clamp(u + du * float(i), 0.0, 1.0);
        acc += texture(spectrum_tex, vec2(uu, 0.25)).r;
        w += 1.0;
    }
    return (w > 0.0) ? acc / w : 0.0;
}

vec3 palette(float h){
    return 0.55 + 0.45 * cos(TAU * (vec3(h) + vec3(0.0, 0.33, 0.67)));
}

float petal_field(float ang, float lobes, float sharp){
    float wave = cos(ang * lobes * 0.5);
    wave = abs(wave);
    return pow(wave, sharp);
}

float bloom(float r, float w){
    float g = clamp(1.0 - r / max(0.0001, w), 0.0, 1.0);
    return g * g;
}

void fragment(){
    vec2 q = UV;
    vec2 p = q * 2.0 - 1.0;
    p.x *= aspect;

    float radius = length(p);
    float base_angle = atan(p.y, p.x);

    float bass = use_audio ? samp(u_bass) : 0.28 + 0.18 * sin(TIME * 0.6);
    float mid = use_audio ? samp(u_mid) : 0.24 + 0.18 * sin(TIME * 0.9 + 1.2);
    float treble = use_audio ? samp(u_high) : 0.22 + 0.18 * sin(TIME * 1.3 + 2.4);

    float drive = audio_gain * (0.45 * bass + 0.35 * mid + 0.2 * treble) + audio_bias;
    drive = clamp(drive, 0.0, 3.5);
    float swirl = swirl_strength * drive;
    float twist = swirl_speed * TIME + swirl * pow(radius, 0.65);
    float angle = base_angle + twist;

    float petals = petal_field(angle, petal_count, ribbon_sharpness);
    float radial = exp(-radius * (1.4 - 0.5 * drive));
    float glow = bloom(radius, glow_width) * (0.9 + 1.4 * drive);

    float hue = fract(base_angle / TAU + color_cycle * TIME + 0.25 * drive + 0.12 * radius);
    vec3 col = palette(hue);
    col *= mix(0.2, 1.6, petals);
    col *= mix(0.6, 1.4, radial);
    col += palette(hue + 0.12) * glow;

    float center_flash = kick_flash_gain * kick_env;
    col += vec3(1.2, 0.9, 1.5) * center_flash * exp(-9.0 * radius);

    vec3 bg_lo = vec3(0.01, 0.02, 0.04);
    vec3 bg_hi = vec3(0.08, 0.09, 0.12);
    float vignette = smoothstep(0.9, 0.2, radius);
    vec3 bg = mix(bg_lo, bg_hi, vignette);
    bg *= mix(1.0, 0.4, background_dim);

    vec2 star_uv = p * 3.5;
    vec2 cell = floor(star_uv);
    vec2 fract_uv = fract(star_uv) - 0.5;
    float gate = step(1.0 - star_density, hash21(cell * 1.37));
    float flicker = 0.5 + 0.5 * sin(TIME * (4.0 + star_shimmer * hash21(cell + 7.2)) + dot(cell, vec2(0.7, 1.3)));
    float star = gate * exp(-18.0 * dot(fract_uv, fract_uv)) * flicker * (0.3 + 2.2 * treble * drive);
    vec3 star_col = vec3(0.6, 0.75, 1.2) * star;

    vec3 mix_col = mix(bg, col, clamp(petals + glow, 0.0, 1.0));
    mix_col += star_col;
    mix_col = pow(max(mix_col, vec3(0.0)), vec3(0.92));

    COLOR = vec4(clamp(mix_col, 0.0, 1.0), 1.0);
}