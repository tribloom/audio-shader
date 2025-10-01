shader_type canvas_item;
render_mode unshaded;

/* ==== Audio ==== */
uniform bool       audio_enabled = true;
uniform sampler2D  spectrum_tex;      // 1 x bar_count, R=magnitude
uniform int        bar_count     = 64;
uniform float      audio_gain    = 1.2;

/* ==== Mapping / shaping ==== */
uniform bool  flip_spectrum   = false; // set true if order arrives reversed
uniform float mag_threshold   = 0.02;  // noise gate
uniform float mag_gamma       = 0.65;  // magnitude -> height curve
uniform float flutter_speed   = 6.0;   // tiny shimmer for sustained notes

/* ==== Layout (bars grow UP from bottom) ==== */
uniform float margin_left   = 0.06;
uniform float margin_right  = 0.94;
uniform float bars_bottom   = 0.08;
uniform float bars_top      = 0.90;   // absolute max height line
uniform float bar_gap       = 0.14;   // fraction of cell width as gap (0..0.8)
uniform float bar_round     = 0.45;   // 0..0.5 rounded cap (relative to half-width)
uniform float bar_min_h     = 0.012;  // minimum visible height (0..1)

/* ==== Style ==== */
uniform float color_pulse_amount = 1.0;  // 0=white, 1=rainbow at peaks
uniform float cap_gloss          = 0.55; // brightens near the top of each bar
uniform float glow_strength      = 0.80; // neon bleed around bars

/* Under-wave (smoothed spectrum area) */
uniform float wave_mix        = 0.28;    // 0 disables the wave
uniform float wave_smoothness = 2.5;     // higher = smoother wave
uniform float wave_alpha      = 0.35;    // opacity of the fill

/* Background (subtle) */
uniform vec3  bg_dark        = vec3(0.016);
uniform float vignette_pow   = 0.9;

/* Debug (no early returns) */
uniform bool  debug_view     = false;

/* ---------- helpers ---------- */
vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.xxx + vec3(0., 2./3., 1./3.)) * 6. - 3.);
    return c.z * mix(vec3(1.), clamp(p - 1., 0., 1.), c.y);
}
vec3 rainbow(float t){ return hsv2rgb(vec3(mix(0.0, 0.85, clamp(t,0.0,1.0)), 0.95, 1.0)); }

float bar_at_index(int i){
    if (bar_count <= 0) return 0.0;
    i = clamp(i, 0, bar_count - 1);
    float u = (float(i) + 0.5) / float(bar_count);
    return texture(spectrum_tex, vec2(u, 0.5)).r;
}

/* neighbor-smoothed sampling with intra-cell lerp */
float sample_mag(float fidx){
    float cells = float(max(bar_count, 1));
    float base  = floor(fidx);
    float t     = fract(fidx);

    int i0 = int(base);
    int i1 = int(mod(base + 1.0, cells));
    if (flip_spectrum){
        i0 = bar_count - 1 - i0;
        i1 = bar_count - 1 - i1;
    }

    float m0 = 0.2 * bar_at_index(max(i0-1,0)) + 0.6 * bar_at_index(i0) + 0.2 * bar_at_index(min(i0+1,bar_count-1));
    float m1 = 0.2 * bar_at_index(max(i1-1,0)) + 0.6 * bar_at_index(i1) + 0.2 * bar_at_index(min(i1+1,bar_count-1));
    return mix(m0, m1, t);
}

/* SDF rounded rectangle centered at origin */
float sdRoundRect(vec2 p, vec2 b, float r){
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

/* Smoothed spectrum for the under-wave */
float wave_mag_at(float x01){
    float cells = float(max(bar_count, 1));
    float fidx  = x01 * cells;
    // sample a few taps around x with Gaussian-ish weights
    float sum = 0.0, wsum = 0.0;
    float sigma = max(0.5, wave_smoothness);
    for (int k=-3; k<=3; k++){
        float o = float(k);
        float w = exp(-0.5 * (o*o) / (sigma*sigma));
        sum  += w * sample_mag(fidx + o);
        wsum += w;
    }
    return sum / max(wsum, 1e-5);
}

void fragment(){
    vec2 RES  = 1.0 / SCREEN_PIXEL_SIZE;
    vec2 uv01 = FRAGCOORD.xy / RES;

    /* --- background (dark with vignette) --- */
    vec2 g = (uv01 - 0.5) * vec2(RES.x/RES.y, 1.0);
    float vign = pow(smoothstep(1.05, 0.15, length(g)), vignette_pow);
    vec3 col = bg_dark * vign;

    /* --- geometry extents --- */
    float left  = margin_left;
    float right = margin_right;
    float usable_w = max(0.001, right - left);
    float bottom = bars_bottom;
    float top    = bars_top;
    float full_h = max(0.0, top - bottom);

    /* --- x mapping into bar grid --- */
    float x_in = (uv01.x - left) / usable_w;
    float inside_x = step(0.0, x_in) * step(x_in, 1.0);
    float cells = float(max(bar_count, 1));
    float fidx  = clamp(x_in * cells, 0.0, cells - 1.0 + 1e-6);

    /* --- magnitudes --- */
    float mag  = sample_mag(fidx);
    float hit  = audio_enabled ? max(0.0, mag * audio_gain - mag_threshold) : 0.0;
    hit = pow(hit, mag_gamma);

    /* Bars are anchored at the BOTTOM and grow UP */
    float h_now = max(bar_min_h, full_h * hit);

    /* Per-bar position */
    float cell_w = usable_w / cells;
    float i_f    = floor(fidx);
    float cx     = left + (i_f + 0.5) * cell_w;
    float cy     = bottom + 0.5 * h_now;   // <-- bottom anchored

    /* Rounded-rect SDF for the bar */
    float bar_w  = cell_w * max(0.02, 1.0 - bar_gap);
    vec2  p      = uv01 - vec2(cx, cy);
    vec2  b      = vec2(0.5 * bar_w, 0.5 * h_now);
    float r      = min(b.x, bar_round * b.x);
    float sdf    = sdRoundRect(p, b, r);
    float aa     = max(1e-4, fwidth(sdf));
    float bar_m  = smoothstep(aa, -aa, sdf);   // 1 inside, 0 outside

    /* Per-bar hue (visual order, not flipped) */
    float denom = max(1.0, float(bar_count - 1));
    float hue_t = float(int(i_f)) / denom;
    vec3  hue   = rainbow(hue_t);

    /* Peak whitening + soft cap gloss */
    float phase   = (i_f + 0.37) * 11.13;
    float flutter = 0.5 + 0.5 * sin(TIME * flutter_speed + phase);
    float pulse   = clamp(hit * (1.0 + 0.25 * (flutter - 0.5) * 2.0), 0.0, 1.0);

    vec3 fill = mix(vec3(1.0), hue, clamp(color_pulse_amount * pulse, 0.0, 1.0));

    // gloss near the top of the bar (y within the bar body)
    float y_rel = clamp((uv01.y - (cy - b.y)) / max(1e-5, 2.0 * b.y), 0.0, 1.0);
    float gloss = smoothstep(0.55, 1.0, y_rel) * cap_gloss;
    fill = mix(fill, vec3(1.0), gloss * 0.45);

    /* Compose main bar */
    col = mix(col, fill, inside_x * bar_m);

    /* Soft neon glow */
    float glow = exp(-max(sdf, 0.0) / max(1e-5, 0.30 * b.x)) * glow_strength * pulse;
    col += hue * glow * inside_x;

    /* Under-wave (smoothed area under spectrum) */
    if (wave_mix > 0.001){
        float x01  = clamp(x_in, 0.0, 1.0);
        float wmag = pow(max(0.0, wave_mag_at(x01) * audio_gain - mag_threshold), mag_gamma);
        float y_w  = bottom + full_h * wmag;
        float wave_fill = smoothstep(0.0, 0.003, y_w - uv01.y); // 1 below the wave
        vec3  wcol = mix(vec3(1.0), rainbow(x01), 0.65) * wave_alpha;
        col = mix(col, wcol, inside_x * wave_fill * wave_mix);
    }

    /* Debug mini bars at bottom (no early return) */
    if (debug_view && bar_count > 0){
        float bar_h = 0.08;
        float in_bar = step(uv01.y, bar_h);
        int di = clamp(int(floor(uv01.x * float(bar_count))), 0, bar_count - 1);
        int sdi = flip_spectrum ? (bar_count - 1 - di) : di;
        float dv = clamp(bar_at_index(sdi) * audio_gain, 0.0, 1.0);
        float hgt = mix(0.0, bar_h, dv);
        float filled = step(uv01.y, hgt);
        vec3 dbg = mix(vec3(0.06), rainbow(float(di)/denom), filled);
        col = mix(col, dbg, in_bar);
    }

    /* gentle tonemap */
    col = sqrt(col);
    COLOR = vec4(col, 1.0);
}
