shader_type canvas_item;
render_mode unshaded;

/* Visualizer wiring */
uniform float aspect = 1.7777;
uniform sampler2D spectrum_tex;
uniform int   bar_count = 64;

/* Master toggles */
uniform bool  audio_enabled = true;
uniform float audio_mix     = 0.6;   // overall influence

/* Beat inputs (either can be driven from your Visualizer) */
uniform float kick_env = 0.0;        // onset envelope (preferred)
uniform float level_in = 0.0;        // wideband level (fallback)

/* Center flash controls */
uniform float flash_gain   = 1.10;   // brightness boost for the core
uniform float flash_exp    = 1.7;    // dynamics softening (↑ = calmer)
uniform float center_focus = 12.0;   // how tightly the flash sticks to the portal
uniform float accent_mix   = 0.04;   // subtle scene tint (set 0 to disable)

/* Optional motion nudge */
uniform float time_mul   = 3.0;
uniform float speed_audio = 0.0;

/* Band windows across spectrum texture (0..1) */
uniform vec2 band_bass   = vec2(0.00, 0.22);
uniform vec2 band_mid    = vec2(0.22, 0.60);
uniform vec2 band_treble = vec2(0.60, 1.00);
uniform float band_gamma = 0.90;

/* Colors per band */
uniform vec3 bass_color = vec3(1.00, 0.25, 0.25);
uniform vec3 mid_color  = vec3(1.00, 0.85, 0.20);
uniform vec3 treb_color = vec3(0.70, 0.40, 1.00);

/* Debug: show the center mask if >0 (helps confirm data path) */
uniform float debug_center = 0.0;


vec2 rot2(vec2 v, float a){ float c=cos(a), s=sin(a); return vec2(c*v.x - s*v.y, s*v.x + c*v.y); }
float hash1(float x){ return fract(sin(x*12.9898) * 13758.5453); }
const vec4 hsv2rgb_K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
vec3 hsv2rgb(vec3 c){ vec3 p = abs(fract(c.xxx + hsv2rgb_K.xyz) * 6.0 - hsv2rgb_K.www);
                      return c.z * mix(hsv2rgb_K.xxx, clamp(p - hsv2rgb_K.xxx, 0.0, 1.0), c.y); }

vec2 mod1v(float p, float size){
    float halfsize = size * 0.5;
    float c = floor((p + halfsize) / size);
    float p2 = mod(p + halfsize, size) - halfsize;
    return vec2(p2, c);
}

vec2 rayCylinder(vec3 ro, vec3 rd, vec3 cb, vec3 ca, float cr){
    vec3  oc = ro - cb;
    float card = dot(ca,rd);
    float caoc = dot(ca,oc);
    float a = 1.0 - card*card;
    float b = dot( oc, rd) - caoc*card;
    float c = dot( oc, oc) - caoc*caoc - cr*cr;
    float h = b*b - a*c;
    if (h < 0.0) return vec2(-1.0);
    h = sqrt(h);
    return vec2(-b - h, -b + h) / a;
}

/* soft sky blue field from original */
vec3 skyColor(vec3 ro, vec3 rd){
    vec3 g0 = hsv2rgb(vec3(0.55, 0.9, 0.035*0.5));
    vec3 g1 = hsv2rgb(vec3(0.75, 0.85, 0.035*2.0));
    vec2 pp = rd.xy;
    float mixv = 0.35;
    return mix(g0, g1, mixv) / max(dot(pp, pp), 0.0001);
}

vec3 aces_approx(vec3 v){
    v = max(v, 0.0);
    v *= 0.6;
    float a=2.51, b=0.03, c=2.43, d=0.59, e=0.14;
    return clamp((v*(a*v+b)) / (v*(c*v+d)+e), 0.0, 1.0);
}

/* -------- spectrum helpers -------- */
float band_avg(vec2 nr){
    int i0 = int(floor(nr.x * float(bar_count)));
    int i1 = int(ceil (nr.y * float(bar_count)));
    i0 = clamp(i0, 0, bar_count-1);
    i1 = clamp(i1, i0+1, bar_count);
    float sum = 0.0; int cnt = 0;
    int span = i1 - i0;
    for (int k=0; k<128; k++){
        if (k >= span) break;
        int idx = i0 + k;
        float x = (float(idx) + 0.5) / float(bar_count);
        sum += texture(spectrum_tex, vec2(x, 0.5)).r;
        cnt++;
    }
    float v = (cnt>0) ? (sum/float(cnt)) : 0.0;
    return pow(clamp(v, 0.0, 1.0), band_gamma);
}
vec4 get_bands(){
    float b = band_avg(band_bass);
    float m = band_avg(band_mid);
    float t = band_avg(band_treble);
    return vec4(b, m, t, max(max(b,m), t));
}

/* -------- tunnel color (original look) -------- */
vec3 tunnel_color(vec3 ww, vec3 uu, vec3 vv, vec3 ro, vec2 p){
    const float rdd = 2.0;
    const float mm  = 5.0;
    const float rep = 16.0;

    vec3 rd = normalize(-p.x*uu + p.y*vv + rdd*ww);
    vec3 skyCol = skyColor(ro, rd);

    vec2 etc = rayCylinder(ro, rd, ro, vec3(0.0, 0.0, 1.0), 1.0);
    vec3 etcp = ro + rd*etc.y;

    vec2 yx = rot2(rd.yx, 0.3*etcp.z);
    rd.y = yx.x; rd.x = yx.y;

    vec3 col = skyCol;

    float a = atan(rd.y, rd.x);
    for (float i = 0.0; i < mm; i += 1.0){
        float ma = a;
        float sz = rep + i*9.0;
        float slices = TAU / sz;

        vec2 r_ma = mod1v(ma, slices);
        float na = r_ma.y;

        float h1 = hash1(na + 13.0*i + 123.4);
        float h2 = fract(h1 * 3677.0);
        float h3 = fract(h1 * 8677.0);

        float tr = mix(0.5, 3.0, h1);
        vec2 tc = rayCylinder(ro, rd, ro, vec3(0.0, 0.0, 1.0), tr);
        vec3 tcp = ro + tc.y * rd;

        vec2 tcp2 = vec2(tcp.z, a);

        float zz = mix(0.025, 0.05, sqrt(h1)) * rep / sz;

        vec2 r_py = mod1v(tcp2.y, slices);
        tcp2.y = r_py.x;

        float fo = smoothstep(0.5*slices, 0.25*slices, abs(tcp2.y));
        tcp2.x += h2 * TIME;
        tcp2.y *= tr * (PI/3.0);
        vec2 tcp3 = tcp2;

        float w = mix(0.2, 1.0, h2);
        vec2 r_px = mod1v(tcp3.x, w);
        tcp3.x = r_px.x;

        float h4 = hash1(r_px.y + 123.4);

        tcp2 /= zz;
        tcp3 /= zz;

        float d1 = abs(tcp2.y);
        float d2 = length(tcp3) - 2.0*h4;
        d2 = abs(d2) - 1.0*h4;
        d2 = abs(d2) - 0.5*h4;

        float d = mix(d1, d2, 0.5 + 0.5*sin(0.01 * tcp2.x));
        d *= zz;

        vec3 bcol = (1.0 + cos(vec3(0.0, 1.0, 2.0) + TAU*h3 + 0.5*h2*h2*tcp.z)) * 0.00005;
        bcol /= max(d*d, 0.00001 + 5e-7 * tc.y * tc.y);
        bcol *= exp(-0.04 * tc.y * tc.y);
        bcol *= smoothstep(-0.5, 1.0, sin(mix(0.125, 1.0, h2) * tcp.z));
        bcol *= fo;

        col += bcol;
    }

    return col;
}

/* -------- center tint BEFORE tone mapping -------- */
vec3 apply_center_tint(vec3 col, vec3 rd, vec3 ww, vec4 bands, float drive){
    // center mask: how parallel this pixel ray is to the forward vector
     float align = max(dot(rd, ww), 0.0);

    // pick dominant band color (boosted weights favour the "winning" band)
    vec3 band_energy = max(bands.xyz, vec3(0.0));
    float max_band = max(max(band_energy.x, band_energy.y), band_energy.z);
    vec3 band_weight = vec3(0.0);
    if (max_band > 0.0){
        band_weight = pow(band_energy / max_band, vec3(4.0));
    }

    float w_sum = band_weight.x + band_weight.y + band_weight.z;
    vec3 band_col;
    if (w_sum > 0.0){
        band_col = (band_weight.x * bass_color
                 + band_weight.y * mid_color
                 + band_weight.z * treb_color) / w_sum;
    } else {
        band_col = bass_color;
    }

    // flash amount from beat/level
    float k = max(kick_env, level_in);
    float flash = flash_gain * pow(k, flash_exp) * drive;

    // Wider bursts for stronger hits (smaller exponent -> larger mask)
    float flash_norm = clamp(flash, 0.0, 1.5);
    float focus_min = max(center_focus * 0.25, 1.0);
    float focus_dynamic = mix(center_focus, focus_min, clamp(flash_norm, 0.0, 1.0));
    float center_mask = pow(align, focus_dynamic);
    float halo_mask = pow(align, max(focus_dynamic * 0.5, 1.0));
	
    // *** IMPORTANT: mix BEFORE tonemapping so it actually tints the near-white core ***
        float amt = center_mask * (0.5 + flash_norm);
    col = mix(col, band_col, clamp(amt, 0.0, 1.0));

    // Kick a bright, colourised bloom in the centre. Strong hits spill wider.
    float flash_add = flash * flash;
    col += band_col * (center_mask * flash_add * 1.2);
    col += band_col * (halo_mask   * flash_add * 0.8);

    // slight global breathing
    col = mix(col, col + 0.25 * band_col, accent_mix * drive);

    // optional debug overlay to verify center mask is where you expect
    if (debug_center > 0.0){
        col = mix(col, vec3(0.0, 1.0, 0.6), clamp(center_mask * debug_center, 0.0, 1.0));
    }

    return col;
}

void fragment() {
    vec2 q = UV;
    vec2 p = -1.0 + 2.0*q;
    vec2 pp = p;
    p.x *= aspect;

    // camera basis (same as you have)
    float tm = TIME * time_mul;
    vec3 ro  = vec3(0.0, 0.0, tm);
    vec3 dro = normalize(vec3(1.0, 0.0, 3.0));
    vec2 r_xz = rot2(dro.xz, 0.2 * sin(0.05 * tm));            dro.x=r_xz.x; dro.z=r_xz.y;
    vec2 r_yz = rot2(dro.yz, 0.2 * sin(0.05 * tm*sqrt(0.5)));  dro.y=r_yz.x; dro.z=r_yz.y;
    const vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 ww = normalize(dro);
    vec3 uu = normalize(cross(up, ww));
    vec3 vv = cross(ww, uu);

    // THIS pixel’s ray (for core lock)
    const float rdd = 2.0;
    vec3 rd_for_mask = normalize(-p.x*uu + p.y*vv + rdd*ww);

    // render your tunnel
    vec3 col = tunnel_color(ww, uu, vv, ro, p);

    // --- ALWAYS-ON center-mask preview (no audio gating) ---
    if (debug_center > 0.0) {
        float cm = pow(max(dot(rd_for_mask, ww), 0.0), center_focus);
        col = mix(col, vec3(0.0, 1.0, 0.6), clamp(cm * debug_center, 0.0, 1.0));
    }

    // --- Audio-driven center tint (only if enabled) ---
    float drive = (audio_enabled ? clamp(audio_mix, 0.0, 1.0) : 0.0);
    if (drive > 0.0) {
        vec4 bands = get_bands();
        col = apply_center_tint(col, rd_for_mask, ww, bands, drive);
    }

    // tone + gamma last
    col -= 0.125 * vec3(0.0, 1.0, 2.0).yzx * length(pp);
    col = aces_approx(col);
    col = sqrt(col);
    COLOR = vec4(col, 1.0);
}
