shader_type canvas_item;
render_mode unshaded;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform float twist = 3.0;
uniform float thickness = 0.04;


float bar_at_index(int i){ if(bar_count<=0) return 0.0; int idx=clamp(i,0,bar_count-1); float u=(float(idx)+0.5)/float(bar_count); return texture(spectrum_tex, vec2(u,0.5)).r*audio_gain; }
float mid_band(){ if(bar_count<=0) return 0.0; int a=int(float(bar_count)*0.3); int b=int(float(bar_count)*0.7); float s=0.0; for(int i=a;i<b;i++) s+=bar_at_index(i); return s/max(1.0,float(b-a)); }


vec2 norm_uv(vec2 uv){ vec2 p=uv*2.0-1.0; p.x*=aspect; return p; }


float helix(vec2 p, float off){
float ang = atan(p.y, p.x);
float r = length(p);
float s = sin(ang*twist + off);
return smoothstep(thickness, 0.0, abs(r - (0.3 + 0.15*s)));
}


void fragment(){
vec2 p = norm_uv(UV);
float m = audio_enabled ? mid_band() : 0.0;
float h1 = helix(p, TIME*1.2);
float h2 = helix(p, TIME*1.2 + PI);
float v = clamp(h1 + h2, 0.0, 1.0) * (1.0 + m);
vec3 col = mix(vec3(0.02), vec3(1.0,0.9,1.0), v);
COLOR = vec4(col,1.0);
}