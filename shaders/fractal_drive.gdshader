shader_type canvas_item;
render_mode unshaded;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform float iter_gain = 1.25;
uniform float zoom = 1.2;


float bar_at_index(int i){ if(bar_count<=0) return 0.0; int idx=clamp(i,0,bar_count-1); float u=(float(idx)+0.5)/float(bar_count); return texture(spectrum_tex, vec2(u,0.5)).r*audio_gain; }


float full_band(){ if(bar_count<=0) return 0.0; float s=0.0; for(int i=0;i<bar_count;i++) s+=bar_at_index(i); return s/max(1.0,float(bar_count)); }


vec2 norm_uv(vec2 uv){ vec2 p=uv*2.0-1.0; p.x*=aspect; return p*zoom; }


void fragment(){
vec2 z = norm_uv(UV);
float a = audio_enabled ? full_band()*iter_gain : 0.0;
vec2 c = vec2(-0.6, 0.45 + a*0.1);
int it = 0; int MAX_IT = 48;
for(int i=0;i<MAX_IT;i++){
float x = (z.x*z.x - z.y*z.y) + c.x;
float y = (2.0*z.x*z.y) + c.y;
z = vec2(x,y);
if (dot(z,z) > 4.0) { it = i; break; }
it = i;
}
float t = float(it)/float(MAX_IT);
vec3 col = mix(vec3(0.0,0.0,0.1), vec3(0.4,0.6,1.0), t);
COLOR = vec4(col,1.0);
}