shader_type canvas_item;
render_mode unshaded, blend_mix;

/* === pipeline uniforms (match your setup) === */
uniform sampler2D spectrum_tex;
uniform vec2      buffer_a_size = vec2(1920.0, 1080.0);

/* audio shaping */
uniform float audio_gamma = 2.0;
uniform float audio_gain  = 4.0;
uniform float audio_floor = 0.02;

/* look controls */
uniform int   sector_count    = 8;             // kaleido slices
uniform int   radial_layers   = 24;            // number of radial bands
uniform float radial_blur     : hint_range(0.0, 0.1) = 0.03;
uniform float sector_softness : hint_range(0.0, 1.0)  = 0.35;
uniform float base_brightness : hint_range(0.0, 2.0)  = 0.9;
uniform float glow_strength   : hint_range(0.0, 2.0)  = 1.1;
uniform float spin_speed      : hint_range(-2.0, 2.0) = 0.25;

//const float PI  = 3.14159265;
//const float TAU = 6.28318530;

/* === helpers === */
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 x)  { return clamp(x, vec3(0.0), vec3(1.0)); }

/* simple HSV-ish palette */
vec3 palette(float h, float v) {
    h = fract(h);
    float r = saturate(abs(h * 6.0 - 3.0) - 1.0);
    float g = saturate(2.0 - abs(h * 6.0 - 2.0));
    float b = saturate(2.0 - abs(h * 6.0 - 4.0));
    vec3 rgb = vec3(r, g, b);
    return rgb * v;
}

float sample_spectrum(float u) {
    float s = texture(spectrum_tex, vec2(saturate(u), 0.0)).r;
    s = max(audio_floor, s);
    s = pow(s, audio_gamma);
    return s * audio_gain;
}

/* fold an angle into a single sector around 0 */
float fold_sector(float angle, float sector_size) {
    float half = sector_size * 0.5;
    float a = mod(angle + half, sector_size) - half;
    return abs(a) / half; // 0 at center, 1 at sector edge
}

void fragment() {
    vec2 res = buffer_a_size;
    if (res.x <= 0.0 || res.y <= 0.0) {
        res = vec2(1.0, 1.0);
    }

    vec2 frag = UV * res;
    vec2 uv   = frag / res;

    // normalized center coords
    float aspect = res.x / res.y;
    vec2 p = uv - 0.5;
    p.x *= aspect;

    float r     = length(p);       // 0 at center
    float angle = atan(p.y, p.x);  // -PI..PI

    // spin the whole thing slowly
    angle += TIME * spin_speed;

    // kaleido folding
    float sector_size = TAU / float(sector_count);
    float sector_pos  = fold_sector(angle, sector_size); // 0 center, 1 edge

    // radial index for spectrum mapping
    float rad_idx = r * float(radial_layers);
    float band    = floor(rad_idx);
    float band_f  = fract(rad_idx);

    // two spectrum samples for radial blur
    float u0 = band / float(radial_layers);
    float u1 = (band + 1.0) / float(radial_layers);

    float s0 = sample_spectrum(u0);
    float s1 = sample_spectrum(u1);
    float spec = mix(s0, s1, band_f);

    // normalize spec to 0..1-ish visual value
    float spec_vis = saturate(spec * 0.25);

    // core “bar” shape in each sector
    float bar = 1.0 - saturate(sector_pos / max(sector_softness, 0.001));

    // fade with radius so edges don’t dominate
    float radial_falloff = saturate(1.0 - r * 1.2);

    // core energy
    float energy = spec_vis * bar * radial_falloff;

    // add a soft glow
    float glow = spec_vis * exp(-r * 5.0);
    energy += glow * glow_strength;

    // color: hue from band index + sector, value from energy
    float hue = fract(u0 + float(sector_count) * 0.05 + TIME * 0.03);
    float value = base_brightness * (0.3 + energy * 1.4);

    vec3 col = palette(hue, value);

    // emphasize bright parts and clamp
    col = saturate(col);

    COLOR = vec4(col, 1.0);
}
