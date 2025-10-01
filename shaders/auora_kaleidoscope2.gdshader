shader_type canvas_item;
render_mode unshaded;

/* ==== Kaleidoscope controls ==== */
uniform int   segments        = 12;
uniform float angle_offset    = 0.0;
uniform float rotate_speed    = 0.25;
uniform float zoom            = 1.02;

/* ==== Flow aurora (pattern) ==== */
uniform float flow_speed      = 0.40;
uniform float warp_strength   = 0.80;
uniform float warp_scale      = 1.35;
uniform float stripe_freq     = 5.0;
uniform float stripe_contrast = 2.0;
uniform float stripe_layers   = 4.0;

/* ==== Color & tone ==== */
uniform vec3  color_low       = vec3(0.20, 0.75, 1.00);  // base color
uniform vec3  color_high      = vec3(1.00, 0.45, 0.25);  // target color on highs
uniform float hue_shift       = 0.0;     // optional slow palette travel 0..1
uniform float glow_strength   = 0.80;    // subtle ribbon glow
uniform float vignette_pow    = 0.85;
uniform float exposure        = 1.12;

/* ==== Spectrum (amp from cyan bar) ==== */
uniform bool       audio_enabled = false;
uniform sampler2D  spectrum_tex;      // 1 x bar_count row, R=magnitude
uniform int        bar_count     = 64;
uniform float      audio_gain    = 1.0;

/* ==== Pulse mapping (from amp -> magenta) ==== */
uniform float pulse_floor   = 0.86;   // amp below this -> no color shift
uniform float pulse_ceiling = 0.98;   // amp at this -> full color shift
uniform float pulse_gamma   = 1.35;   // >1 gentler ramp, <1 snappier
uniform float amp_boost     = 2.0;    // extra scale after mapping
uniform float color_mix     = 1.0;    // 0..1 amount of color shift at pulse=1

/* Debug HUD */
uniform bool  debug_view = false;



/* ------- noise & helpers ------- */
float hash(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){
    vec2 i=floor(p), f=fract(p);
    float a=hash(i), b=hash(i+vec2(1.0,0.0)), c=hash(i+vec2(0.0,1.0)), d=hash(i+vec2(1.0,1.0));
    vec2 u=f*f*(3.0-2.0*f);
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}
float fbm(vec2 p){ float v=0.0, a=0.5; for(int k=0;k<5;k++){ v+=a*vnoise(p); p*=2.0; a*=0.5; } return v; }

vec2 kaleido(vec2 p, int seg, float extra_rot){
    float r = length(p);
    float a = atan(p.y, p.x) + extra_rot;
    float sector = TAU / float(max(seg,3));
    a -= sector * floor(a / sector);
    a = abs(a - 0.5*sector);
    return r * vec2(cos(a), sin(a));
}

/* HSV-ish helpers */
vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.xxx + vec3(0., 2./3., 1./3.)) * 6. - 3.);
    return c.z * mix(vec3(1.), clamp(p-1., 0., 1.), c.y);
}
vec3 hue_rotate(vec3 base_rgb, float t){ // t in 0..1
    vec3 target = hsv2rgb(vec3(fract(t), 0.9, 1.0));
    return mix(base_rgb, target, 0.35);
}

/* compute slow loudness (amp) and a gentle hue bias */
void spectrum_amp_hue(out float amp, out float hue_t){
    amp = 0.0; hue_t = 0.0;
    if (!audio_enabled || bar_count <= 0) return;
    int n = max(bar_count, 1);
    float sum=0.0, hue_acc=0.0, w=0.0;
    for(int i=0;i<256;i++){
        if(i>=n) break;
        float u=(float(i)+0.5)/float(n);
        float m=texture(spectrum_tex, vec2(u,0.5)).r * audio_gain;
        sum += m;
        hue_acc += m * (float(i)/max(1.0,float(n-1)));
        w += 1.0;
    }
    float avg = (w>0.0)? sum/w : 0.0;               // cyan meter
    amp   = clamp(pow(avg, 0.6), 0.0, 2.0);
    hue_t = clamp(hue_acc / max(sum*40.0 + 1.0, 1.0), 0.0, 1.0);
}

/* multi-directional stripes with domain warp (never degrades into rings) */
float stripes(vec2 p, float t){
    vec2 w = vec2(fbm(p*warp_scale + vec2( 1.3,-0.7)*t),
                  fbm(p*warp_scale + vec2(-0.9, 1.1)*t));
    p += warp_strength * (w - 0.5);
    float v=0.0; int L=int(clamp(stripe_layers,1.0,4.0));
    for(int i=0;i<4;i++){
        if(i>=L) break;
        float ang = t*0.25 + float(i)*TAU/float(L);
        vec2 d = vec2(cos(ang), sin(ang));
        float s = sin(dot(p,d)*stripe_freq + fbm(p*1.7 + d*0.8)*1.6 - t*flow_speed);
        v += pow(0.5 + 0.5*s, stripe_contrast);
    }
    return v/float(L);
}

/* tiny rect mask for debug bars */
float rect_mask(vec2 uv, vec2 pos, vec2 size){
    vec2 d = step(pos, uv) * step(uv, pos+size);
    return d.x * d.y;
}

/* ------- fragment ------- */
void fragment(){
    vec2 RES  = 1.0 / SCREEN_PIXEL_SIZE;
    vec2 uv01 = SCREEN_UV;
    vec2 g = (uv01 - 0.5) * vec2(RES.x/RES.y, 1.0);
    float t = TIME;

    /* 1) Cyan amp -> mapped pulse (magenta) */
    float amp, hue_t; spectrum_amp_hue(amp, hue_t);
    float num = amp - pulse_floor;
    float den = max(1e-4, pulse_ceiling - pulse_floor);
    float pulse01 = clamp(num / den, 0.0, 1.0);
    pulse01 = pow(pulse01, max(0.01, pulse_gamma));
    float pulse = clamp(pulse01 * amp_boost, 0.0, 1.0);

    /* 2) Kaleidoscope domain (no pulse in zoom/brightness) */
    g *= zoom;
    float spin = angle_offset + rotate_speed * t;
    vec2  pk   = kaleido(g, segments, spin);

    /* 3) Pattern value (structure) */
    float v = stripes(pk, t);

    /* 4) COLOR SHIFT ONLY: blend between two colors by pulse */
    vec3 base_col  = hue_rotate(color_low,  hue_shift + 0.05*sin(t*0.07) + 0.30*hue_t);
    vec3 target_col= hue_rotate(color_high, hue_shift + 0.05*sin(t*0.07) + 0.30*hue_t);
    float cmix = clamp(pulse * color_mix, 0.0, 1.0);
    vec3 col = mix(base_col, target_col, cmix);

    /* 5) Subtle glow from structure (NOT from pulse) */
    float glow = smoothstep(0.60, 1.0, v) * glow_strength;

    /* 6) Compose WITHOUT pulse brightness: stable, non-flashy */
    vec3 rgb = col * (0.35 + 0.90*v + 0.55*glow);

    /* 7) Vignette + tonemap */
    float vig = pow(smoothstep(1.15, 0.15, length(g)), vignette_pow);
    rgb *= vig;
    rgb = 1.0 - exp(-rgb * exposure);
    rgb = sqrt(rgb);

    /* Debug: cyan=amp, magenta=pulse */
    if (debug_view){
        float cyan = clamp(amp, 0.0, 1.0);
        float mag  = clamp(pulse, 0.0, 1.0);
        vec2 pos1=vec2(0.02,0.02), siz1=vec2(0.25*cyan,0.014);
        vec2 pos2=vec2(0.02,0.04), siz2=vec2(0.25*mag, 0.014);
        rgb = mix(rgb, vec3(0.2,1.0,1.0), rect_mask(uv01,pos1,siz1));
        rgb = mix(rgb, vec3(1.0,0.2,1.0), rect_mask(uv01,pos2,siz2));
    }

    COLOR = vec4(rgb, 1.0);
}
