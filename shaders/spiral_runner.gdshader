shader_type canvas_item;
render_mode unshaded;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 3.2;
uniform float aspect = 1.0;
uniform float arms = 3.0;
uniform float thickness = 0.035;

float bar_at_index(int i){
    if (bar_count <= 0) return 0.0;
    int idx = clamp(i, 0, bar_count-1);
    float u = (float(idx)+0.5)/float(bar_count);
    return texture(spectrum_tex, vec2(u,0.5)).r * audio_gain;
}
float mid_band(){
    if (bar_count<=0) return 0.0;
    int a = int(float(bar_count)*0.25);
    int b = int(float(bar_count)*0.65);
    float s=0.0; int n=max(1,b-a);
    for(int i=a;i<b;i++) s+=bar_at_index(i);
    return s/float(n);
}
float low_band(){
    int n=max(1,min(8,bar_count)); float s=0.0;
    for(int i=0;i<n;i++) s+=bar_at_index(i); return s/float(n);
}

vec2 norm_uv(vec2 uv){ vec2 p=uv*2.0-1.0; p.x*=aspect; return p; }

void fragment(){
    vec2 p = norm_uv(UV);
    float r = length(p);
    float ang = atan(p.y, p.x);

    float m = audio_enabled ? mid_band() : 0.0;
    float k = audio_enabled ? low_band() : 0.0;

    float spiral = abs(fract((ang/(2.0*3.14159265))*arms + log(r+0.0001)*(0.25 + 1.2*m)) - 0.5);
    float line = smoothstep(thickness, 0.0, spiral);
    float head = smoothstep(0.015, 0.0, abs(r - (0.25 + 0.2*m)));

    float val = max(line, head*(1.0 + 1.5*k));
    vec3 col = mix(vec3(0.02), vec3(1.0,0.85,0.3), val);
    COLOR = vec4(col, 1.0);
}
