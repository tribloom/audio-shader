shader_type canvas_item;
render_mode unshaded;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform float cell = 12.0;
uniform float thickness = 0.12;


float bar_at_index(int i){
if (bar_count <= 0) return 0.0;
int idx = clamp(i, 0, bar_count-1);
float u = (float(idx)+0.5)/float(bar_count);
return texture(spectrum_tex, vec2(u,0.5)).r * audio_gain;
}


float mid_band(){
if (bar_count <= 0) return 0.0;
int lo = int(float(bar_count)*0.3);
int hi = int(float(bar_count)*0.7);
float s = 0.0; int n = max(1, hi-lo);
for (int i=lo;i<hi;i++) s += bar_at_index(i);
return s/float(n);
}


vec2 norm_uv(vec2 uv){ vec2 p = uv*2.0-1.0; p.x*=aspect; return p; }


float box(vec2 p, vec2 b){ vec2 d = abs(p)-b; return length(max(d,0.0))+min(max(d.x,d.y),0.0); }


void fragment(){
vec2 p = norm_uv(UV);
float m = audio_enabled ? mid_band() : 0.0;
vec2 gp = floor((p*0.5+0.5)*cell);
vec2 id = gp/ max(1.0, cell-1.0);
float pulse = smoothstep(0.0,1.0, m);
vec2 center = (gp+0.5)/cell*2.0-1.0; center.x*=aspect;
float d = box(p-center, vec2(0.07 + pulse*0.05));
float line = smoothstep(thickness, 0.0, d);
vec3 col = mix(vec3(0.04), mix(vec3(0.4,0.0,0.8), vec3(0.8,0.0,1.0), id.x), line);
COLOR = vec4(col,1.0);
}