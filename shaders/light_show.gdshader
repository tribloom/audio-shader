shader_type canvas_item;
render_mode unshaded;

/* -----------------------------
   AUDIO UNIFORMS (existing)
------------------------------*/
uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 1.0;

/* -----------------------------
   SCENE / CONTROL UNIFORMS
------------------------------*/
uniform float aspect = 1.7778;
uniform float base_brightness = 1.10;
uniform float glow_size = 0.018;
uniform float pulse_amount = 0.28;

/* "Around the head" sweep + spirograph tunnel */
uniform float head_radius = 0.28;        // circle radius around viewer's head
uniform float sweep_rate = 0.55;         // how fast hands orbit around head
uniform float tunnel_rate = 1.25;        // spirograph radial modulation
uniform float tunnel_depth = 0.16;       // how far inward the tunnels come
uniform float lift = 0.02;               // slight vertical lift (sit face-to-face)

/* Hand + fingertips (baton feel) */
uniform int hands = 2;                   // 1 or 2 hands
uniform int fingers_per_hand = 5;        // LEDs per hand (like fingertips)
uniform float finger_spread = 0.050;     // spacing along the hand/baton
uniform float hand_width = 0.90;         // stretch offsets along hand direction

/* Trails (temporal taps, no backbuffer) */
uniform int trail_samples = 20;          // temporal taps per point (<= MAX_SAMPLES)
uniform float trail_spread = 0.45;       // seconds of look-back across taps
uniform float trail_decay = 0.85;        // per-tap brightness falloff
uniform float tap_bias = 2.2;            // >1 = denser near “now”, sharper leading edge

/* Motion nuance */
uniform float micro_jitter = 0.010;      // tiny hand tremor
uniform float stretch_gain = 0.015;      // velocity-based elongation
uniform float baton_arc_bias = 0.25;     // extra curvature like baton twirls

/* Randomization */
uniform float seed = 123.0;

/* Palette (steady; no audio coloring) */
uniform vec3 col_a = vec3(0.10, 0.85, 1.00);
uniform vec3 col_b = vec3(1.00, 0.25, 0.65);
uniform vec3 col_c = vec3(0.75, 0.95, 0.30);
uniform vec3 col_d = vec3(0.60, 0.50, 1.00);

/* Internal caps */
const int MAX_LIGHTS = 12;    // total across both hands (fingers_per_hand * hands)
const int MAX_SAMPLES = 32;

/* -----------------------------
   Small helpers
------------------------------*/
float h11(float x){
    return fract(sin(x * 127.531 + 0.3183) * 43758.5453);
}
vec2 h12(float x){
    float a = h11(x);
    float b = h11(x + 19.19);
    return vec2(a, b);
}
vec3 palette(float t){
    vec3 p1 = mix(col_a, col_b, smoothstep(0.0, 0.33, t));
    vec3 p2 = mix(col_b, col_c, smoothstep(0.33, 0.66, t));
    vec3 p3 = mix(col_c, col_d, smoothstep(0.66, 1.0,  t));
    if (t < 0.33) return p1;
    else if (t < 0.66) return mix(col_b, p2, (t - 0.33) / 0.33);
    else return mix(col_c, p3, (t - 0.66) / 0.34);
}

float low_amp(){
    if (!audio_enabled) return 0.0;
    int bins = min(bar_count, 16);
    float sum = 0.0;
    for (int i = 0; i < 16; i++){
        if (i >= bins) break;
        float y = (float(i) + 0.5) / float(max(bar_count, 1));
        sum += texture(spectrum_tex, vec2(0.5, y)).r;
    }
    float avg = sum / float(max(bins, 1));
    return clamp(avg * audio_gain, 0.0, 4.0);
}

float glow(vec2 uv, vec2 center, float size){
    vec2 d = uv - center;
    float r2 = dot(d, d) / (size * size);
    return exp(-r2 * 3.5);
}

float biased_back(int s, int S){
    float u = float(s) / float(max(S - 1, 1));
    return pow(u, tap_bias);
}

/* -----------------------------
   Baton / Hand motion model
------------------------------*/

/* Hand center follows a circle around the viewer’s head, with a spirograph “tunnel” in front */
vec2 hand_center(float t, float hand_index){
    float angle = t * sweep_rate * 6.28318 + hand_index * 3.14159; // opposite sides by default
    float r = head_radius;

    /* spirograph tunnel modulation: pull inward when facing front (angle ~ 0 or pi) */
    float tunnel = sin(t * tunnel_rate * 6.28318 + hand_index * 0.37);
    float front_factor = 0.5 * (1.0 + cos(angle)); // ~1.0 near angle=0 (front), ~0.0 near pi (back)
    r -= tunnel_depth * tunnel * front_factor;

    /* base circular sweep */
    vec2 c = vec2(cos(angle), sin(angle)) * r;

    /* slight vertical lift to feel face-height */
    c.y += lift;

    /* baton arc bias: pushes paths outward side-on, like twirling around the ears */
    c.x += baton_arc_bias * sin(angle * 2.0);

    /* tiny jitter */
    vec2 j = (h12(t * 11.73 + hand_index * 7.1) - 0.5) * 2.0 * micro_jitter;
    return c + j;
}

/* Direction tangent for the hand path (used to align the “baton” / finger row) */
vec2 hand_tangent(float t, float hand_index){
    float dt = 0.012;
    vec2 p0 = hand_center(t - dt, hand_index);
    vec2 p1 = hand_center(t + dt, hand_index);
    vec2 v = normalize(p1 - p0);
    return v;
}

/* Fingertip offsets: arranged along the hand/baton direction, centered around middle finger */
vec2 finger_offset(int finger_idx, vec2 tangent){
    float k = float(finger_idx) - 0.5 * float(fingers_per_hand - 1);
    vec2 along = tangent * k * finger_spread * hand_width;
    /* very slight bow perpendicular to tangent to emulate knuckle curve */
    vec2 perp = vec2(-tangent.y, tangent.x) * (k * k) * 0.0025;
    return along + perp;
}

/* Fingertip position */
vec2 fingertip_pos(float t, float hand_index, int finger_idx){
    vec2 c = hand_center(t, hand_index);
    vec2 tan = hand_tangent(t, hand_index);
    vec2 p = c + finger_offset(finger_idx, tan);
    return p;
}

/* -----------------------------
   MAIN
------------------------------*/
void fragment(){
    vec2 uv = (UV - vec2(0.5)) * vec2(1.0, aspect);

    float amp = low_amp();
    float pulse = 1.0 + pulse_amount * amp;
    float size = glow_size * pulse;

    vec3 col = vec3(0.0);
    float t = TIME;

    int H = hands;
    if (H < 1) H = 1;
    if (H > 2) H = 2;

    int F = fingers_per_hand;
    if (F < 1) F = 1;
    if (F > MAX_LIGHTS) F = MAX_LIGHTS;

    int S = trail_samples;
    if (S > MAX_SAMPLES) S = MAX_SAMPLES;

    /* color phase per finger to give subtle variety across the hand */
    for (int h = 0; h < 2; h++){
        if (h >= H) break;

        for (int f = 0; f < MAX_LIGHTS; f++){
            if (f >= F) break;

            /* steady slow color cycle, distinct per hand/finger */
            float hue_t = fract(t * 0.035 + float(h) * 0.11 + float(f) * 0.07);
            vec3 lcol = palette(hue_t);

            /* velocity estimate for directional stretch */
            vec2 p_now = fingertip_pos(t, float(h), f);
            vec2 p_prev = fingertip_pos(t - 0.015, float(h), f);
            vec2 v = normalize(p_now - p_prev);

            float fade = 1.0;

            for (int s = 0; s < MAX_SAMPLES; s++){
                if (s >= S) break;

                float back = biased_back(s, S);      // 0..1, denser near now
                float dt = back * trail_spread;

                vec2 p = fingertip_pos(t - dt, float(h), f);

                /* velocity-based elongation (whip hits) strongest near leading edge */
                float lead = 1.0 - back;
                vec2 stretch = v * stretch_gain * (1.0 + 2.0 * lead);

                float g = glow(uv, p + stretch, size * (1.0 + 0.45 * lead));
                col += lcol * g * fade;

                fade *= trail_decay;
            }
        }
    }

    col *= base_brightness;

    /* soft clamp for nice highlights */
    col = col / (vec3(1.0) + col);

    COLOR = vec4(col, 1.0);
}
