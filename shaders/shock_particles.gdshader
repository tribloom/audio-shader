shader_type canvas_item;
render_mode unshaded;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 3.0;
uniform float aspect = 1.0;
uniform float density = 140.0;

float bar_at_index(int i){
    if (bar_count <= 0) return 0.0;
    int idx = clamp(i, 0, bar_count-1);
    float u = (float(idx)+0.5)/float(bar_count);
    return texture(spectrum_tex, vec2(u,0.5)).r * audio_gain;
}
float low_band(){ int n=max(1,min(8,bar_count)); float s=0.0; for(int i=0;i<n;i++) s+=bar_at_index(i); return s/float(n); }
float hi_band(){ int n=max(1,min(16,bar_count)); int start=max(0,bar_count-n); float s=0.0; for(int i=0;i<n;i++) s+=bar_at_index(start+i); return s/float(n); }

vec2 norm_uv(vec2 uv){ vec2 p=uv*2.0-1.0; p.x*=aspect; return p; }
float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898,78.233)))*43758.5453); }

void fragment(){
    vec2 p = norm_uv(UV);
    float bass = audio_enabled ? low_band() : 0.0;
    float tre  = audio_enabled ? hi_band()  : 0.0;

    float acc = 0.0;
    for (int i=0; i<80; i++){
        float fi = float(i);
        float ang = fi*0.078 + TIME*(1.0 + 3.0*tre);
        vec2 dir = vec2(cos(ang), sin(ang));
        float rad = 0.2 + 0.7*hash(vec2(fi, fi*1.37));
        vec2 pos = dir * rad;
        float blink = step(0.95, fract(hash(vec2(fi, TIME*0.7))* (1.0 + 6.0*bass)));
        float d = length(p - pos);
        float spark = smoothstep(0.05, 0.0, d) * blink;
        acc += spark;
    }
    acc = clamp(acc / (density*(0.6+tre)), 0.0, 1.0);
    vec3 col = mix(vec3(0.02), vec3(0.7,0.9,1.0), acc*(1.0 + 1.2*bass));
    COLOR = vec4(col, 1.0);
}
