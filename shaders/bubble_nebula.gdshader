shader_type canvas_item;

/* ---------- Audio (optional) ---------- */
uniform bool use_audio = false;
uniform sampler2D spectrum_tex : hint_default_black;
uniform int   band_count   : hint_range(2, 32) = 12;
uniform float pulse_gain   : hint_range(0.0, 1.5) = 0.28;
uniform float pulse_bias   : hint_range(0.0, 1.0) = 0.06;
uniform float halo_gain    : hint_range(0.0, 2.0) = 0.9;
uniform float parallax_g   : hint_range(0.0, 1.0) = 0.25;
uniform float u_lo         : hint_range(0.0,1.0) = 0.18; // bass bin
uniform float u_hi         : hint_range(0.0,1.0) = 0.75; // highs bin

/* ---------- Look / behavior ---------- */
uniform float aspect    : hint_range(0.1, 4.0) = 1.7777;
uniform int   max_iter  : hint_range(4, 24)    = 12;
uniform float bg_sat    : hint_range(0.0, 1.0) = 0.85;
uniform float seam_kill : hint_range(0.0, 1.0) = 0.0;    // usually 0 now
uniform float tile_y_scale     : hint_range(1.0, 3.0) = 1.8;

/* --- Anti-clipping controls --- */
uniform float bubble_scale : hint_range(0.5, 1.0) = 0.86;   // global radius shrink
uniform float cell_pad     : hint_range(0.0, 0.45) = 0.14;  // fraction of half-tile kept empty
uniform float max_pulse    : hint_range(0.0, 2.0)  = 0.60;  // clamp audio growth
uniform float halo_pad_frac: hint_range(0.0, 0.4)  = 0.12;  // extra pad so glow doesn't hit edges
uniform float radius_margin_px : hint_range(0.0, 6.0) = 2.0; // small AA safety

/* ---------- utils ---------- */
const vec4 HSV_K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.xxx + HSV_K.xyz) * 6.0 - HSV_K.www);
    return c.z * mix(HSV_K.xxx, clamp(p - HSV_K.xxx, 0.0, 1.0), c.y);
}
float hash1(float x){ return fract(sin(x*12.9898) * 13758.5453); }
float hash2(vec2  x){ return fract(sin(dot(x, vec2(12.9898,58.233))) * 13758.5453); }
vec2 mod2(inout vec2 p, vec2 size){
    vec2 c = floor((p + size*0.5)/size);
    p = mod(p + size*0.5, size) - size*0.5;
    return c;
}
float tanh_approx(float x){ float x2=x*x; return clamp(x*(27.0+x2)/(27.0+9.0*x2), -1.0, 1.0); }

/* audio sampling */
float samp(float u){
    float du=0.006, a=0.0, w=0.0;
    for(int k=-2;k<=2;k++){
        float uk=clamp(u+du*float(k),0.0,1.0);
        a += texture(spectrum_tex, vec2(uk, 0.25)).r; w += 1.0;
    }
    return (w>0.0)? a/w : 0.0;
}
float band_from_cell(vec2 cell_id, float layer_idx){
    float h = hash1(dot(cell_id, vec2(1.37, 2.41)) + 31.0*layer_idx);
    if (band_count <= 1) return h;
    float bucket = floor(h * float(band_count));
    return (bucket + 0.5) / float(band_count);
}

/* one layer */
vec4 layer_plane(vec2 p, float i, float zf, float z, vec3 bgcol){
    float sz = 0.5 * zf;
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

    // base + audio pulse
    float r_base = sz * mix(0.10, 0.475, h0*h0) * bubble_scale;
    float pulse = 0.0;
    float lo = use_audio? samp(u_lo) : 0.2 + 0.1*sin(TIME*0.6);
    float hi = use_audio? samp(u_hi) : 0.2 + 0.2*sin(TIME*1.1);
    if (use_audio){
        float uband = band_from_cell(cell, i);
        float lvl   = samp(uband);
        pulse = pulse_bias + pulse_gain * lvl;
    } else {
        float uband = fract(h2 + 0.13*i);
        pulse = pulse_bias + 0.15 * sin(TIME*0.9 + TAU*uband);
    }
    pulse = clamp(pulse, 0.0, max_pulse);

    // --- predict static center offset & wobble amp (using a provisional radius)
    float r_guess = r_base * (1.0 + pulse);
    float amp_guess = mix(0.25, 0.5, h3) * r_guess;

    // static offset that keeps center away from edges (before wobble)
    float offx = 0.95*(sz - r_guess - amp_guess) * sign(h3-0.5) * h3;
    float offy = 0.475*(tile_size.y - 2.0*r_guess) * sign(h5-0.5) * h5;

    // audio parallax offset (applied later but include worst case)
    vec2 par = parallax_g * lo * zf * vec2(0.25, -0.15);

    // remaining space to edge in each axis (half-tile minus worst-case center offset)
    float hx = 0.5 * tile_size.x, hy = 0.5 * tile_size.y;
    float pad_frac = clamp(cell_pad, 0.0, 0.45);
    float halo_pad = halo_pad_frac * min(hx, hy);

    float space_x = hx * (1.0 - pad_frac) - (abs(offx) + amp_guess + abs(par.x));
    float space_y = hy * (1.0 - pad_frac) - (abs(offy) + amp_guess + abs(par.y));

    // AA safety in pixel space + halo pad in local space
    float r_max = max(0.0, min(space_x, space_y) - (radius_margin_px * pix) - halo_pad);

    // final safe radius and wobble
    float r = min(r_guess, r_max);
    float amp = mix(0.25, 0.5, h3) * r;

    // place bubble with wobble + static offset + parallax
    cp.x -= amp * sin(mix(3.0, 0.25, h0)*TIME + TAU*h2);
    cp += vec2(offx, offy);
    cp += par;

    float d = length(cp) - r;

    // color + halo
    vec3 hsv = vec3(h1, 0.75, 1.5);
    vec3 ocol = hsv2rgb(hsv);
    vec3 icol = hsv2rgb(hsv * vec3(1.0, 0.5, 1.25));
    vec3 col  = mix(icol, ocol, smoothstep(r, 0.0, -d)) * mix(0.8, 1.0, h0);

    float halo = exp(-6.0*max(d, 0.0)/max(r, 1e-4)) * (0.6 + 1.4*hi) * halo_gain;
    col += halo;
    col = mix(bgcol, col, fi);

    float t = smoothstep(aa, -aa, d);

    if (seam_kill > 0.0){
        vec2 edge = abs(cp) - 0.5*tile_size;
        float near_edge = max(abs(edge.x), abs(edge.y));
        float k = smoothstep(pix*1.5, pix*3.0, near_edge);
        t *= mix(1.0, k, seam_kill);
    }

    return vec4(col, t);
}

vec3 compose(vec2 p, vec2 pp){
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

        vec4 pc = layer_plane(sp, i, zf, z, bg);
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

    vec3 col = compose(p, pp);
    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
