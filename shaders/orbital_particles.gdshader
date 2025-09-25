shader_type canvas_item;

uniform bool use_audio = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float u_bass = 0.18;
uniform float u_mid = 0.45;
uniform float u_high = 0.78;

uniform float aspect = 1.7777;
uniform int   lanes  = 5;                       // ring lanes
uniform int   dots   = 60;                      // total dots
uniform float zoom   : hint_range(0.6,1.6) = 1.0;

float samp(float u){ float du=0.01,a=0.0; for(int k=-2;k<=2;k++) a+=texture(spectrum_tex,vec2(clamp(u+du*float(k),0.0,1.0),0.25)).r; return a/5.0; }
float hash(float x){ return fract(sin(x)*43758.5453); }
vec3 pal(float t){ return 0.5+0.5*cos(6.2831*(t)+vec3(0.0,0.33,0.67)); }

void fragment(){
    vec2 q=vec2(UV.x,1.0-UV.y); vec2 p=-1.0+2.0*q; p.x*=aspect;

    float bass = use_audio? samp(u_bass):0.25+0.06*sin(TIME*0.6);
    float mid  = use_audio? samp(u_mid ):0.25+0.05*sin(TIME*0.4+1.3);
    float hi   = use_audio? samp(u_high):0.25+0.08*sin(TIME*0.9+2.2);

    float z = zoom*(1.0+0.12*bass);  // kick zoom
    p *= z;

    vec3 col = mix(vec3(0.02,0.04,0.07), vec3(0.08,0.10,0.13), q.y);

    int L = max(lanes,1);
    int N = clamp(dots, 10, 120);

    float T = TIME*(0.3+0.4*mid);
    float r0 = 0.25;

    for(int i=0;i<120;i++){
        if(i>=N) break;
        float fi = float(i);
        float lane = float(i % L);
        float r = r0 + 0.12*lane;

        float sp = 0.6 + 0.2*hash(fi*3.1);
        float ph = fi*2.399 + T*sp;
        vec2  c  = r*vec2(cos(ph), sin(ph));

        float d = length(p - c);
        float s = exp(-d*d*140.0);                // soft dot
        vec3  ink= pal(0.2*lane + 0.1*fi + 0.3*hi);
        col = mix(col, ink, clamp(s,0.0,1.0));
    }

    // faint radial glow
    float rg = exp(-dot(p,p)*0.9) * (0.4+0.6*hi);
    col += rg*vec3(0.5,0.8,1.2);

    col *= smoothstep(1.7,0.5,length(p));
    COLOR = vec4(clamp(col,0.0,1.0),1.0);
}
