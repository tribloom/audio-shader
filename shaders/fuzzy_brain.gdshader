shader_type canvas_item;

/* ---------- Optional audio inputs ---------- */
uniform bool enable_audio = true;
uniform float volume_env = -1.0;          // if your framework has overall loudness (0..1); leave <0 to auto-compute from spectrum
uniform sampler2D spectrum_tex;
uniform int bar_count;

/* Loudness → speed mapping (multiplies TIME) */
uniform float flow_speed = 1.0;           // base speed
uniform float flow_min = 0.6;             // speed factor at silence
uniform float flow_max = 2.0;             // speed factor at max loudness
uniform float flow_curve = 0.9;           // <1 responds more at low volumes

/* Look controls */
uniform float scale = 7.0;                // pattern zoom
uniform float gamma_correction = 2.2;     // final gamma

/* --------- Helpers --------- */
vec2 rand(vec2 p){
    vec2 q = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

vec3 paletteIQ(float t){
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.45, 0.25, 0.14);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.0, 0.1, 0.2);
    vec3 x = c * t + d;
    vec3 col = a + b * cos(TAU * x);
    return col;
}

float spectrum_mean(){
    int n = max(1, bar_count);
    int taps = 64;
    float sum = 0.0;
    for (int i = 0; i < 64; i++){
        float t = float(i) / float(taps - 1);
        float x = (t * float(n - 1) + 0.5) / float(n);
        sum += texture(spectrum_tex, vec2(x, 0.5)).r;
    }
    float m = sum / float(taps);
    return clamp(m, 0.0, 1.0);
}

/* --------- Fragment --------- */
void fragment(){
    /* Shadertoy-like coords */
    vec2 res = vec2(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);
    vec2 fragCoord = UV * res;
    vec2 uv = (fragCoord * 2.0 - res) / min(res.x, res.y);

    /* Radial falloff for vignette/contrast (like original _d) */
    float d0 = length(uv) * 0.75;

    /* Loudness → flow speed */
    float loud = volume_env;
    if (loud < 0.0){
        loud = spectrum_mean();
    }
    loud = clamp(loud, 0.0, 1.0);
    float loud_nl = pow(loud, flow_curve);
    float speed_factor = mix(flow_min, flow_max, loud_nl);
    if (!enable_audio){
        speed_factor = 1.0;
    }

    /* Time */
    float t = TIME * flow_speed * speed_factor;

    /* Cell-space */
    vec2 p = (uv * scale) + vec2(t * 1.1, t * 0.75);
    vec2 st1 = floor(p);
    vec2 st2 = fract(p);

    /* Neighborhood search (same logic as original) */
    float mindist = 0.25;
    for (int ix = -1; ix <= 1; ix++){
        for (int iy = -1; iy <= 1; iy++){
            vec2 n = vec2(float(iy), float(ix));
            vec2 off = rand(st1 + n);
            off.x = 0.5 + sin(t + TAU * off.x) * 0.5;
            off.y = 0.5 + sin(t + TAU * off.y) * 0.5;
            vec2 pos = n + off - st2;
            float d = length(pos);
            mindist = min(mindist, mindist * d);
        }
    }

    /* Palette + radial shaping */
    vec3 col = paletteIQ(mindist * 15.5);
    col *= d0 * d0;

    /* Gamma */
    col = pow(col, vec3(1.0 / gamma_correction));

    COLOR = vec4(col, 1.0);
}
