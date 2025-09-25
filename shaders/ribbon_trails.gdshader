shader_type canvas_item;

uniform bool use_audio = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float u_bass = 0.18;
uniform float u_mid = 0.45;
uniform float u_high = 0.78;

uniform float aspect = 1.7777;
uniform float ribbons = 6.0;            // how many curves
uniform float amp     : hint_range(0.0,0.8) = 0.28; // base vertical amplitude
uniform float thick   : hint_range(0.3,3.0) = 1.2;  // ribbon thickness
uniform float speed   : hint_range(0.0,4.0) = 1.2;

float samp(float u){ float du=0.01,a=0.0; for(int k=-2;k<=2;k++) a+=texture(spectrum_tex,vec2(clamp(u+du*float(k),0.0,1.0),0.25)).r; return a/5.0; }
vec3 pal(float t){ return 0.5+0.5*cos(6.2831*(t)+vec3(0.0,0.5,1.0)); }

void fragment(){
    vec2 q=vec2(UV.x,1.0-UV.y); vec2 p=-1.0+2.0*q; p.x*=aspect;

    float bass = use_audio? samp(u_bass):0.25+0.06*sin(TIME*0.6);
    float mid  = use_audio? samp(u_mid ):0.25+0.05*sin(TIME*0.4+1.3);
    float hi   = use_audio? samp(u_high):0.25+0.08*sin(TIME*0.9+2.2);

    vec3 col = mix(vec3(0.02,0.04,0.07), vec3(0.08,0.10,0.13), q.y);

    int N = int(clamp(ribbons,1.0,12.0));
    float A = amp*(1.0+0.9*mid);               // mids drive sway
    float T = TIME*speed*(1.0+0.2*bass);

    for(int i=0;i<12;i++){
        if(i>=N) break;
        float fi = float(i);
        float k  = 1.0 + 0.25*fi;
        float ph = fi*1.618 + T;
        float y  = A*sin(k*p.x + ph);
        float d  = abs(p.y - y);
        float g  = exp(-d*d*(8.0/thick));      // soft gaussian band

        vec3 ink = pal(0.15*fi + 0.25*p.x + 0.3*bass);
        col = mix(col, ink, clamp(g,0.0,1.0));
    }

    // highs add sparkles along center line
    float spark = exp(-p.y*p.y*18.0) * pow(hi,1.3);
    col += spark*vec3(1.2,1.1,0.8);

    col *= smoothstep(1.7,0.5,length(p));
    COLOR = vec4(clamp(col,0.0,1.0),1.0);
}
