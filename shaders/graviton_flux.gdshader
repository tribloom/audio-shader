shader_type canvas_item;

uniform bool enable_audio = true;
uniform float aspect = 1.7778;
uniform sampler2D spectrum_tex;
uniform sampler2D waveform_tex;
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

uniform vec3 band_color : source_color = vec3(0.90, 0.98, 1.0);
uniform vec3 caustic_color : source_color = vec3(0.35, 0.70, 1.0);
uniform float bg_dim = 0.035;

uniform float shear_amt = 0.55;    // baseline shear
uniform float band_freq = 8.0;     // number of bands
uniform float band_sharp= 24.0;    // band crispness
uniform float caustic_mix = 0.8;   // intersection brightness

float bin(int i){ float x=(float(i)+0.5)/64.0; return texture(spectrum_tex, vec2(x,0.5)).r; }
float bandp(float a,float b){
    float n=max(1.0,b-a), s=0.0; for(int i=0;i<64;i++){ if(float(i)>=a && float(i)<b) s+=bin(i); }
    return s/n;
}
float ridge(float x, float k){ x=1.0-abs(x); return exp(-k*x*x); } // sharp, safe ridge

void fragment(){
    vec2 uv = UV*2.0-1.0; uv.x*=aspect;
    float t = TIME;

    float low  = enable_audio?bandp(0.0,10.0)*audio_gain:0.0;
    float mid  = enable_audio?bandp(10.0,28.0)*audio_gain:0.0;
    float high = enable_audio?bandp(28.0,56.0)*audio_gain:0.0;
    float K = enable_audio?clamp(kick,0.0,1.0):0.0;

    // Two orthogonal shear fields (no polar/tunnel)
    float shear = shear_amt + 0.7*low;
    vec2 U = uv + vec2( sin( (uv.y*band_freq) + 1.7*t + 2.0*mid ), 0.0 ) * (0.12*shear);
    vec2 V = uv + vec2( 0.0, sin( (uv.x*band_freq) + 1.9*t + 1.6*mid ) ) * (0.12*shear);

    // Bands: sharp ridges on both axes
    float bx = ridge(sin(U.x*band_freq + 0.6*sin(t) + 0.8*mid), band_sharp*(1.0+0.5*high));
    float by = ridge(sin(V.y*band_freq + 0.7*cos(t) + 0.8*mid), band_sharp*(1.0+0.5*high));

    // Interference / caustics at intersections
    float cross = bx*by;
    float caust = smoothstep(0.0, 1.0, cross) * (0.7 + 0.8*high);

    // Kick: global shear pulse
    float pulse = 1.0 + 0.25*K;

    vec3 col = vec3(bg_dim);
    col += band_color    * (0.55*bx + 0.55*by) * pulse;
    col += caustic_color * (caustic_mix * caust);

    // Soft vignette
    float vig = smoothstep(1.25, 0.4, length(uv));
    col *= vig;

    // Gentle tone balance
    col = col / (1.0 + col*0.6);

    COLOR = vec4(clamp(col,0.0,1.8),1.0);
}
