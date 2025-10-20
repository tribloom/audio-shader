shader_type canvas_item;
render_mode unshaded;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform float spin_speed = 0.25;
uniform float ring_density = 6.0;
uniform float aberration = 0.012;


float bar_at_index(int i){
if (bar_count <= 0) return 0.0;
int idx = clamp(i, 0, bar_count-1);
float u = (float(idx) + 0.5)/float(bar_count);
return texture(spectrum_tex, vec2(u, 0.5)).r * audio_gain;
}


float hi_band(){
int n = max(1, min(16, bar_count));
float s = 0.0; int start = max(0, bar_count - n);
for (int i=0;i<n;i++) s += bar_at_index(start+i);
return s/float(n);
}


vec2 rot(vec2 p, float a){
float c = cos(a), s = sin(a);
return vec2(p.x*c - p.y*s, p.x*s + p.y*c);
}


vec2 norm_uv(vec2 uv){
vec2 p = uv*2.0 - 1.0; p.x *= aspect; return p;
}


float rings(vec2 p, float density){
float r = length(p);
float v = fract(r * density);
float d = abs(v - 0.5);
return smoothstep(0.18, 0.0, d);
}


void fragment(){
vec2 p = norm_uv(UV);
float t = TIME * spin_speed;
float hi = audio_enabled ? hi_band() : 0.0;
p = rot(p, t + hi*0.6);
float base = rings(p, ring_density + hi*3.0);
// simple chromatic aberration
float r = rings(p*(1.0 - aberration), ring_density + hi*3.0);
float g = base;
float b = rings(p*(1.0 + aberration), ring_density + hi*3.0);
COLOR = vec4(r, g, b, 1.0);
}