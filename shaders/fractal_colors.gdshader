shader_type canvas_item;

/* -------- Optional audio -------- */
uniform bool use_audio = false;                 // turn on to use spectrum_tex
uniform sampler2D spectrum_tex : hint_default_black;
uniform int   audio_regions : hint_range(2,12) = 6;   // vertical color bands
uniform float audio_hue_gain : hint_range(0.0,2.0) = 0.65; // hue shift strength
uniform float audio_smooth   : hint_range(0.0,1.0) = 0.25; // soften per-band

/* -------- Look controls (good defaults) -------- */
uniform float aspect     : hint_range(0.1,4.0) = 1.7777;
uniform float zoom       : hint_range(0.5,4.0) = 2.1;
uniform int   iter_count : hint_range(24,200)  = 120;
uniform float eps_div    : hint_range(1e-8,1e-3) = 1e-6;
uniform float exposure   : hint_range(0.3,3.0) = 1.6;
uniform float gamma_fix  : hint_range(0.6,1.4) = 0.9;

/* ---------- helpers ---------- */
vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.xxx + vec3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0);
    return c.z * mix(vec3(1.0), clamp(p-1.0,0.0,1.0), c.y);
}

/* sample a mid/high band and lightly smooth */
float spectrum_sample(float u){
    // small 5-tap average for stability
    float du = 0.006;
    float acc = 0.0; float w = 0.0;
    for(int k=-2;k<=2;k++){
        float uk = clamp(u + du*float(k), 0.0, 1.0);
        acc += texture(spectrum_tex, vec2(uk, 0.25)).r;
        w += 1.0;
    }
    return (w>0.0)? acc/w : 0.0;
}

/* compute a smooth hue offset per X using N bins */
float hue_shift_from_audio(float x){
    int N = max(audio_regions, 2);
    float shift = 0.0;
    float norm  = 0.0;
    float sigma = mix(0.8, 0.25, audio_smooth); // band overlap
    for(int i=0;i<12;i++){          // supports up to 12 regions
        if(i>=N) break;
        float c  = (float(i)+0.5)/float(N);     // band center in [0..1]
        float dx = (x - c) * float(N);          // in-band distance
        float w  = exp(-0.5 * dx*dx / (sigma*sigma)); // gaussian weight
        float u  = (float(i)+0.5)/float(N);     // spectrum bin
        float lvl = spectrum_sample(u);
        shift += w * lvl;
        norm  += w;
    }
    if (norm > 0.0) shift /= norm;
    return shift; // 0..~1
}

void fragment(){
    // centered coords with aspect
    vec2 q = vec2(UV.x, 1.0 - UV.y);
    vec2 p = -1.0 + 2.0*q;
    p.x *= aspect;
    p *= zoom;

    // gentle base motion so it’s alive even without audio
    float t = TIME;
    vec2  C = vec2(1.15 + 0.22*sin(0.31*t),
                   0.95 + 0.20*cos(0.27*t));

    // iterate a safe inversion+fold
    vec2 z = p;
    float trap_min = 1e9;
    float ang_sum  = 0.0;

    int N = iter_count;
    for(int i=0;i<N;i++){
        float r2 = dot(z,z);
        float d  = max(r2, eps_div);
        z = abs(z/d - C);
        float r = length(z);
        trap_min = min(trap_min, r);
        ang_sum += atan(z.y, z.x);
    }

    // vivid base hue from log-bands + angle
    float band = 0.40 * log(1.0 + 8.0 / max(trap_min, 1e-6));
    float hue  = fract(band + 0.12 * sin(ang_sum * 0.22));
    float sat  = 0.95;
    float val  = 1.0;

    // optional, regional audio hue shift
    float hue_shift = 0.0;
    if (use_audio){
        hue_shift = audio_hue_gain * hue_shift_from_audio(UV.x);
    } else {
        // smooth fallback (no spectrum bound)
        hue_shift = 0.10 * sin(0.35*t + 6.28318*UV.x);
    }
    hue = fract(hue + hue_shift);

    vec3 col = hsv2rgb(vec3(hue, sat, val));

    // exposure + gamma to keep it bright without washing out
    col *= exposure;
    col = col / (1.0 + col);
    col = pow(col, vec3(gamma_fix));

    COLOR = vec4(clamp(col,0.0,1.0), 1.0);
}
