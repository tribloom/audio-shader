shader_type canvas_item;

/*
Aurora Kaleidoscope (Godot 4 canvas_item)
- Input: 1xN spectrum texture (R=current, G=peak), same as your bars/line shaders.
- No script changes required if you assign this to a slot that already binds:
    spectrum_tex, bar_count, aspect
- Visual: domain-warped FBM + kaleidoscope + music-driven ripples & hue.
shader_type canvas_item;

/* ---- Optional audio: bind a 1×N (or N×1) spectrum and set use_audio=true ---- */
uniform bool use_audio = false;
uniform sampler2D spectrum_tex : hint_default_black;
uniform int   band_count  : hint_range(2, 32) = 12;   // how many spectrum bands to map cells to
uniform float pulse_gain  : hint_range(0.0, 1.5) = 0.25; // how much radius grows with audio
uniform float pulse_bias  : hint_range(0.0, 1.0) = 0.05; // minimum pulse so it’s never dead

/* ---- Look / behavior ---- */
uniform float aspect   : hint_range(0.1, 4.0) = 1.7777;
uniform int   max_iter : hint_range(4, 24)    = 12;   // layers (same as MaxIter)
uniform float bg_sat   : hint_range(0.0, 1.0) = 0.85; // background saturation
uniform float seam_kill: hint_range(0.0, 1.0) = 1.0;  // 1 = hide grid lines, 0 = keep

/* ---- constants ---- */
const float PI = 3.141592654;
const float TAU = 6.283185307;

/* === utilities === */
const vec4 HSV_K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.xxx + HSV_K.xyz) * 6.0 - HSV_K.www);
    return c.z * mix(HSV_K.xxx, clamp(p - HSV_K.xxx, 0.0, 1.0), c.y);
}

float hash1(float x){ return fract(sin(x*12.9898) * 13758.5453); }
float hash2(vec2  x){ return fract(sin(dot(x, vec2(12.9898,58.233))) * 13758.5453); }

/* mercury.sexy tiler: returns cell id, recenters p in cell */
vec2 mod2(inout vec2 p, vec2 size){
    vec2 c = floor((p + size*0.5)/size);
    p = mod(p + size*0.5, size) - size*0.5;
    return c;
}

float tanh_approx(float x){
    float x2 = x*x;
    return clamp(x*(27.0 + x2)/(27.0 + 9.0*x2), -1.0, 1.0);
}

/* --- spectrum helpers --- */
float spectrum_smooth(float u){
    // small 5-tap average; works for 1×N or N×1 textures
    float du = 0.006, acc = 0.0; float w=0.0;
    for(int k=-2;k<=2;k++){
        float uk = clamp(u + du*float(k), 0.0, 1.0);
        acc += texture(spectrum_tex, vec2(uk, 0.25)).r; w += 1.0;
    }
    return (w>0.0) ? acc/w : 0.0;
}

/* map a cell id to a band [0..1] deterministically */
float band_from_cell(vec2 cell_id, float layer_idx){
    // scramble per cell & per layer so neighbors don’t use same band
    float h = hash1(dot(cell_id, vec2(1.37, 2.41)) + 31.0*layer_idx);
    if (band_count <= 1) return h;
    float bucket = floor(h * float(band_count));
    return (bucket + 0.5) / float(band_count);
}

/* ---- one layer of bubbles (ported + audio pulse + seam fix) ---- */
vec4 plane(vec2 p, float i, float zf, float z, vec3 bgcol, float x01){
    float sz = 0.5 * zf;
    vec2 cp = p;

    vec2 cell = mod2(cp, vec2(2.0*sz, sz));

    float h0 = hash2(cell + i + 123.4);
    float h1 = fract(4483.0*h0);
    float h2 = fract(8677.0*h0);
    float h3 = fract(9677.0*h0);
    float h4 = fract(7877.0*h0);
    float h5 = fract(9967.0*h0);
    if (h4 < 0.5) return vec4(0.0);

    float fi = exp(-0.25 * max(z - 1.0, 0.0));
    float pix = max(fwidth(cp.x), fwidth(cp.y));
    float aa  = mix(6.0, 1.0, fi) * pix;

    // base radius
    float r   = sz * mix(0.1, 0.475, h0*h0);

    // ===== audio radius pulse (subtle) =====
    float pulse = 0.0;
    if (use_audio){
        float uband = band_from_cell(cell, i);          // per-cell band pick
        float lvl   = spectrum_smooth(uband);
        pulse = pulse_bias + pulse_gain * lvl;          // 0..(bias+gain)
    } else {
        // gentle fallback so it still breathes
        float uband = fract(h2 + 0.13*i);
        pulse = pulse_bias + 0.15 * sin(TIME*0.9 + TAU*uband);
    }
    r *= (1.0 + pulse);  // grow/shrink bubble with audio

    // wobble / offsets (original)
    float amp = mix(0.25, 0.5, h3) * r;
    cp.x -= amp * sin(mix(3.0, 0.25, h0)*TIME + TAU*h2);
    cp.x += 0.95*(sz - r - amp) * sign(h3-0.5) * h3;
    cp.y += 0.475*(sz - 2.0*r)  * sign(h5-0.5) * h5;

    float d = length(cp) - r;

    // rainbow colors (original), keep bright
    vec3 hsv = vec3(h1, 0.75, 1.5);
    vec3 ocol = hsv2rgb(hsv);
    vec3 icol = hsv2rgb(hsv * vec3(1.0, 0.5, 1.25));
    vec3 col  = mix(icol, ocol, smoothstep(r, 0.0, -d)) * mix(0.8, 1.0, h0);
    col = mix(bgcol, col, fi);

    // coverage (alpha)
    float t = smoothstep(aa, -aa, d);

    // ===== seam killer (hides the rectangular lines from mod2 tiling) =====
    if (seam_kill > 0.0){
        vec2 S = vec2(2.0*sz, sz);
        vec2 edge = abs(cp) - 0.5*S;              // 0 at cell borders
        float near_edge = max(abs(edge.x), abs(edge.y));
        float k = smoothstep(pix*1.5, pix*3.0, near_edge); // 0 near edge → 1 away
        t *= mix(1.0, k, seam_kill);
    }

    return vec4(col, t);
}

/* ---- main effect (ported) ---- */
vec3 effect(vec2 p, vec2 pp){
    vec3 bg0 = hsv2rgb(vec3(0.66, bg_sat, 0.10));
    vec3 bg1 = hsv2rgb(vec3(0.55, 0.66, 0.60));
    vec3 bg  = mix(bg1, bg0, tanh_approx(1.5*length(p)));
    vec3 col = bg;

    for (int ii=0; ii<24; ii++){
        if (ii >= max_iter) break;
        float i = float(ii);
        const float Near = 4.0;
        float z  = float(max_iter) - i;
        float zf = Near/(Near + float(max_iter) - i);

        vec2 sp = p;
        float h = hash1(i + 1234.5);
        sp.y += -mix(0.2, 0.3, h*h) * TIME * zf;
        sp += h;

        vec4 pc = plane(sp, i, zf, z, bg, UV.x);
        col = mix(col, pc.rgb, pc.a);
    }

    col *= smoothstep(1.4, 0.5, length(pp));
    col = sqrt(max(col, vec3(0.0)));
    return col;
}

void fragment(){
    vec2 q  = vec2(UV.x, 1.0 - UV.y);
    vec2 p  = -1.0 + 2.0*q;
    vec2 pp = p;
    p.x *= aspect;

    vec3 col = effect(p, pp);
    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}

Hookup (quickest): assign this shader to your material_line slot to test.
*/

uniform sampler2D spectrum_tex; // width=bar_count, height=1, R=current, G=peak
uniform int bar_count = 64;
uniform float aspect = 1.7777;

// Artistic controls
uniform int   symmetry = 6;         // kaleidoscope segments (3..12 looks good)
uniform float warp_amt = 0.22;      // domain warp strength
uniform float swirl_amt = 0.7;      // radial swirl amount
uniform float noise_scale = 1.8;    // FBM base frequency
uniform float motion_speed = 0.35;  // baseline motion speed
uniform float ripple_gain = 0.45;   // ring ripple strength
uniform float brightness = 1.1;     // overall gain
uniform float gamma = 0.95;         // visual shaping
uniform float edge_fade = 0.7;      // vignette radius (0.5..1.3)

// --- helpers ----------------------------------------------------------
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
    mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
    for (int i = 0; i < 5; i++){
        v += a * noise2(p);
        p = m * p;
        a *= 0.5;
    }
    return v;
}

mat2 rot2(float a){
    float c = cos(a), s = sin(a);
    return mat2(vec2(c, s), vec2(-s, c));
}

// Continuous spectrum sample at u in [0,1]
float sample_spec(float u){
    float fb = float(bar_count);
    float idx = clamp(u, 0.0, 1.0) * (fb - 1.0);
    float i0 = floor(idx);
    float t  = fract(idx);
    float tx0 = (i0 + 0.5) / fb;
    float tx1 = (min(i0 + 1.0, fb - 1.0) + 0.5) / fb;
    float h0 = texture(spectrum_tex, vec2(tx0, 0.5)).r;
    float h1 = texture(spectrum_tex, vec2(tx1, 0.5)).r;
    return mix(h0, h1, t);
}

// HSV -> RGB
vec3 hsv2rgb(vec3 c){
    vec4 K = vec4(1., 2./3., 1./3., 3.);
    vec3 p = abs(fract(c.xxx + K.xyz)*6. - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0., 1.), c.y);
}

// --- fragment ---------------------------------------------------------
void fragment(){
    // Normalized canvas UV centered at 0 with aspect correction
    vec2 uv0 = UV - 0.5;
    vec2 p = uv0 * vec2(aspect, 1.0);

    // Read quick band summaries from spectrum (low/mid/high)
    float bass = sample_spec(0.06);
    float mid  = sample_spec(0.35);
    float high = sample_spec(0.78);
    float level_est = clamp((bass + mid + high) / 3.0 * 1.25, 0.0, 1.0);

    // Polar coords
    float r = length(p) + 1e-5;
    float a = atan(p.y, p.x);

    // Kaleidoscope fold
    float seg = 6.28318530718 / float(max(symmetry, 1));
    a = abs(mod(a, seg) - seg*0.5);
    p = vec2(cos(a), sin(a)) * r;

    // Music-driven swirl (stronger outward, modulated by mids)
    float swirl = swirl_amt * (0.3 + 1.2*mid);
    p = rot2(swirl * TIME * (0.6 + 1.4*r)) * p;

    // Domain warping (two FBM fields pushed by highs/mids)
    float t = TIME * (motion_speed * (0.7 + 0.8*mid));
    vec2 w = vec2(
        fbm(p * (noise_scale*1.1) + vec2(0.0, t * (0.6 + high))),
        fbm(p * (noise_scale*0.9) + vec2(t * (0.4 + mid), 0.0))
    );
    p += (w - 0.5) * (warp_amt * (0.6 + 1.2*level_est));

    // Base nebula density
    float base = fbm(p * noise_scale);

    // Music-driven concentric ripples (bass/mid/high drive freq & speed)
    float rip =
        0.42 * sin(r*(42.0 + 60.0*bass) - TIME*(2.5 + 2.0*bass)) +
        0.30 * sin(r*(78.0 + 50.0*mid ) - TIME*(1.9 + 1.6*mid )) +
        0.22 * sin(r*(120. + 40.0*high) - TIME*(1.5 + 1.4*high));

    float field = base + ripple_gain * rip;

    // Edge fade / vignette
    float vign = 1.0 - smoothstep(edge_fade, 1.35, r);

    // Brightness shaping
    float lum = pow(clamp(field * brightness * vign, 0.0, 1.0), gamma);

    // Hue ties to tonal center (lean warmer with bass, cooler with highs)
    float hue = clamp(0.65 - 0.20*high + 0.08*bass, 0.0, 1.0);
    float sat = 0.85;
    vec3 rgb = hsv2rgb(vec3(hue, sat, 1.0));

    // Modulate color by intensity; add a soft glow feel
    // (Multiplying rgb by lum gives a “colored light” effect)
    rgb *= mix(0.25, 1.0, lum);
    vec3 col = rgb * lum;

    COLOR = vec4(col, 1.0);
}
