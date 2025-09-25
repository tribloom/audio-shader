shader_type canvas_item;

/* Aurora Kaleidoscope PLUS (onset-driven pulses)
   Inputs: spectrum_tex (1xN R=current, G=peak), bar_count, aspect,
           kick_in (smoothed), kick_env (0..1), ring_age (0..1)
*/

uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float aspect = 1.7777;

/* Look / Motion */
uniform int   symmetry = 6;
uniform float warp_amt = 0.22;
uniform float swirl_amt = 0.7;
uniform float noise_scale = 1.8;
uniform float motion_speed = 0.35;
uniform float ripple_gain = 0.45;
uniform float brightness = 1.1;
uniform float gamma = 0.95;

/* Vignette based on normalized radius (fixed) */
uniform float edge_fade = 0.72;   // 0.5..1.3

/* External onset signals from GDScript */
uniform float kick_in  = 0.0;     // smoothed bass (optional)
uniform float kick_env = 0.0;     // 0..1, spikes on kick then decays
uniform float ring_age = 1.0;     // 0..1, resets to 0 on kick

/* Ring controls (more visible defaults) */
uniform float ring_near  = 0.08;  // start radius (0..1)
uniform float ring_far   = 0.98;  // end radius   (0..1)
uniform float ring_width = 0.10;  // gaussian width in normalized radius
uniform float ring_gain  = 1.10;  // brightness of the ring

/* Palette */
uniform bool  use_palette = true;
uniform vec3  pal_a = vec3(0.03, 0.05, 0.10);
uniform vec3  pal_b = vec3(0.20, 0.70, 1.00);
uniform vec3  pal_c = vec3(1.00, 0.95, 0.55);
uniform float pal_mid_pos = 0.55;
uniform float palette_bias = 0.12;

/* -------- helpers -------- */
float hash21(vec2 p){
    p = fract(p*vec2(234.34, 435.345));
    p += dot(p, p+34.45);
    return fract(p.x*p.y);
}
float noise2(vec2 p){
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    vec2 u = f*f*(3.0-2.0*f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p){
    float v = 0.0;
    float a = 0.5;
    mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)); // Godot 4 columns
    for (int i = 0; i < 5; i++){
        v += a * noise2(p);
        p = m * p;
        a *= 0.5;
    }
    return v;
}
mat2 rot2(float ang){
    float c = cos(ang), s = sin(ang);
    return mat2(vec2(c, s), vec2(-s, c)); // columns
}
float sample_mag(float u){
    float fb = float(bar_count);
    float idx = clamp(u, 0.0, 1.0) * max(1.0, fb - 1.0);
    float i0 = floor(idx);
    float t  = fract(idx);
    float tx0 = (i0 + 0.5) / fb;
    float tx1 = (min(i0 + 1.0, fb - 1.0) + 0.5) / fb;
    float h0 = texture(spectrum_tex, vec2(tx0, 0.5)).r;
    float h1 = texture(spectrum_tex, vec2(tx1, 0.5)).r;
    return mix(h0, h1, t);
}
vec3 palette3(float t){
    t = clamp(t, 0.0, 1.0);
    float pm = clamp(pal_mid_pos, 0.0001, 0.9999);
    return (t < pm) ? mix(pal_a, pal_b, smoothstep(0.0, pm, t))
                    : mix(pal_b, pal_c, smoothstep(pm, 1.0, t));
}
vec3 hsv2rgb(vec3 c){
    vec4 K = vec4(1., 2./3., 1./3., 3.);
    vec3 p = abs(fract(c.xxx + K.xyz)*6. - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0., 1.), c.y);
}

/* -------- fragment -------- */
void fragment(){
    // Centered UV, aspect-corrected space for noise/swirl
    vec2 uv0 = UV - 0.5;
    vec2 p_aspect = uv0 * vec2(aspect, 1.0);

    // Normalized radius for vignette and ring:
    // scale so that r_norm ~= 1 at the farthest visible corner
    float r_scale = length(vec2(aspect * 0.5, 0.5));
    float r_norm = length(p_aspect) / max(1e-6, r_scale);

    // Band summaries for motion/colour
    float bass  = sample_mag(0.08);
    float mid   = sample_mag(0.45);
    float high  = sample_mag(0.85);
    float level_est = clamp((bass + mid + high) / 3.0 * 1.25, 0.0, 1.0);

    // Kaleidoscope fold in angle space, keep original radius for features
    float a = atan(p_aspect.y, p_aspect.x);
    float seg = 6.28318530718 / float(max(symmetry, 1));
    a = abs(mod(a, seg) - seg*0.5);
    vec2 p = vec2(cos(a), sin(a)) * length(p_aspect);

    // Music-driven swirl
    float swirl = swirl_amt * (0.3 + 1.2*mid);
    p = rot2(TIME * (0.6 + 1.4*length(p)) * swirl) * p;

    // Domain warp
    float t = TIME * (motion_speed * (0.7 + 0.8*mid));
    vec2 w = vec2(
        fbm(p * (noise_scale*1.1) + vec2(0.0, t * (0.6 + high))),
        fbm(p * (noise_scale*0.9) + vec2(t * (0.4 + mid), 0.0))
    );
    p += (w - 0.5) * (warp_amt * (0.6 + 1.2*level_est));

    // Base nebula + harmonic ripples
    float base = fbm(p * noise_scale);
    // Use normalized radius so ripples scale similarly across aspects
    float r = length(p) / max(1e-6, r_scale);
    float rip =
        0.42 * sin(r*(38.0 + 56.0*bass) - TIME*(2.3 + 2.0*bass)) +
        0.30 * sin(r*(72.0 + 48.0*mid ) - TIME*(1.8 + 1.6*mid )) +
        0.22 * sin(r*(108. + 38.0*high) - TIME*(1.4 + 1.4*high));
    float field = base + ripple_gain * rip;

    // Vignette with normalized radius
    float vign = 1.0 - smoothstep(edge_fade, 1.28, r_norm);

    // Intensity curve
    float lum = pow(clamp(field * brightness * vign, 0.0, 1.0), gamma);

    // Palette
    float t_col = clamp(palette_bias + 0.55*lum + 0.25*high - 0.15*bass, 0.0, 1.0);
    vec3 base_rgb = use_palette ? palette3(t_col)
                                : hsv2rgb(vec3(clamp(0.65 - 0.20*high + 0.08*bass, 0.0, 1.0), 0.85, 1.0));
    vec3 col = base_rgb * lum;

    /* Onset-driven bloom and ring (now using normalized radius) */
    col = mix(col, vec3(1.0), 0.60 * clamp(kick_env, 0.0, 1.0));

    float rr = mix(ring_near, ring_far, clamp(ring_age, 0.0, 1.0));
    float rw = max(0.02, ring_width);
    float ring = exp(-pow((r_norm - rr) / rw, 2.0));
    col += vec3(ring) * (ring_gain * clamp(kick_env, 0.0, 1.0));

    COLOR = vec4(col, 1.0);
}
