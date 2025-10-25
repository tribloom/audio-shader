shader_type canvas_item;

uniform bool enable_audio = true;
uniform float aspect = 1.7778;
uniform sampler2D spectrum_tex;
uniform sampler2D waveform_tex; // optional
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

uniform vec3 cell_color : source_color = vec3(0.9, 0.95, 1.0);
uniform vec3 line_color : source_color = vec3(0.15, 0.30, 0.55);
uniform float grid_scale = 2.8;
uniform float line_thickness = 0.035;
uniform float warp_amp = 0.10;

float bin(int i){ float x=(float(i)+0.5)/64.0; return texture(spectrum_tex, vec2(x,0.5)).r; }
float band(float a, float b){
    float n = max(1.0, b-a), s=0.0;
    for (int i=0;i<64;i++){ if (float(i)>=a && float(i)<b) s += bin(i); }
    return s/n;
}
mat2 rot(float r){ float c=cos(r), s=sin(r); return mat2(vec2(c,-s), vec2(s,c)); }

float sdHex(vec2 p, float r){
    p = abs(p);
    return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x) - r;
}

vec2 hexCenter(vec2 p, float r){
    // Map p to center of nearest hex (approx)
    const float k = 1.7320508;
    vec2 q = vec2(p.x * 2.0 / k, (p.y + p.x / k) * 2.0 / 3.0);
    vec2 i = floor(q + 0.5);
    vec2 f = q - i;
    if (abs(f.x) + abs(f.y) > 1.0) i += vec2(step(0.0, f.x), step(0.0, f.y)) - vec2(1.0);
    vec2 center = vec2(i.x + i.y * 0.5, i.y) * vec2(k * 0.5, 1.5);
    return p - center * r;
}

void fragment(){
    vec2 uv = UV * 2.0 - 1.0;
    uv.x *= aspect;
    float t = TIME;

    float lows  = enable_audio ? band(0.0, 10.0) * audio_gain : 0.0;
    float mids  = enable_audio ? band(10.0, 28.0) * audio_gain : 0.0;
    float highs = enable_audio ? band(28.0, 56.0) * audio_gain : 0.0;

    // Optional waveform -> tiny phase drift
    float wf = texture(waveform_tex, vec2(fract(t * 0.2), 0.5)).r;
    wf = (wf * 2.0 - 1.0) * 0.02;

    vec2 u = uv;
    u += warp_amp * vec2(
        sin(3.1 * u.y + 0.9 * t + 2.0 * mids + wf),
        cos(3.4 * u.x + 0.8 * t + 1.6 * mids - wf)
    );

    float base_r = 0.62 + 0.10 * level * audio_gain;
    float r = base_r * (1.0 + 0.06 * sin(2.0 * t + 3.0 * lows));
    float shock = enable_audio ? smoothstep(0.0, 1.0, kick) : 0.0;

    float scale = grid_scale;
    vec2 p = u * scale;
    vec2 hp = hexCenter(p, 1.0);
    float d = sdHex(hp, r);

    float edge = smoothstep(line_thickness, 0.0, abs(d));

    // Shock ring from center
    float rr = length(u) * scale;
    float pr = fract(0.20 * t + 0.25 * highs);
    float w = 0.05 + 0.10 * highs;
    float ring = smoothstep(0.5, 0.0, abs(rr - (1.0 + pr * 2.5)) / w) * (0.8 * shock);

    vec3 base = mix(line_color, cell_color, edge);
    base += ring * cell_color;
    base *= 0.9 + 0.2 * highs;

    COLOR = vec4(base, 1.0);
}
