shader_type canvas_item;

/* Optional audio */
uniform bool use_audio = false;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float u_bass : hint_range(0.0,1.0) = 0.18;
uniform float u_mid  : hint_range(0.0,1.0) = 0.38;
uniform float u_high : hint_range(0.0,1.0) = 0.75;

/* Look */
uniform float aspect     : hint_range(0.1,4.0) = 1.7777;
uniform float grid_scale : hint_range(6.0,40.0) = 16.0;
uniform float step_count : hint_range(3.0,24.0) = 10.0;
uniform float height_amp : hint_range(0.0,3.0)  = 1.6;
uniform float shade_amt  : hint_range(0.0,1.5)  = 1.0;
uniform float fog_amt    : hint_range(0.0,1.5)  = 0.35;
uniform float accent_prob: hint_range(0.0,1.0)  = 0.15;

/* Palette via HSV */
uniform float hue_base   : hint_range(0.0,1.0) = 0.58; // ~cyan-blue
uniform float hue_range  : hint_range(0.0,1.0) = 0.18; // spread by height
uniform float sat_base   : hint_range(0.0,1.0) = 0.75;
uniform float val_base   : hint_range(0.0,2.0) = 1.2;
uniform float hue_sway   : hint_range(0.0,0.3) = 0.06; // highs → tint

/* Accents */
uniform vec3 col_accent1 = vec3(0.95,0.15,0.15); // red
uniform vec3 col_accent2 = vec3(0.02,0.02,0.02); // black

/* Helpers */
float h(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123); }
float v(vec2 p){
    vec2 i=floor(p), f=fract(p);
    vec2 u=f*f*(3.0-2.0*f);
    float a=h(i), b=h(i+vec2(1,0)), c=h(i+vec2(0,1)), d=h(i+vec2(1,1));
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}
float samp(float u){
    float du=0.006,a=0.0,w=0.0;
    for(int k=-2;k<=2;k++){ float uk=clamp(u+du*float(k),0.0,1.0);
        a+=texture(spectrum_tex, vec2(uk,0.25)).r; w+=1.0; }
    return (w>0.0)?a/w:0.0;
}
vec3 hsv2rgb(vec3 c){
    vec3 p = abs(fract(c.xxx + vec3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0);
    return c.z * mix(vec3(1.0), clamp(p-1.0,0.0,1.0), c.y);
}

void fragment(){
    vec2 q = vec2(UV.x, 1.0-UV.y);
    vec2 p = -1.0 + 2.0*q; p.x *= aspect;

    float bass = use_audio? samp(u_bass) : 0.25 + 0.06*sin(TIME*0.6);
    float mid  = use_audio? samp(u_mid ) : 0.25 + 0.05*sin(TIME*0.4+1.2);
    float hig  = use_audio? samp(u_high) : 0.25 + 0.08*sin(TIME*0.9+2.7);

    vec2 gp = p * grid_scale;
    vec2 ci = floor(gp);
    vec2 fc = fract(gp) - 0.5;

    float base = v((ci + 7.3)*0.15 + 0.10*TIME);
    float steps = step_count + 8.0*mid;
    float stepped = floor( (base + height_amp*bass) * steps ) / max(1.0, steps);

    // neighbor gradient for fake light
    float nx=v(((ci+vec2(1.0,0.0))+7.3)*0.15+0.10*TIME)-base;
    float ny=v(((ci+vec2(0.0,1.0))+7.3)*0.15+0.10*TIME)-base;
    float ldot = clamp(0.6 + 0.8*(-0.7*nx + 0.6*ny), 0.0, 1.0);
    float side = 1.0 - shade_amt*(0.35 + 0.65*abs(fc.x) + 0.35*abs(fc.y));

    // height→HSV color
    float hue = fract(hue_base + hue_range*stepped + hue_sway*hig);
    vec3 tower = hsv2rgb(vec3(hue, sat_base, val_base));
    tower *= 0.55 + 0.75*ldot;
    tower *= side;

    // accents on highs
    float acc_hash = h(ci*3.11 + 5.7);
    if ((hig > 0.35) && (acc_hash < accent_prob)){
        tower = mix(col_accent2, col_accent1, step(0.5, acc_hash));
        tower *= 0.8 + 0.6*hig;
    }

    // face mask
    float r = max(abs(fc.x), abs(fc.y));
    float face = smoothstep(0.52, 0.48, r);

    // fog and outlines
    float fog = mix(1.0, 0.7, fog_amt * smoothstep(0.2,1.2,length(p)));
    vec3 bg = vec3(0.02,0.04,0.07);
    vec3 col = mix(bg, tower, face) * fog;

    float px = max(fwidth(fc.x), fwidth(fc.y));
    float outline = smoothstep(0.5, 0.5 - 2.0*px, max(abs(fract(gp.x)-0.5), abs(fract(gp.y)-0.5)));
    col = mix(col, col*0.82, outline*0.7);

    COLOR = vec4(clamp(col,0.0,1.0),1.0);
}
