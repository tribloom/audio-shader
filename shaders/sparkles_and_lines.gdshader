shader_type canvas_item;
render_mode unshaded;

uniform bool audio_enabled = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform float spectrum_u = 0.7;
uniform float audio_gain = 4.0;

uniform float speed = 0.4;
uniform float sparkle_gain = 1.0;
uniform float gradient_center = 0.15;
uniform float gradient_strength = 1.0;
uniform float overall_gain = 1.0;
uniform vec2  manual_offset = vec2(0.0);
uniform float aspect = 1.7777;

float S(float a, float b, float t){
    return smoothstep(a, b, t);
}

float DistLine(vec2 p, vec2 a, vec2 b){
    vec2 pa = p - a;
    vec2 ba = b - a;
    float t = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * t);
}

float N21(vec2 p){
    p = fract(p * vec2(233.34, 851.73));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

vec2 N22(vec2 p){
    float n = N21(p);
    return vec2(n, N21(p + n));
}

vec2 GetPos(vec2 id, vec2 offs){
    vec2 n = N22(id + offs);
    return offs + sin(n * speed * TIME) * 0.4;
}

float Line(vec2 p, vec2 a, vec2 b){
    float d = DistLine(p, a, b);
    float m = S(0.03, 0.01, d);
    float d2 = length(a - b);
    m *= S(1.0, 0.0, d2) * 0.5 + S(0.05, 0.03, abs(d2 - 0.75));
    return m;
}

float Layer(vec2 uv){
    float m = 0.0;
    vec2 gv = fract(uv) - 0.5;
    vec2 id = floor(uv);

    vec2 p[9];
    int idx = 0;
    for (int y = -1; y <= 1; y++){
        for (int x = -1; x <= 1; x++){
            p[idx] = GetPos(id, vec2(float(x), float(y)));
            idx++;
        }
    }

    for (int i = 0; i < 9; i++){
        m += Line(gv, p[4], p[i]);

        vec2 j = (p[i] - gv) * 20.0;
        float sparkle = 1.0 / max(dot(j, j), 1e-4);
        float flicker = sin(speed * TIME + fract(p[i].x) * 10.0) * 0.4 + 0.4;
        m += sparkle_gain * sparkle * flicker;
    }

    m += Line(gv, p[1], p[3]);
    m += Line(gv, p[1], p[5]);
    m += Line(gv, p[5], p[7]);
    m += Line(gv, p[7], p[3]);

    return m;
}

float sample_fft(){
    if (!audio_enabled){
        return 1.0;
    }
    float u = clamp(spectrum_u, 0.0, 1.0);
    float v = textureLod(spectrum_tex, vec2(u, 0.5), 0.0).r;
    return clamp(v * audio_gain, 0.0, 4.0);
}

void fragment(){
    vec2 q = vec2(UV.x, 1.0 - UV.y);
    vec2 uv = vec2((q.x - 0.5) * aspect, (q.y - 0.5));

    float t = TIME * speed * 0.1;
    float s = sin(t);
    float c = cos(t);
    vec2 uv_rot = vec2(c * uv.x - s * uv.y, s * uv.x + c * uv.y);
    vec2 offset_rot = vec2(c * manual_offset.x - s * manual_offset.y,
            s * manual_offset.x + c * manual_offset.y);

    float m = 0.0;
    for (int k = 0; k <= 4; k++){
        float i = float(k) / 4.0;
        float z = fract(i + t);
        float size = mix(10.0, 0.5, z);
        float fade = S(0.0, 0.5, z) * S(1.2, 0.8, z);
        m += Layer(uv_rot * size + i * 20.0 - offset_rot) * fade;
    }

    float fft = sample_fft();
    vec3 base = sin((t * t + 100.0) * vec3(0.345, 0.456, 0.657)) * 0.4 + 0.6;

    vec3 col = base * m;
    float gradient = (uv_rot.y - gradient_center) * gradient_strength * fft;
    col -= gradient * base;
    col *= overall_gain;
    col = clamp(col, 0.0, 1.0);

    COLOR = vec4(col, 1.0);
}