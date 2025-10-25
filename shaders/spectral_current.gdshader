shader_type canvas_item;

uniform bool enable_audio = true;
uniform float aspect = 1.7778;
uniform sampler2D spectrum_tex;
uniform sampler2D waveform_tex;
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

/* Look */
uniform float flow_scale = 2.2;     // spatial scale of flow
uniform float refract_amp = 0.045;  // base refraction
uniform float ripple_amp  = 0.10;   // user dial (now safely clamped)
uniform float dispersion  = 0.006;  // RGB split
uniform float bg_dim = 0.06;

/* helpers */
float h11(float x){ x=fract(x*0.1031); x*=x+33.33; return fract(1e4*x*(x+0.9)); }
float n2(vec2 p){
    vec2 i=floor(p), f=fract(p);
    vec2 u=f*f*(3.0-2.0*f);
    float a=h11(dot(i,vec2(1.0,57.0)));
    float b=h11(dot(i+vec2(1,0),vec2(1.0,57.0)));
    float c=h11(dot(i+vec2(0,1),vec2(1.0,57.0)));
    float d=h11(dot(i+vec2(1,1),vec2(1.0,57.0)));
    return mix(mix(a,b,u.x),mix(c,d,u.x),u.y);
}
float fbm(vec2 p){
    float s=0.0,a=0.5;
    for(int i=0;i<4;i++){ s+=a*n2(p); p=p*2.02+19.0; a*=0.55; }
    return s;
}
vec2 safe_norm(vec2 v){
    float d = max(dot(v,v), 1e-6);
    return v * inversesqrt(d);
}
float bin(int i){ float x=(float(i)+0.5)/64.0; return texture(spectrum_tex, vec2(x,0.5)).r; }
float band(float a,float b){
    float n=max(1.0,b-a), s=0.0; for(int i=0;i<64;i++){ if(float(i)>=a && float(i)<b) s+=bin(i); }
    return s/n;
}

void fragment(){
    vec2 uv = UV*2.0-1.0; uv.x*=aspect;
    float t = TIME;

    float wf = texture(waveform_tex, vec2(fract(t*0.25),0.5)).r;
    wf = (wf*2.0-1.0)*0.02;

    float low  = enable_audio?band(0.0,10.0)*audio_gain:0.0;
    float mid  = enable_audio?band(10.0,28.0)*audio_gain:0.0;
    float high = enable_audio?band(28.0,56.0)*audio_gain:0.0;

    float sc = flow_scale * (1.0 - 0.05*low);
    vec2 P = uv * sc;

    float f  = fbm(P + vec2(0.35*t, -0.28*t) + wf);
    float f2 = fbm(P * 1.7 - vec2(0.22*t, 0.31*t));
    vec2 grad = vec2(dFdx(f), dFdy(f)); // pseudo-normal

    float bend = refract_amp * (1.0 + 0.9*low + 0.5*level*audio_gain);
    vec2 refr = safe_norm(grad + 1e-4) * bend;

    float r = length(uv);
    // clamp user ripple so internal math stays sane
    float ra = clamp(ripple_amp, 0.0, 0.35);
    float ripple = ra * (0.4 + 1.2*mid);
    float w = sin(6.0*r + 2.2*t + 2.0*mid);
    vec2 rip = ripple * w * safe_norm(uv + 1e-4);

    float K = enable_audio?clamp(kick,0.0,1.0):0.0;
    vec2 shock_vec = 0.045 * K * safe_norm(uv + 1e-4);

    // Chromatic dispersion
    vec2 uvr = uv + refr + rip + shock_vec + vec2( dispersion, 0.0);
    vec2 uvg = uv + refr*0.9 + rip*0.9 + shock_vec;
    vec2 uvb = uv + refr*1.1 + rip*1.1 + shock_vec - vec2( dispersion, 0.0);

    float lr = fbm(uvr*1.6 + vec2(t*0.20, -t*0.17));
    float lg = fbm(uvg*1.6 + vec2(t*0.20, -t*0.17) + 7.0);
    float lb = fbm(uvb*1.6 + vec2(t*0.20, -t*0.17) + 13.0);

    vec3 col = vec3(bg_dim) + vec3(lr, lg, lb);
    col *= 0.85 + 0.6*high;

    // mild tone balance to avoid blowouts at extreme dials
    col = col / (1.0 + col*0.7);

    float vig = smoothstep(1.1, 0.35, length(uv));
    col *= vig;

    COLOR = vec4(clamp(col,0.0,1.8),1.0);
}
