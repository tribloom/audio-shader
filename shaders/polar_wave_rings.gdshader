shader_type canvas_item;

uniform bool use_audio = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float u_bass = 0.18;
uniform float u_mid = 0.45;
uniform float u_high = 0.78;

uniform float aspect = 1.7777;
uniform float freq   : hint_range(2.0,40.0) = 16.0;  // base ring count
uniform float speed  : hint_range(0.0,6.0)  = 2.0;   // outward motion
uniform float width  : hint_range(0.1,3.0)  = 1.1;   // line thickness

float samp(float u){ float du=0.01,a=0.0; for(int k=-2;k<=2;k++) a+=texture(spectrum_tex,vec2(clamp(u+du*float(k),0.0,1.0),0.25)).r; return a/5.0; }
vec3 pal(float t){ return 0.5+0.5*cos(6.2831*(t)+vec3(0.0,0.33,0.67)); }

void fragment(){
    vec2 q=vec2(UV.x,1.0-UV.y); vec2 p=-1.0+2.0*q; p.x*=aspect;
    float r = length(p);

    float bass = use_audio? samp(u_bass):0.25+0.06*sin(TIME*0.6);
    float mid  = use_audio? samp(u_mid ):0.25+0.05*sin(TIME*0.4+1.2);
    float hi   = use_audio? samp(u_high):0.25+0.08*sin(TIME*0.9+2.1);

    float f = freq + 12.0*mid;
    float ph = speed*TIME*(1.0+0.6*bass);
    float s = sin(f*r - ph*TAU);

    // sharp rings
    float line = smoothstep(1.0-width*0.6, 1.0, s*s);
    vec3 bg  = mix(vec3(0.02,0.05,0.08), vec3(0.08,0.12,0.18), q.y);
    vec3 ink = pal(0.25*r + 0.3*line + 0.2*bass);
    vec3 col = mix(bg, ink, line);

    // highs → sparkle on crests
    float crest = smoothstep(0.98, 1.0, s);
    col += crest*(0.5+0.7*hi)*vec3(0.9,1.0,1.0);

    col *= smoothstep(1.7,0.5,r);
    COLOR = vec4(clamp(col,0.0,1.0),1.0);
}
