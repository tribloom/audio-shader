shader_type canvas_item;
render_mode unshaded;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform float wiring_scale = 10.0;
uniform float spark_chance = 0.5;


float bar_at_index(int i){ if(bar_count<=0) return 0.0; int idx=clamp(i,0,bar_count-1); float u=(float(idx)+0.5)/float(bar_count); return texture(spectrum_tex, vec2(u,0.5)).r*audio_gain; }


float low_band(){ int n=max(1,min(8,bar_count)); float s=0.0; for(int i=0;i<n;i++) s+=bar_at_index(i); return s/float(n); }
float hi_band(){ int n=max(1,min(16,bar_count)); int start=max(0,bar_count-n); float s=0.0; for(int i=0;i<n;i++) s+=bar_at_index(start+i); return s/float(n); }


vec2 norm_uv(vec2 uv){ vec2 p=uv*2.0-1.0; p.x*=aspect; return p; }


float trace(vec2 p){
p *= wiring_scale;
vec2 f = fract(p) - 0.5;
float v = min(abs(f.x), abs(f.y));
float d = smoothstep(0.15, 0.0, v);
return d;
}


void fragment(){
vec2 p = norm_uv(UV);
float bass = audio_enabled ? low_band() : 0.0;
float tre = audio_enabled ? hi_band() : 0.0;
float wires = trace(p*(1.0 + bass*0.25));
float sparks = step(1.0 - spark_chance, fract(sin(dot(p, vec2(12.9898,78.233)))*43758.5453 + TIME*3.0*tre));
float val = wires + sparks*tre;
vec3 col = mix(vec3(0.02), vec3(0.0,1.0,0.6), val);
COLOR = vec4(col,1.0);
}