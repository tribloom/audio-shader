shader_type canvas_item;

/* ---- Optional audio: bind a 1×N (or N×1) spectrum and set use_audio=true ---- */
uniform bool use_audio = false;
uniform sampler2D spectrum_tex : hint_default_black;
uniform int   band_count  : hint_range(2, 32) = 12;     // spectrum bands mapped to cells
uniform float pulse_gain  : hint_range(0.0, 1.5) = 0.25;// radius growth with audio
uniform float pulse_bias  : hint_range(0.0, 1.0) = 0.05;// baseline pulse (never dead)
uniform float audio_hue_gain : hint_range(0.0,1.5) = 0.35; // optional gentle hue drift

/* ---- Look / behavior ---- */
uniform float aspect    : hint_range(0.1, 4.0) = 1.7777;
uniform int   max_iter  : hint_range(4, 24)    = 12;   // layers (like MaxIter)
uniform float bg_sat    : hint_range(0.0, 1.0) = 0.85;
uniform float seam_kill : hint_range(0.0, 1.0) = 1.0;

/* NEW: make Y cells taller so pulsing bubbles don’t hit the ceiling */
uniform float tile_y_scale     : hint_range(1.0, 3.0) = 1.8;  // 1.8–2.2 looks great
/* NEW: keep a tiny pixel-space margin inside the tile so edges never clip */
uniform float radius_margin_px : hint_range(0.0, 6.0) = 2.0;

//const float PI  = 3.141592654;
//const float TAU = 6.283185307;

/* === utilities === */
const vec4 HSV_K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.xxx + HSV_K.xyz) * 6.0 - HSV_K.www);
    return c.z * mix(HSV_K.xxx, clamp(p - HSV_K.xxx, 0.0, 1.0), c.y);
}
float hash1(float x){ return fract(sin(x*12.9898) * 13758.5453); }
float hash2(vec2  x){ return fract(sin(dot(x, vec2(12.9898,58.233))) * 13758.5453); }

/* mercury.sexy tiler */
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
    float du = 0.006, acc = 0.0; float w=0.0;
    for(int k=-2;k<=2;k++){
        float uk = clamp(u + du*float(k), 0.0, 1.0);
        acc += texture(spectrum_tex, vec2(uk, 0.25)).r; w += 1.0;
    }
    return (w>0.0) ? acc/w : 0.0;
}
float band_from_cell(vec2 cell_id, float layer_idx){
    float h = hash1(dot(cell_id, vec2(1.37, 2.41)) + 31.0*layer_idx);
    if (band_count <= 1) return h;
    float bucket = floor(h * float(band_count));
    return (bucket + 0.5) / float(band_count);
}

/* ---- one layer (fixed: larger tile in Y + radius cap) ---- */
vec4 plane(vec2 p, float i, float zf, float z, vec3 bgcol, float x01){
    float sz = 0.5 * zf;

    // use a taller cell in Y to give headroom for pulsing
    vec2 tile_size = vec2(2.0*sz, sz * tile_y_scale);

    vec2 cp = p;
    vec2 cell = mod2(cp, tile_size);

    float h0 = hash2(cell + i + 123.4);
    float h1 = fract(4483.0*h0);
    float h2 = fract(8677.0*h0);
    float h3 = fract(9677.0*h0);
    float h4 = fract(7877.0*h0);
    float h5 = fract(9967.0*h0);
    if (h4 < 0.5) return vec4(0.0);

    float fi  = exp(-0.25 * max(z - 1.0, 0.0));
    float pix = max(fwidth(cp.x), fwidth(cp.y));
    float aa  = mix(6.0, 1.0, fi) * pix;

    // base radius
    float r   = sz * mix(0.1, 0.475, h0*h0);

    // audio radius pulse (subtle)
    float pulse = 0.0;
    if (use_audio){
        float uband = band_from_cell(cell, i);
        float lvl   = spectrum_smooth(uband);
        pulse = pulse_bias + pulse_gain * lvl;
    } else {
        float uband = fract(h2 + 0.13*i);
        pulse = pulse_bias + 0.15 * sin(TIME*0.9 + TAU*uband);
    }
    r *= (1.0 + pulse);

    // HARD CAP: keep radius inside both half-extents minus a small margin
    float hx = 0.5 * tile_size.x;          // = sz
    float hy = 0.5 * tile_size.y;          // taller half-height
    float margin = radius_margin_px * pix; // pixel-space margin
    float r_cap  = max(0.0, min(hx - margin, hy - margin));
    r = min(r, r_cap);

    // wobble / offsets (Y offset uses the taller tile height now)
    float amp = mix(0.25, 0.5, h3) * r;
    cp.x -= amp * sin(mix(3.0, 0.25, h0)*TIME + TAU*h2);
    cp.x += 0.95*(sz - r - amp) * sign(h3-0.5) * h3;
    cp.y += 0.475*(tile_size.y - 2.0*r) * sign(h5-0.5) * h5;

    float d = length(cp) - r;

    // rainbow colors (+ optional gentle hue drift across screen X)
    vec3 hsv = vec3(h1, 0.75, 1.5);
    if (use_audio){
        hsv.x = fract(hsv.x + audio_hue_gain * (0.5 + 0.5*sin(6.28318*x01)));
    }
    vec3 ocol = hsv2rgb(hsv);
    vec3 icol = hsv2rgb(hsv * vec3(1.0, 0.5, 1.25));
    vec3 col  = mix(icol, ocol, smoothstep(r, 0.0, -d)) * mix(0.8, 1.0, h0);
    col = mix(bgcol, col, fi);

    float t = smoothstep(aa, -aa, d);

    // seam killer uses the same (larger) tile_size
    if (seam_kill > 0.0){
        vec2 edge = abs(cp) - 0.5*tile_size;        // 0 at cell borders
        float near_edge = max(abs(edge.x), abs(edge.y));
        float k = smoothstep(pix*1.5, pix*3.0, near_edge);
        t *= mix(1.0, k, seam_kill);
    }

    return vec4(col, t);
}

/* ---- main effect (ported) ---- */
vec3 effect(vec2 p, vec2 pp, float x01){
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

        vec4 pc = plane(sp, i, zf, z, bg, x01);
        col = mix(col, pc.rgb, pc.a);
    }

    col *= smoothstep(1.4, 0.5, length(pp));
    col = sqrt(max(col, vec3(0.0)));
    return col;
}

void fragment(){
    vec2 q  = vec2(UV.x, 1.0 - UV.y);
    float x01 = clamp(q.x, 0.0, 1.0);
    vec2 p  = -1.0 + 2.0*q;
    vec2 pp = p;
    p.x *= aspect;

    vec3 col = effect(p, pp, x01);
    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
