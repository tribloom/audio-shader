shader_type canvas_item;

uniform bool enable_audio = true;
uniform float aspect = 1.7778;
uniform sampler2D spectrum_tex;
uniform sampler2D waveform_tex; // optional
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

uniform vec3 rim_color  : source_color = vec3(0.9, 0.98, 1.0);
uniform vec3 core_color : source_color = vec3(0.35, 0.70, 1.0);
uniform float ribbon_density = 6.0; // 1..16
uniform float depth_scroll   = 0.55;
uniform float twist_base     = 1.8;

float bin(int i){ float x=(float(i)+0.5)/64.0; return texture(spectrum_tex, vec2(x,0.5)).r; }
float band(float a, float b){
    float n = max(1.0, b-a), s=0.0;
    for (int i=0;i<64;i++){ if (float(i)>=a && float(i)<b) s += bin(i); }
    return s/n;
}

void fragment(){
    vec2 uv = UV * 2.0 - 1.0;
    uv.x *= aspect;
    float t = TIME;

    float low  = enable_audio ? band(0.0, 10.0) * audio_gain : 0.0;
    float mid  = enable_audio ? band(10.0, 28.0) * audio_gain : 0.0;
    float high = enable_audio ? band(28.0, 56.0) * audio_gain : 0.0;

    // Polar coords
    float r = length(uv);
    float a = atan(uv.y, uv.x);

    // Optional waveform micro-wobble of depth
    float wf = texture(waveform_tex, vec2(fract(t * 0.3), 0.5)).r;
    wf = (wf * 2.0 - 1.0) * 0.15;

    float z = depth_scroll * t + 0.25 * mid + 0.05 * wf;
    float twist = twist_base + 1.2 * low;

    float k = enable_audio ? smoothstep(0.0, 1.0, kick) : 0.0;
    float r2 = r * (1.0 - 0.20 * k) + 0.05 * k;

    float bands = clamp(ribbon_density, 1.0, 16.0);
    float accum = 0.0;
    float glow  = 0.0;

    for (int i = 0; i < 16; i++){
        if (float(i) >= bands) break;
        float phase = float(i) * 1.5707963;

        float ang = a + twist * r2 + 1.2 * z + phase + 0.35 * sin(6.0 * r2 + 3.0 * t + 2.0 * mid);
        float width = mix(0.22, 0.10, clamp(high, 0.0, 1.0));
        float s = sin(ang);
        float bandv = 1.0 - smoothstep(0.0, width, abs(s));
        float df = exp(-2.5 * r2);

        accum += bandv * df;
        glow  += bandv * df * (0.6 + 0.6 * high);
    }

    accum = clamp(accum, 0.0, 1.5);
    glow  = clamp(glow,  0.0, 1.5);

    float core = accum * (0.7 + 0.6 * level * audio_gain);
    float rim  = glow  * (0.6 + 0.6 * high);

    vec3 col = core * core_color + rim * rim_color;

    float vig = smoothstep(1.2, 0.3, length(uv));
    col *= vig;

    COLOR = vec4(col, 1.0);
}
