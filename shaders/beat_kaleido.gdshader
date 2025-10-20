shader_type canvas_item;
render_mode unshaded;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 2.8;
uniform float aspect = 1.0;
uniform float cell_scale = 6.0;
uniform float kick_flash = 1.2;

float bar_at_index(int i){
    if (bar_count <= 0) return 0.0;
    int idx = clamp(i, 0, bar_count-1);
    float u = (float(idx)+0.5)/float(bar_count);
    return texture(spectrum_tex, vec2(u,0.5)).r * audio_gain;
}

float low_band(){
    int n = max(1, min(8, bar_count));
    float s = 0.0; for (int i=0;i<n;i++) s += bar_at_index(i);
    return s / float(n);
}

vec2 norm_uv(vec2 uv){ vec2 p = uv*2.0-1.0; p.x *= aspect; return p; }
vec2 kale(vec2 p){
    p = abs(p);
    p = vec2(max(p.x, p.y), min(p.x, p.y)); // swap for radial diamond sym
    return p;
}

float grid(vec2 p){
    p *= cell_scale;
    vec2 f = abs(fract(p) - 0.5);
    float d = min(f.x, f.y);
    return smoothstep(0.15, 0.0, d);
}

void fragment(){
    vec2 p = norm_uv(UV);
    p = kale(p);

    float kick = audio_enabled ? low_band() : 0.0;
    float g = grid(p * (1.0 + 0.15*kick));
    float glow = pow(g, 0.6) * (1.0 + kick_flash * kick);

    vec3 base = vec3(0.02);
    vec3 c1 = vec3(0.9, 0.2, 1.0);
    vec3 c2 = vec3(0.2, 0.8, 1.0);
    float mixv = smoothstep(0.0, 1.0, length(p));
    vec3 col = mix(c1, c2, mixv) * glow + base*(1.0 - glow);

    COLOR = vec4(col, 1.0);
}
