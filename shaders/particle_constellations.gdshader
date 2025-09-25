shader_type canvas_item;

uniform bool use_audio = false;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float audio_bass_u  : hint_range(0.0,1.0)=0.18;
uniform float audio_high_u  : hint_range(0.0,1.0)=0.72;

uniform float aspect : hint_range(0.1,4.0)=1.7777;
uniform float density : hint_range(1.5,6.0)=3.2;
uniform float link_strength : hint_range(0.0,3.0)=1.6;   // ↑ stronger web

float samp(float u){
    float du=0.01,a=0.0,w=0.0;
    for(int k=-3;k<=3;k++){
        float uk=clamp(u+du*float(k),0.0,1.0);
        a+=texture(spectrum_tex, vec2(uk,0.25)).r; w+=1.0;
    }
    return (w>0.0)?a/w:0.0;
}
float h(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123); }
vec2  rnd2(vec2 p){
    return fract(sin(vec2(dot(p,vec2(12.9898,78.233)),
                          dot(p,vec2(39.346,11.135))))*43758.5453);
}

void fragment(){
    vec2 q=vec2(UV.x,1.0-UV.y);
    vec2 p=-1.0+2.0*q; p.x*=aspect;

    float bass = use_audio? samp(audio_bass_u) : 0.25+0.05*sin(TIME*0.6);
    float high = use_audio? samp(audio_high_u) : 0.25+0.10*sin(TIME*1.1+1.7);

    vec2 gp = p * density;
    vec2 ci = floor(gp);                    // cell index (renamed from i)
    vec2 f  = fract(gp);

    float d1=1e9,d2=1e9; vec2 s1=vec2(0.0), s2=vec2(0.0);
    for(int yy=-1; yy<=1; yy++)
    for(int xx=-1; xx<=1; xx++){
        vec2 g = ci + vec2(float(xx), float(yy));    // <-- float cast
        vec2 r = rnd2(g);
        vec2 pos = r + 0.15*sin(TIME*0.2 + TAU*r);
        vec2 d = (vec2(float(xx),float(yy)) + pos) - f;
        float dist = dot(d,d);
        if(dist<d1){ d2=d1; s2=s1; d1=dist; s1=d; }
        else if(dist<d2){ d2=dist; s2=d; }
    }

    float star = exp(-12.0*dot(s1,s1));
    // highs → twinkle gain
    float twk = 0.7 + 1.3*pow(high, 0.8);
    star *= twk;

    // Voronoi ridge; bass widens/brightens links
    float ridge = (sqrt(d2)-sqrt(d1));
    float edge = clamp(0.9 - ridge * (3.2 + 4.0*bass*link_strength), 0.0, 1.0);
    edge = smoothstep(0.35, 0.95, edge);

    vec3 bg   = vec3(0.02,0.04,0.07);
    vec3 col  = bg + vec3(0.32,0.58,1.0)*edge + vec3(0.95)*star;
    col *= smoothstep(1.6,0.4,length(p));
    COLOR = vec4(clamp(col,0.0,1.0),1.0);
}
