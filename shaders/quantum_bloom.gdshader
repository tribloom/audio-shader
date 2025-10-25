shader_type canvas_item;

uniform bool enable_audio = true;
uniform float aspect = 1.7778;
uniform sampler2D spectrum_tex;
uniform sampler2D waveform_tex;
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

/* Look */
uniform vec3 cell_color : source_color = vec3(0.86, 0.98, 1.0);
uniform vec3 vein_color : source_color = vec3(0.35, 0.70, 1.0);
uniform float bg_dim = 0.04;

uniform float colony_size = 0.75;  // base radius
uniform float cell_count  = 5.0;   // 3..8
uniform float ring_sharp  = 22.0;  // inner ring crispness

mat2 rot(float a){ float c=cos(a), s=sin(a); return mat2(vec2(c,-s),vec2(s,c)); }
float bin(int i){ float x=(float(i)+0.5)/64.0; return texture(spectrum_tex, vec2(x,0.5)).r; }
float band(float a,float b){
    float n=max(1.0,b-a), s=0.0; for(int i=0;i<64;i++){ if(float(i)>=a && float(i)<b) s+=bin(i); }
    return s/n;
}
float sdCircle(vec2 p, float r){ return length(p)-r; }
float soft_union(float a, float b, float k){
    float h = clamp(0.5 + 0.5*(b - a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0 - h);
}

void fragment(){
    vec2 uv = UV*2.0-1.0; uv.x*=aspect;
    float t = TIME;

    float low  = enable_audio?band(0.0,10.0)*audio_gain:0.0;
    float mid  = enable_audio?band(10.0,28.0)*audio_gain:0.0;
    float high = enable_audio?band(28.0,56.0)*audio_gain:0.0;
    float K = enable_audio?clamp(kick,0.0,1.0):0.0;

    float R = colony_size * (0.85 + 0.5*level*audio_gain + 0.4*low);

    int Ni = int(clamp(cell_count, 3.0, 8.0));
    float invN = 1.0 / float(Ni);

    float d = 1e9;
    for(int i=0;i<8;i++){
        if(i>=Ni) break;
        float idx = float(i);

        float ang = (idx*invN)*6.28318 + 0.3*mid + 0.12*sin(t*0.7 + idx);
        float rad = R * (0.35 + 0.18*sin(t*0.9 + idx*1.7)) + 0.28*K;

        vec2 c = vec2(cos(ang), sin(ang)) * rad;

        vec2 p = uv - c;
        float cell_r = 0.38 + 0.12*low;
        float d_cell = sdCircle(p, cell_r);

        d = soft_union(d, d_cell, 0.28);
    }

    float edge = exp(-8.0*max(d,0.0));
    float fill = exp(-8.0*max(-d,0.0));

    float rr = length(uv);
    float rings = sin(20.0*rr + 2.0*t + 2.0*mid);
    rings = exp(- (ring_sharp*(1.0+0.6*high)) * pow(max(0.0, 0.5 + 0.5*rings), 2.0));

    vec3 col = vec3(bg_dim);
    col += cell_color * (0.55*edge + 0.75*fill);
    col += vein_color * 0.9 * rings * fill;

    col *= 0.9 + 0.4*K;

    float vig = smoothstep(1.2, 0.35, length(uv));
    col *= vig;

    COLOR = vec4(clamp(col,0.0,1.8),1.0);
}
