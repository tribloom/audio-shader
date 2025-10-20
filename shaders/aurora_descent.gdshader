shader_type canvas_item;
render_mode unshaded;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform float fall = 0.25;


float bar_at_index(int i){ if(bar_count<=0) return 0.0; int idx=clamp(i,0,bar_count-1); float u=(float(idx)+0.5)/float(bar_count); return texture(spectrum_tex, vec2(u,0.5)).r*audio_gain; }
float hi_band(){ int n=max(1,min(16,bar_count)); int start=max(0,bar_count-n); float s=0.0; for (int i=0;i<n;i++) s+=bar_at_index(start+i); return s/float(n); }


vec2 norm_uv(vec2 uv){ vec2 p=uv*2.0-1.0; p.x*=aspect; return p; }


float aur(vec2 p){
float w = 0.4 + 0.2*sin(p.x*6.0 + TIME*0.6);
return smoothstep(w, 0.0, abs(p.y + 0.5*sin(p.x*2.0 + TIME*0.8)));
}


void fragment(){
vec2 p = norm_uv(UV);
float h = audio_enabled ? hi_band() : 0.0;
p.y += sin(TIME*fall*2.0) * (0.25 + 0.25*h);
float v = aur(p);
vec3 col = mix(vec3(0.0,0.05,0.1), vec3(0.2,0.8,1.0), v);
COLOR = vec4(col,1.0);
}