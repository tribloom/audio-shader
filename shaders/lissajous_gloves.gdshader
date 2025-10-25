shader_type canvas_item;

uniform bool enable_audio = true;
uniform float aspect = 1.7778;
uniform sampler2D spectrum_tex;
uniform sampler2D waveform_tex;
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

uniform vec3 col_a : source_color = vec3(0.90, 0.98, 1.00);
uniform vec3 col_b : source_color = vec3(0.40, 0.80, 1.00);
uniform float bg_dim = 0.08;
uniform float trail_softness = 0.020;   // smaller = crisper
uniform float trail_count = 4.0;        // copies per “hand”
uniform float lissa_a = 3.0;            // base a:b
uniform float lissa_b = 2.0;
uniform float swirl = 0.45;             // field swirl

float sbin(int i){
    float x = (float(i) + 0.5) / 64.0;
    return texture(spectrum_tex, vec2(x, 0.5)).r;
}
float band(float i0, float i1){
    float lo = floor(i0);
    float hi = ceil(i1);
    float n = max(1.0, (hi - lo));
    float s = 0.0;
    for (int i = 0; i < 64; i++){
        if (float(i) >= lo && float(i) < hi) s += sbin(i);
    }
    return s / n;
}
float wsample(float x01){
    // Safe waveform sample. If missing, returns 0.0.
    return texture(waveform_tex, vec2(clamp(x01,0.0,1.0), 0.5)).r * 2.0 - 1.0;
}
mat2 rot(float a){
    float c = cos(a), s = sin(a);
    return mat2(vec2(c, -s), vec2(s, c));
}
float line_dist(vec2 p, vec2 a, vec2 b){
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}

void fragment(){
    vec2 uv = UV * 2.0 - 1.0;
    uv.x *= aspect;

    // Swirl the field slightly for hand-like movement
    uv *= rot(swirl * uv.y);

    float t = TIME;

    // Audio features
    float low  = enable_audio ? band(0.0, 8.0)  * audio_gain : 0.0;
    float mid  = enable_audio ? band(8.0, 24.0) * audio_gain : 0.0;
    float high = enable_audio ? band(24.0, 56.0)* audio_gain : 0.0;

    // Waveform adds micro-jitter to segments (feels “human”)
    float wf = enable_audio ? wsample(fract(0.1 * t)) : 0.0;

    float a = lissa_a + 1.2 * low;
    float b = lissa_b + 0.8 * mid;
    float speed = 0.8 + 1.4 * high + 0.5 * kick;

    float width = trail_softness * (1.0 - 0.35 * high);
    width *= mix(1.0, 0.55, clamp(level * audio_gain, 0.0, 1.0));

    vec3 col = vec3(bg_dim);
    int hands = 2;

    for (int h = 0; h < 2; h++){
        float ph = float(h) * 1.5707963 + 0.30 * mid;
        float whip = enable_audio ? (0.28 * kick) : 0.0;

        int copies = int(clamp(trail_count, 1.0, 8.0));
        for (int cpy = 0; cpy < 8; cpy++){
            if (cpy >= copies) break;
            float lag = float(cpy) * 0.12;
            float tt = t * speed - lag;

            // Lissajous center path
            vec2 c = vec2(sin(a * tt + ph), sin(b * tt + ph + 1.0));
            c *= rot(0.18 * low + 0.14 * mid);
            c *= 0.55 + 0.15 * level * audio_gain;

            // Local direction + tiny waveform wobble
            vec2 d = normalize(vec2(a*cos(a*tt + ph), b*cos(b*tt + ph + 1.0)) + 1e-3);
            d *= (1.0 + 0.05 * wf);
            vec2 p0 = c - d * (0.22 + whip);
            vec2 p1 = c + d * (0.22 + whip);

            float dline = line_dist(uv, p0, p1);
            float alpha = exp(-pow(dline / width, 2.0));

            vec3 base = mix(col_a, col_b, float(h));
            float copy_bias = 1.0 - float(cpy) / max(1.0, float(copies - 1));
            float intensity = (0.72 + 0.62 * level * audio_gain) * (0.72 + 0.28 * copy_bias);

            col += base * alpha * intensity;
        }
    }

    COLOR = vec4(col, 1.0);
}
