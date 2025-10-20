shader_type canvas_item;
render_mode unshaded;


uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;
uniform float aspect = 1.0;
uniform vec3 color_line = vec3(0.0, 1.0, 1.0);
uniform vec3 color_bg = vec3(0.0, 0.0, 0.0);
uniform float grid_scale = 8.0;
uniform float line_thickness = 0.015;
uniform float glow = 0.6;


float bar_at_index(int i){
if (bar_count <= 0) return 0.0;
int idx = clamp(i, 0, bar_count-1);
float u = (float(idx) + 0.5) / float(bar_count);
return texture(spectrum_tex, vec2(u, 0.5)).r * audio_gain;
}


float low_band(){
int n = max(1, min(8, bar_count));
float s = 0.0; for (int i=0; i<n; i++) s += bar_at_index(i);
return s / float(n);
}


vec2 norm_uv(vec2 uv){
vec2 p = uv * 2.0 - 1.0;
p.x *= aspect; // keep shapes circular
return p;
}


float grid(vec2 p, float scale){
p *= scale;
vec2 g = abs(fract(p) - 0.5);
float d = min(g.x, g.y);
return smoothstep(line_thickness, 0.0, d);
}


void fragment(){
vec2 p = norm_uv(UV);
float bass = audio_enabled ? low_band() : 0.0;
float s = grid_scale * (1.0 + 0.35 * bass);
float g = grid(p, s);
float glow_v = pow(g, 0.5) * (glow + bass * 0.8);
vec3 col = mix(color_bg, color_line, glow_v);
COLOR = vec4(col, 1.0);
}