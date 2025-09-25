shader_type canvas_item;

uniform bool use_audio = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float u_bass = 0.18;
uniform float u_mid = 0.45;
uniform float u_high = 0.78;

uniform float aspect = 1.7777;
uniform float flow   : hint_range(0.0,3.0) = 1.2; // speed multiplier
uniform float scale1 : hint_range(0.5,6.0) = 1.8;
uniform float scale2 : hint_range(0.5,6.0) = 3.1;

float samp(float u){ float du=0.01,a=0.0; for(int k=-2;k<=2;k++) a+=texture(spectrum_tex,vec2(clamp(u+du*float(k),0.0,1.0),0.25)).r; return a/5.0; }

float fwarp(vec2 p, float t){
    vec2 q = p;
    q += 0.35*vec2(sin(1.7*q.y+1.1*t), cos(1.5*q.x+0.9*t));
    q += 0.20*vec2(sin(2.1*q.y-1.3*t), cos(1.9*q.x-1.5*t));
    float v = sin(q.x)*cos(q.y);
    return v;
}

void fragment(){
    vec2 q=vec2(UV.x,1.0-UV.y); vec2 p=-1.0+2.0*q; p.x*=aspect;

    float bass = use_audio? samp(u_bass):0.25+0.06*sin(TIME*0.6);
    float hi   = use_audio? samp(u_high):0.25+0.08*sin(TIME*0.9+2.0);

    float t = TIME*flow*(1.0+0.4*bass);

    float c1 = fwarp(p*scale1, t);
    float c2 = fwarp(p*scale2, -t*0.7);
    float ca = abs(c1) + abs(c2);
    ca = pow(smoothstep(0.0, 1.0, ca), 1.6 - 0.8*bass);  // bass -> contrast

    vec3 base = mix(vec3(0.02,0.05,0.08), vec3(0.08,0.12,0.18), q.y);
    vec3 ink  = mix(vec3(0.2,0.6,1.0), vec3(1.0,0.95,0.8), ca);
    vec3 col  = mix(base, ink, ca);

    // highs → tiny twinkles on bright ridges
    float tw = smoothstep(0.85, 1.0, ca) * pow(hi,1.3);
    col += tw*vec3(0.6,0.9,1.2);

    col *= smoothstep(1.7,0.5,length(p));
    COLOR = vec4(clamp(col,0.0,1.0),1.0);
}
