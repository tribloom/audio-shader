shader_type canvas_item;
render_mode unshaded;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform float density = 7.0;


float bar_at_index(int i){ if(bar_count<=0) return 0.0; int idx=clamp(i,0,bar_count-1); float u=(float(idx)+0.5)/float(bar_count); return texture(spectrum_tex, vec2(u,0.5)).r*audio_gain; }
float full_band(){ if(bar_count<=0) return 0.0; float s=0.0; for(int i=0;i<bar_count;i++) s+=bar_at_index(i); return s/max(1.0,float(bar_count)); }


vec2 norm_uv(vec2 uv){ vec2 p=uv*2.0-1.0; p.x*=aspect; return p; }


float ring(vec2 p, float r, float w){ return smoothstep(w, 0.0, abs(length(p)-r)); }


void fragment(){
vec2 p = norm_uv(UV);
float energy = audio_enabled ? full_band() : 0.0;
float r = length(p);
float v = 0.0;
for (int i=0;i<6;i++){
float rr = float(i+1)/density + energy*0.2;
v += ring(p, rr, 0.02+energy*0.02);
}
vec3 col = mix(vec3(0.03), vec3(1.0), pow(clamp(v,0.0,1.0), 1.2));
COLOR = vec4(col, 1.0);
}