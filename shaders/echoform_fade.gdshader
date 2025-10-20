shader_type canvas_item;
render_mode unshaded;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform float decay = 0.85;


float bar_at_index(int i){ if(bar_count<=0) return 0.0; int idx=clamp(i,0,bar_count-1); float u=(float(idx)+0.5)/float(bar_count); return texture(spectrum_tex, vec2(u,0.5)).r*audio_gain; }
float full_band(){ if(bar_count<=0) return 0.0; float s=0.0; for(int i=0;i<bar_count;i++) s+=bar_at_index(i); return s/max(1.0,float(bar_count)); }


vec2 norm_uv(vec2 uv){ vec2 p=uv*2.0-1.0; p.x*=aspect; return p; }


float line_y(vec2 p, float y, float w){ return smoothstep(w, 0.0, abs(p.y - y)); }


void fragment(){
vec2 p = norm_uv(UV);
float e = audio_enabled ? full_band() : 0.0;
float y = sin(p.x*8.0 + TIME*1.5)*0.2;
float base = line_y(p, y, 0.02 + e*0.03);
float echo1 = line_y(p, y*0.8, 0.02) * decay;
float echo2 = line_y(p, y*0.6, 0.02) * decay*decay;
float v = clamp(base + echo1 + echo2, 0.0, 1.0);
vec3 col = mix(vec3(0.0), vec3(1.0), v);
COLOR = vec4(col,1.0);
}