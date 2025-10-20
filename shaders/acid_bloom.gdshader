shader_type canvas_item;
render_mode unshaded;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform vec3 color_center = vec3(0.7,1.0,0.2);
uniform vec3 color_ring = vec3(1.0,0.8,0.3);
uniform float density = 8.0;


float bar_at_index(int i){
if (bar_count<=0) return 0.0; int idx=clamp(i,0,bar_count-1);
float u=(float(idx)+0.5)/float(bar_count); return texture(spectrum_tex, vec2(u,0.5)).r*audio_gain;
}


float acid_band(){
// emphasize upper mids (squelch)
int a = int(float(bar_count)*0.55);
int b = int(float(bar_count)*0.85);
int n = max(1,b-a); float s=0.0; for(int i=a;i<b;i++) s += bar_at_index(i);
return s/float(n);
}


vec2 norm_uv(vec2 uv){ vec2 p = uv*2.0-1.0; p.x*=aspect; return p; }


void fragment(){
vec2 p = norm_uv(UV);
float ac = audio_enabled ? acid_band() : 0.0;
float r = length(p);
float rings = smoothstep(0.08, 0.0, abs(fract(r * (density+ac*6.0)) - 0.5));
float core = smoothstep(0.2+ac*0.1, 0.0, r);
vec3 col = mix(vec3(0.0), color_ring, rings) + color_center*core;
COLOR = vec4(col,1.0);
}