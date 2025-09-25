shader_type canvas_item;

/*
UNIVERSE (perspective fractal, audio-reactive)
Expects from GDScript:
  spectrum_tex (1xN, R=current, G=peak), bar_count, aspect
  kick_in, kick_env, ring_age
*/

uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float aspect = 1.25;

/* Artistic controls */
uniform float time_scale = 1.0;
uniform float brightness = 1.0;
uniform float gamma_curve = 1.2;

/* Iterations */
uniform int steps = 56;  // <= 72
uniform int folds = 6;   // <= 7
const int MAX_STEPS = 72;
const int MAX_FOLDS = 7;

/* Audio inputs */
uniform float kick_in  = 0.0;
uniform float kick_env = 0.0;
uniform float ring_age = 1.0;

/* Ring */
uniform float ring_near  = 0.10;
uniform float ring_far   = 0.98;
uniform float ring_width = 0.12;
uniform float ring_gain  = 0.9;
uniform float bloom_gain = 0.55;

/* Spectrum helpers */
float spec_at(float u){
    float fb = float(bar_count);
    float idx = clamp(u, 0.0, 1.0) * max(1.0, fb - 1.0);
    float i0 = floor(idx);
    float t  = fract(idx);
    float tx0 = (i0 + 0.5) / fb;
    float tx1 = (min(i0 + 1.0, fb - 1.0) + 0.5) / fb;
    float h0 = texture(spectrum_tex, vec2(tx0, 0.5)).r;
    float h1 = texture(spectrum_tex, vec2(tx1, 0.5)).r;
    return mix(h0, h1, t);
}
float band_max(float u0, float u1){
    int taps = 8;
    float m = 0.0;
    for (int i = 0; i < taps; i++){
        float t = float(i)/float(taps - 1);
        m = max(m, spec_at(mix(u0, u1, t)));
    }
    return m;
}

/* Utils */
mat2 rot2(float a){
    float c = cos(a), s = sin(a);
    return mat2(vec2(c, s), vec2(-s, c)); // Godot 4 columns
}

void fragment(){
    vec2 uv = UV - 0.5;
    vec2 uv_aspect = uv * vec2(aspect, 1.0);

    float r_scale = length(vec2(aspect * 0.5, 0.5));
    float r_norm = length(uv_aspect) / max(1e-6, r_scale);

    float iTime = TIME * time_scale;

    float bass = band_max(0.02, 0.13);
    float mid  = band_max(0.30, 0.60);
    float high = band_max(0.75, 0.98);

    float t = iTime * 0.1
            + ((0.25 + 0.05 * sin(iTime * 0.1 + 2.0*high))
               / (length(uv_aspect) + 0.07)) * 2.2;
    t += 0.10 * bass + 0.20 * kick_env;

    float si = sin(t), co = cos(t);
    mat2 ma = mat2(vec2(co, si), vec2(-si, co));

    float v1 = 0.0;
    float v2 = 0.0;
    float v3 = 0.0;
    float s = 0.0;

    for (int i = 0; i < MAX_STEPS; i++){
        if (i >= steps) break;

        vec3 p = s * vec3(uv_aspect, 0.0);
        p.xy *= ma;
        p += vec3(0.22, 0.30,
                  s - 1.5 - sin(iTime * 0.13) * 0.1 - 0.2*bass);

        for (int j = 0; j < MAX_FOLDS; j++){
            if (j >= folds) break;
            float d = max(dot(p, p), 1e-6);
            p = abs(p) / d - 0.659;
        }

        float pp = dot(p, p);
        float luv = length(uv_aspect);

        v1 += pp * 0.0015 * (1.8 + sin(luv * 13.0 + 0.5  - iTime * 0.2 + 2.2*bass));
        v2 += pp * 0.0013 * (1.5 + sin(luv * 14.5 + 1.2  - iTime * 0.3 + 1.7*mid ));
        v3 += length(p.xy * 10.0) * 0.0003 * (1.0 + 0.5*high);

        s += 0.035 * (1.0 + 0.6*bass + 0.3*kick_in);
    }

    float len_uv = length(uv_aspect);
    v1 *= smoothstep(0.75, 0.0, len_uv);
    v2 *= smoothstep(0.55, 0.0, len_uv);
    v3 *= smoothstep(0.95, 0.0, len_uv);

    vec3 col = vec3(
        v3 * (1.5 + sin(iTime * 0.2) * 0.4),
        (v1 + v3) * 0.30,
        v2
    );

    col = mix(col, vec3(1.0), bloom_gain * clamp(kick_env, 0.0, 1.0));

    float rr = mix(ring_near, ring_far, clamp(ring_age, 0.0, 1.0));
    float ring = exp(-pow((r_norm - rr) / max(0.02, ring_width), 2.0));
    col += vec3(ring) * (ring_gain * clamp(kick_env, 0.0, 1.0));

    col = min(pow(max(vec3(0.0), col) * max(1e-3, brightness), vec3(gamma_curve)), vec3(1.0));
    COLOR = vec4(col, 1.0);
}
