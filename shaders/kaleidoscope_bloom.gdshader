shader_type canvas_item;

uniform bool use_audio = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float u_bass = 0.18;
uniform float u_mid = 0.45;
uniform float u_high = 0.78;

uniform float aspect = 1.7777;
uniform int   segs   = 8;        // symmetry segments
uniform float warp   : hint_range(0.0,1.5) = 0.6;
uniform float glow   : hint_range(0.0,2.0) = 1.0;

float samp(float u){ float du=0.01,a=0.0; for(int k=-2;k<=2;k++) a+=texture(spectrum_tex,vec2(clamp(u+du*float(k),0.0,1.0),0.25)).r; return a/5.0; }
vec3 pal(float t){ return 0.5+0.5*cos(vec3(0.0,0.6,1.0)*6.2831*(t)+vec3(0.0,0.5,1.0)); }

void fragment(){
    vec2 q=vec2(UV.x,1.0-UV.y); vec2 p=-1.0+2.0*q; p.x*=aspect;

    float bass = use_audio? samp(u_bass):0.25+0.06*sin(TIME*0.6);
    float mid  = use_audio? samp(u_mid ):0.25+0.05*sin(TIME*0.4+1.2);
    float hi   = use_audio? samp(u_high):0.25+0.08*sin(TIME*0.9+2.1);

    // Polar
    float r = length(p);
    float a = atan(p.y,p.x);
    float seg = float(max(segs,1));
    a = abs(mod(a, TAU/seg) - (TAU/seg)*0.5);          // mirror inside segment

    // Core pattern
    float t = TIME*0.25 + 0.4*bass;
    float w = a + warp*(0.5*sin(3.0*a + 2.0*r + t) + 0.5*cos(2.0*a - 3.0*r + t));
    float band = 0.6 + 0.4*sin(8.0*w + 5.0*r - 2.0*t);

    // Color + bloom
    vec3 col = pal(0.15*r + 0.25*band + 0.2*mid);
    float bloom = smoothstep(0.86, 1.0, band) * (0.7+0.6*hi);
    col += glow*bloom*vec3(1.0,0.9,0.7);

    // Falloff
    col *= smoothstep(1.7,0.5,r);
    COLOR = vec4(clamp(col,0.0,1.0),1.0);
}
