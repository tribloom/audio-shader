shader_type canvas_item;

uniform bool use_audio=false;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float u_low:hint_range(0.0,1.0)=0.12;
uniform float u_mid:hint_range(0.0,1.0)=0.35;
uniform float u_hi :hint_range(0.0,1.0)=0.75;

uniform float aspect:hint_range(0.1,4.0)=1.7777;
uniform float zoom:hint_range(0.6,3.0)=1.1;
uniform float stripes:hint_range(3.0,10.0)=6.0;  // fewer
uniform float softness:hint_range(0.05,0.35)=0.18;
uniform float base_speed:hint_range(0.0,2.0)=0.45;
uniform float warp:hint_range(0.0,0.8)=0.25;     // less domain warp

float samp(float u){
    float du=0.008,a=0.0,w=0.0;
    for(int k=-2;k<=2;k++){ float uk=clamp(u+du*float(k),0.0,1.0);
        a+=texture(spectrum_tex, vec2(uk,0.25)).r; w+=1.0; }
    return (w>0.0)?a/w:0.0;
}
float n(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123); }
float v(vec2 p){
    vec2 i=floor(p), f=fract(p);
    vec2 u=f*f*(3.0-2.0*f);
    float a=n(i), b=n(i+vec2(1,0)), c=n(i+vec2(0,1)), d=n(i+vec2(1,1));
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}
vec2 curl(vec2 p){
    float e=0.002;
    float n1=v(p+vec2(e,0.0)) - v(p-vec2(e,0.0));
    float n2=v(p+vec2(0.0,e)) - v(p-vec2(0.0,e));
    return normalize(vec2(n2,-n1));
}
vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.xxx + vec3(0,2.0/3.0,1.0/3.0))*6.0-3.0);
    return c.z * mix(vec3(1.0), clamp(p-1.0,0.0,1.0), c.y);
}

void fragment(){
    vec2 q=vec2(UV.x,1.0-UV.y);
    vec2 p=-1.0+2.0*q; p.x*=aspect; p*=zoom;

    float low=use_audio?samp(u_low):0.25+0.06*sin(TIME*0.5);
    float mid=use_audio?samp(u_mid):0.25+0.06*sin(TIME*0.7+1.7);
    float hi =use_audio?samp(u_hi ):0.20+0.08*sin(TIME*0.9+3.1);

    float t = TIME*(base_speed + 0.6*low);

    vec2 pp = p + warp*vec2(v(p*0.9+0.4*t), v(p*0.9-0.4*t));
    vec2 dir = curl(pp*0.9 + 0.15*t);
    float phase = dot(pp,dir)*stripes + 1.7*v(pp*1.6+0.2*t);

    float s = abs(sin(phase));
    float width = mix(0.28, 0.52, clamp(mid,0.0,1.0));
    float m = smoothstep(width, width-softness, s);

    float glow = pow(m,1.3);

    float hue = fract(0.58 + 0.06*phase/TAU + 0.15*hi);
    vec3 col = hsv2rgb(vec3(hue, 0.85, 1.0))*glow;

    vec3 bg = mix(vec3(0.06,0.09,0.13), vec3(0.02,0.04,0.07), smoothstep(-1.0,1.0,p.y));
    col = bg + col;
    col *= smoothstep(1.9,0.5,length(p));
    COLOR = vec4(clamp(col,0.0,1.0),1.0);
}
