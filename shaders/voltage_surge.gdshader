shader_type canvas_item;
render_mode unshaded;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform float bolt_freq = 8.0;
uniform float thickness = 0.035;


float bar_at_index(int i){ if(bar_count<=0) return 0.0; int idx=clamp(i,0,bar_count-1); float u=(float(idx)+0.5)/float(bar_count); return texture(spectrum_tex, vec2(u,0.5)).r*audio_gain; }
float low_band(){ int n=max(1,min(8,bar_count)); float s=0.0; for(int i=0;i<n;i++) s+=bar_at_index(i); return s/float(n); }


vec2 norm_uv(vec2 uv){ vec2 p=uv*2.0-1.0; p.x*=aspect; return p; }


float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }


float lightning(vec2 p){
// vertical bolt with jittering segments
float x = p.x + (hash(vec2(floor(p.y*bolt_freq), TIME)) - 0.5)*0.2;
float d = abs(x);
return smoothstep(thickness, 0.0, d);
}


void fragment(){
vec2 p = norm_uv(UV);
float bass = audio_enabled ? low_band() : 0.0;
float v = lightning(p*(1.0 + bass*0.15));
vec3 col = mix(vec3(0.0), vec3(0.3,0.6,1.0), v*(1.0 + bass*1.2));
COLOR = vec4(col,1.0);
}