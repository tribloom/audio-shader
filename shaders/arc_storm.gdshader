shader_type canvas_item;
render_mode unshaded, blend_mix;

/* wired by your Visualizer already */
uniform float aspect = 1.7777;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;

/* look tuning */
uniform int   arc_count = 5;           // 3–6 looks best (max 8)
const  int    ARC_MAX   = 8;
uniform float speed     = 0.60;        // baseline speed when audio OFF
uniform float curvature = 0.32;
uniform float warp_amp  = 0.20;
uniform float warp_freq = 2.20;
uniform float width_base= 95.0;
uniform float glow      = 1.25;
uniform float gamma_fix = 0.90;
uniform vec3  base_tint = vec3(0.25,0.55,1.30);

/* === audio toggle + speed when ON === */
uniform bool  audio_enabled = true;
uniform float speed_audio_mul   = 1.35;  // constant boost when audio is ON
uniform float speed_level_drive = 0.20;  // extra % from wideband level (0..1)
uniform float speed_min = 0.05;
uniform float speed_max = 3.0;

/* === band ranges (cutoffs) and gains (balance bass-heavy trance) ===
     u ∈ [0..1] across your spectrum texture (low→high) */
uniform vec2 band_bass   = vec2(0.00, 0.18);
uniform vec2 band_mid    = vec2(0.18, 0.55);
uniform vec2 band_treble = vec2(0.55, 1.00);
uniform float gain_bass = 0.85;
uniform float gain_mid  = 1.20;
uniform float gain_treble = 1.75;
uniform float band_gamma = 0.85;        // compress/flatten band dynamics (lower = more even)

/* === highlight controls === */
uniform bool  highlight_all   = true;   // false = highlight one arc; true = per-band arcs
uniform float highlight_thresh = 0.42;  // sensitivity for band “hit”
uniform float highlight_blend  = 0.85;  // 0..1 mix toward band color
uniform float highlight_boost  = 0.35;  // brightness bump on hit
uniform vec3  bass_color   = vec3(1.00, 0.22, 0.15); // red
uniform vec3  mid_color    = vec3(1.00, 0.92, 0.22); // yellow
uniform vec3  treble_color = vec3(0.72, 0.46, 1.00); // violet

/* ---------- 2D simplex noise (Gustavson) ---------- */
vec3 mod289(vec3 x){ return x - floor(x*(1.0/289.0))*289.0; }
vec2 mod289(vec2 x){ return x - floor(x*(1.0/289.0))*289.0; }
vec3 permute(vec3 x){ return mod289((x*34.0+1.0)*x); }
float snoise(vec2 v){
    const vec4 C = vec4(0.211324865,0.366025404,-0.577350269,0.024390244);
    vec2 i = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0,0.0) : vec2(0.0,1.0);
    vec4 x12 = x0.xyxy + C.xxzz; x12.xy -= i1;
    i = mod289(i);
    vec3 p = permute(permute(i.y + vec3(0.0,i1.y,1.0)) + i.x + vec3(0.0,i1.x,1.0));
    vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
    m = m*m; m = m*m;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    vec3 g;
    g.x = a0.x*x0.x + h.x*x0.y;
    g.y = a0.y*x12.x + h.y*x12.y;
    g.z = a0.z*x12.z + h.z*x12.w;
    return 130.0 * dot(m, g);
}

/* spectrum helpers */
float spec_at(float u){ return texture(spectrum_tex, vec2(clamp(u,0.0,1.0), 0.5)).r; }
float spec_avg(float u0, float u1){
    float a=0.0; const int TAPS=4;
    for(int k=0;k<TAPS;k++){ float t=float(k)/float(max(TAPS-1,1)); a+=spec_at(mix(u0,u1,t)); }
    return a/float(TAPS);
}
float band_energy(vec2 range, float gain){
    float e = spec_avg(range.x, range.y) * gain;
    e = clamp(e, 0.0, 1.0);
    // compress dominance a bit so treble can compete
    return pow(e, band_gamma);
}

/* map arc index to spectrum u */
float arc_u(int j, int total){
    return pow((float(j) - 0.5) / float(total), 0.9);
}

/* which band does u belong to? 0=bass,1=mid,2=treble */
int band_id_for_u(float u){
    if (u < band_mid.x) return 0;
    if (u < band_treble.x) return 1;
    return 2;
}

void fragment(){
    vec2 uv = UV*2.0 - 1.0;
    uv.y *= 1.0 / max(aspect, 1e-6);

    float audio_on = audio_enabled ? 1.0 : 0.0;

    // band energies (balanced by gains; flattened by gamma)
    float E_b = mix(0.0, band_energy(band_bass,   gain_bass),   audio_on);
    float E_m = mix(0.0, band_energy(band_mid,    gain_mid),    audio_on);
    float E_t = mix(0.0, band_energy(band_treble, gain_treble), audio_on);
    float E_wide = mix(0.0, band_energy(vec2(0.0,1.0), 1.0), audio_on);

    // effective speed
    float speed_eff = speed * mix(1.0, speed_audio_mul * (1.0 + speed_level_drive * (E_wide - 0.3)), audio_on);
    speed_eff = clamp(speed_eff, speed_min, speed_max);
    float t = TIME * speed_eff;

    // if single-highlight mode, choose band and target arc index
    int single_idx = -1; vec3 single_col = base_tint; float maxv = 0.0;
    if (!highlight_all && audio_on > 0.5){
        maxv = max(E_b, max(E_m, E_t));
        if (maxv > highlight_thresh){
            if (E_b >= E_m && E_b >= E_t){ single_idx = arc_count;                     single_col = bass_color; }
            else if (E_m >= E_t)         { single_idx = int(round((float(arc_count)+1.0)*0.5)); single_col = mid_color;  }
            else                         { single_idx = 1;                              single_col = treble_color; }
        }
    }

    vec3 col = vec3(0.0);

    for(int j=1; j<=ARC_MAX; j++){
        if (j > arc_count) break;

        float u = arc_u(j, arc_count);
        float amp = mix(0.25, spec_at(u), audio_on);

        float y_bias = (float(j) - (float(arc_count)+1.0)*0.5) * (0.18 / float(max(arc_count,1)));
        float bow   = curvature * (uv.x*uv.x - 0.25);
        float field = warp_amp * (
            0.70 * snoise((uv + vec2(t/float(j), -t/float(j))) * (warp_freq * (1.0 + 0.3*amp)))
          + 0.30 * snoise((uv*2.0 + vec2(-t, t)) * (warp_freq*0.6 + 0.2*E_b + 0.2*E_t))
        );

        float width = width_base * float(j) * (1.0 + 0.7 * amp);
        float d = (uv.y + bow + y_bias + field) * width;

        float intensity = abs(4.0 / max(abs(d), 1e-4));
        intensity = pow(intensity, gamma_fix);

        // base tint
        vec3 tint = base_tint * (0.8 + 0.8*amp);

        if (highlight_all){
            // color each arc by its band's hit
            int bid = band_id_for_u(u);
            float e = (bid==0)?E_b : (bid==1)?E_m : E_t;
            vec3  hc = (bid==0)?bass_color : (bid==1)?mid_color : treble_color;
            if (e > highlight_thresh){
                float k = clamp((e - highlight_thresh) / max(1e-4, 1.0 - highlight_thresh), 0.0, 1.0);
                tint = mix(tint, hc, highlight_blend);
                intensity *= 1.0 + highlight_boost * k;
            }
        } else {
            // single highlighted arc
            if (j == single_idx){
                float k = clamp((maxv - highlight_thresh) / max(1e-4, 1.0 - highlight_thresh), 0.0, 1.0);
                tint = mix(tint, single_col, highlight_blend);
                intensity *= 1.0 + highlight_boost * k;
            }
        }

        col += intensity * tint;
    }

    COLOR = vec4(col * glow, 1.0);
}
