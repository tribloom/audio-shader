shader_type canvas_item;

/* === REQUIRED: exactly what your extras already set === */
uniform sampler2D spectrum_tex;               // 1×N RG8: R=bin, G=peak
uniform vec2 rect_size = vec2(1920.0,1080.0); // pixels
uniform vec2 rect_pos  = vec2(0.0,0.0);       // pixels (top-left)

/* ---- fixed look (no extra knobs) ---- */
const float GAMMA = 0.70;   // perceptual lift for quiet bins
const float GAIN  = 6.00;   // visibility
const float BAR_PX  = 2.0;
const float LINE_PX = 1.5;

const vec3 COL_BG   = vec3(0.02, 0.02, 0.02);
const vec3 COL_PEAK = vec3(0.95, 0.70, 0.20);

/* Shadertoy-ish gradient: blue->cyan->yellow->white */
vec3 ramp(float t){
    t = clamp(t, 0.0, 1.0);
    vec3 c1 = vec3(0.10, 0.25, 0.80);
    vec3 c2 = vec3(0.10, 0.80, 0.90);
    vec3 c3 = vec3(0.95, 0.85, 0.20);
    vec3 c4 = vec3(0.98, 0.98, 0.98);
    if (t < 0.33) return mix(c1, c2, t/0.33);
    if (t < 0.66) return mix(c2, c3, (t-0.33)/0.33);
    return mix(c3, c4, (t-0.66)/0.34);
}

/* === We do NOT rely on UV/SCREEN_UV/FRAGCOORD === */
varying vec2  vf_uv;     // 0..1 across rect
varying float vf_px_uv;  // ~1px in UV

void vertex(){
    vec2 local = VERTEX - rect_pos;
    vf_uv = clamp(local / max(rect_size, vec2(1.0)), 0.0, 1.0);
    vf_px_uv = 1.0 / max(rect_size.x, rect_size.y);
}

float px_uv(float px){ return vf_px_uv * px; }
float line_mask(float d, float px){ return smoothstep(px_uv(px), 0.0, d); }

/* exact sampling from 1px-tall strip: use LOD 0 to avoid blank mips */
float spec_r(float u){ return textureLod(spectrum_tex, vec2(u, 0.5), 0.0).r; }
float spec_g(float u){ return textureLod(spectrum_tex, vec2(u, 0.5), 0.0).g; }

/* log-ish frequency remap like many Shadertoy FFTs */
float logmap(float x){
    // avoid 0 singularity; assume ~1024 bins typical
    float min_f = 1.0 / 1024.0;
    float a = log(min_f);
    float t = a + (0.0 - a) * clamp(x, 0.0, 1.0);
    return clamp(exp(t), 0.0, 1.0);
}

/* perceptual lift */
float lift(float x){ return pow(max(x,0.0), GAMMA) * GAIN; }

void fragment(){
    vec2 uv = vf_uv;
    vec3 col = COL_BG;

    // frequency coordinate with log spread (classic Shadertoy feel)
    float u = logmap(clamp(uv.x, 0.0, 1.0));

    // magnitude from spectrum R, peak from G
    float m  = clamp(lift(spec_r(u)), 0.0, 1.0);  // 0..1 after lift
    float pk = clamp(spec_g(u), 0.0, 1.0);

    // mirrored mountain around centerline (Shadertoy FFT vibe)
    float y_mid = 0.5;
    float half_h = 0.42;                     // total height of lobes
    float top_edge    = y_mid + m * half_h;  // upper lobe
    float bottom_edge = y_mid - m * half_h;  // lower lobe

    // fill upper & lower lobes with gradient by magnitude
    float up    = smoothstep(0.0, px_uv(BAR_PX)*0.6, max(0.0, uv.y - (y_mid)) ) *
                  smoothstep(0.0, px_uv(BAR_PX)*0.6, max(0.0, top_edge - uv.y));
    float down  = smoothstep(0.0, px_uv(BAR_PX)*0.6, max(0.0, (y_mid) - uv.y)) *
                  smoothstep(0.0, px_uv(BAR_PX)*0.6, max(0.0, uv.y - bottom_edge));

    vec3 grad = ramp(m);
    col = mix(col, grad, up + down);

    // thin peak line on the upper lobe (from G channel)
    float peak_y = y_mid + pk * half_h;
    col = mix(col, COL_PEAK, line_mask(abs(uv.y - peak_y), LINE_PX));

    COLOR = vec4(col, 1.0);
}
