shader_type canvas_item;

// Ring visibility controls
uniform float ring_idle   = 0.00; // 0 = fully off when quiet, try 0.05 for a faint guide
uniform float ring_gate   = 0.12; // energy gate for a band to light
uniform float ring_knee   = 0.08; // soft knee after the gate
uniform float ring_gamma  = 1.40; // >1 emphasizes louder bands

/* ——— Inputs you already have ——— */
uniform sampler2D spectrum_tex : hint_default_black;
uniform float     spectrum_v   = 0.25;   // V row with spectrum bars
uniform sampler2D color_tex    : hint_default_white; // base color/exp

/* ——— Visual framing ——— */
uniform float aspect      = 1.7777;
uniform float base_gain   = 1.20;
uniform float headroom    = 0.55;
uniform float vignette    = 0.22;

/* ——— Spectrum → bands ——— */
const int  MAX_BANDS = 64;       // compile-time max
uniform int  bar_count = 32;     // set to your spectrum bar count
uniform bool log_frequency = true;   // perceptual spacing
uniform float log_gamma    = 0.6;    // <1.0 = more lows

/* ——— Pulses ——— */
uniform bool  use_audio       = true;
uniform float pulse_speed_lo  = 0.42;  // bass
uniform float pulse_speed_hi  = 0.95;  // highs
uniform float ray_width_lo    = 0.065; // bass
uniform float ray_width_hi    = 0.030; // highs
uniform float pulse_width     = 0.12;
uniform float pulse_gain      = 7.0;
uniform float pulse_gate      = 0.10;
uniform float pulse_knee      = 0.10;
uniform float tint_strength   = 1.75;
uniform float white_boost     = 1.40;
uniform float center_radius   = 0.40;

/* ——— Band origin ring UI (to make mapping obvious) ——— */
uniform bool  show_ring     = true;
uniform float ring_radius   = 0.98;
uniform float ring_size     = 0.022;  // dot size
uniform float ring_glow     = 0.8;    // how soft/bright the dot is

/* ——— Helpers ——— */
vec2 rot2(vec2 p, float a){ float c=cos(a), s=sin(a); return vec2(p.x*c - p.y*s, p.x*s + p.y*c); }
float rand1(float n){ return fract(sin(n) * 43758.5453123); }
vec2  rand2(vec2 p){ return fract(vec2(sin(p.x*591.32 + p.y*154.077), cos(p.x*391.32 + p.y*49.077))); }
float noise1(float p){ float fl=floor(p), fc=fract(p); return mix(rand1(fl), rand1(fl+1.0), fc); }

float voronoi(vec2 x){
    vec2 p=floor(x), f=fract(x), res=vec2(8.0);
    for(int j=-1;j<=1;j++){
        for(int i=-1;i<=1;i++){
            vec2 b=vec2(float(i),float(j));
            vec2 r=b - f + rand2(p+b);
            float d=max(abs(r.x),abs(r.y));
            if(d<res.x){ res.y=res.x; res.x=d; }
            else if(d<res.y){ res.y=d; }
        }
    }
    return res.y - res.x;
}

vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.xxx + vec3(0.0,2.0/3.0,1.0/3.0))*6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p-1.0,0.0,1.0), c.y);
}

/* spectrum sampling */
float spec_sample(float u){ return texture(spectrum_tex, vec2(clamp(u,0.0,1.0), spectrum_v)).r; }
float spec_smooth(float u){
    float du=0.006; float s=0.0;
    s += spec_sample(u-2.0*du);
    s += spec_sample(u-1.0*du);
    s += spec_sample(u);
    s += spec_sample(u+1.0*du);
    s += spec_sample(u+2.0*du);
    return s/5.0;
}

/* map band index -> [0..1] sample position (linear or log) */
float band_u(int idx){
    if (bar_count <= 1) return 0.5;
    float x = float(idx)/(float(bar_count)-1.0);
    if (log_frequency) x = pow(x, log_gamma);
    return x;
}

void fragment(){
    vec2 q   = UV;
    vec2 suv = (q - 0.5) * 2.0;
    vec2 uv  = suv; uv.x *= aspect;

    // same “network” base as before (subtle camera drift)
    float flicker = noise1(TIME*2.0)*0.8 + 0.4;
    vec2 uvm = uv;
    uvm *= 0.6 + sin(TIME*0.1)*0.4;
    uvm  = rot2(uvm, sin(TIME*0.3));
    uvm += TIME*0.4;

    float v=0.0, a=0.6, f=1.0, hot=0.0;
    for(int i=0;i<3;i++){
        float v1 = voronoi(uvm*f + 5.0);
        if(i>0){
            float v2 = voronoi(uvm*f*0.5 + 50.0 + TIME);
            float va = 1.0 - smoothstep(0.0,0.1, v1);
            float vb = 1.0 - smoothstep(0.0,0.08, v2);
            float spark = a * pow(va*(0.5+vb), 2.0);
            v   += spark;
            hot += spark * va;
        }
        v1 = 1.0 - smoothstep(0.0,0.3, v1);
        float add = a * noise1(v1*5.5 + 0.1);
        v += (i==0) ? add*flicker : add;
        f *= 3.0; a *= 0.7;
    }
    v *= exp(-0.6*length(suv))*1.2;
    float edge_mask = pow(clamp(hot*1.8, 0.0, 1.0), 2.0);

    vec3 cexp = texture(color_tex, uvm*0.001).rgb * 3.0 + texture(color_tex, uvm*0.010).rgb;
    cexp *= 1.4;
    vec3 base_col = vec3(pow(v, cexp.x), pow(v, cexp.y), pow(v, cexp.z)) * base_gain * headroom;

    // center emphasis
    float r_center = length(vec2(suv.x*aspect, suv.y));
    float center_zone = 1.0 - smoothstep(center_radius, 0.0, r_center);

    // pulses + ring
    vec3  sum_rgb = vec3(0.0);
    float sum_w   = 0.0;
    vec3  ring_rgb = vec3(0.0);

    int bands = clamp(bar_count, 1, MAX_BANDS);
    for (int k=0; k<MAX_BANDS; k++){
        if (k >= bands) break;

        float u = band_u(k);                      // band’s U in spectrum
        float e = spec_smooth(u);                 // energy
        float amp = use_audio ? max(0.0, e - pulse_gate) : 0.0;
        amp = amp / (amp + pulse_knee);           // soft knee
        amp *= pulse_gain;

        // per-band speed/width (bass→slow/thick, highs→fast/thin)
        float t = float(k) / max(1.0, float(bands-1));
        float speed = mix(pulse_speed_lo, pulse_speed_hi, t);
        float rwidth = mix(ray_width_lo, ray_width_hi, t);

        // origin around a ring (and a tiny unique angle jitter)
        float ang = TAU * t + (rand1(float(k))*0.02 - 0.01);
        vec2  O   = ring_radius * vec2(cos(ang), sin(ang));
        vec2  C   = vec2(0.0);
        vec2  D   = normalize(C - O);
        float L   = length(C - O);

        // ray coords
        vec2  OP = suv - O;
        float s  = dot(OP, D);
        float d  = length(OP - D*clamp(s, 0.0, L));

        // moving front position
        float front = mod(TIME * speed + t*0.37, 1.0) * L;

        // pulse profile
        float across = exp(-(d*d)/(rwidth*rwidth));
        float along  = exp(-((s-front)*(s-front))/(pulse_width*pulse_width));
        float on     = step(pulse_gate, e);       // only show when energy present
        float w      = on * amp * across * along * edge_mask;
        if (s < 0.0 || s > L) w = 0.0;

        vec3 tint = hsv2rgb(vec3(u, 1.0, 1.0));
        sum_rgb += tint * w;
        sum_w   += w;

        // origin dot (ring UI)
   // origin dot (ring UI) — lights only when the band is hot
	if (show_ring){
	    float dr   = length(suv - O);
	    float dotv = exp(- (dr*dr) / (ring_size*ring_size));

	    // gate + soft knee + gamma
	    float ecut = max(0.0, e - ring_gate);
	    float eg   = ecut / (ecut + ring_knee);   // smooth step-up
	    eg         = pow(eg, ring_gamma);

	    // optional faint idle visibility
	    float vis  = max(ring_idle, eg);

	    ring_rgb  += tint * dotv * ring_glow * vis;
	}

    }

    // surge color + “go white” at center when many meet
    vec3 surge_tint = (sum_w > 1e-4) ? (sum_rgb / sum_w) : vec3(0.0);
    float white_mix = clamp(sum_w * white_boost * center_zone, 0.0, 1.0);
    vec3  surge_col = mix(surge_tint, vec3(1.0), white_mix);
    float alpha = clamp(sum_w * tint_strength, 0.0, 0.55);

    vec3 col = mix(base_col, surge_col, alpha) + ring_rgb;

    // vignette + tone map
    vec2 vp = suv; vp.x *= aspect;
    float vig = mix(1.0, smoothstep(1.7, 0.6, length(vp)), vignette);
    col *= vig;
    col  = col / (1.0 + col);
    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
