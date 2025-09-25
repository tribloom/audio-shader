shader_type canvas_item;
render_mode unshaded, blend_mix;

/* Sky + horizon */
uniform vec4 sky_top  : source_color = vec4(0.05, 0.04, 0.10, 1.0);
uniform vec4 sky_bot  : source_color = vec4(0.02, 0.02, 0.06, 1.0);
uniform vec4 glow_col : source_color = vec4(0.85, 0.40, 1.00, 1.0);
uniform float horizon_y    = 0.52;
uniform float glow_strength = 1.25;

/* Stars */
uniform float stars_cols = 180.0;
uniform float stars_brightness = 0.9;

/* Aspect from your script (you already set this on others) */
uniform float aspect = 1.7777;

/* 4 mountain layers (far → near) */
uniform vec4 mcol4 : source_color = vec4(0.62, 0.50, 0.95, 1.0);
uniform vec4 mcol3 : source_color = vec4(0.46, 0.40, 0.92, 1.0);
uniform vec4 mcol2 : source_color = vec4(0.28, 0.30, 0.75, 1.0);
uniform vec4 mcol1 : source_color = vec4(0.10, 0.16, 0.44, 1.0);

uniform float y4 = 0.66;
uniform float a4 = 0.018;
uniform float s4 = 1.3;
uniform float v4 = 0.02; // slowest (furthest)
uniform float y3 = 0.70;
uniform float a3 = 0.025;
uniform float s3 = 1.0;
uniform float v3 = 0.04;
uniform float y2 = 0.75;
uniform float a2 = 0.038;
uniform float s2 = 0.85;
uniform float v2 = 0.07;
uniform float y1 = 0.81;
uniform float a1 = 0.055;
uniform float s1 = 0.70;
uniform float v1 = 0.11; // fastest (nearest)

/* --- tiny 1D fbm for ridges --- */
float h1(float n){ return fract(sin(n)*43758.5453); }
float n1(float x){
    float i = floor(x), f = fract(x);
    float u = f*f*(3.0-2.0*f);
    return mix(h1(i), h1(i+1.0), u);
}
float fbm(float x){
    float a=0.5, f=1.0, s=0.0;
    for (int i=0;i<5;i++){ s += a*n1(x*f); f*=2.03; a*=0.53; }
    return s;
}

float ridge(vec2 uv, float y0, float amp, float scale, float vel, float phase){
    float x = (uv.x*aspect)*scale + TIME*vel + phase;
    return y0 + amp * (fbm(x) - 0.5);
}

vec3 stars(vec2 uv){
    vec3 col = vec3(0.0);
    vec2 grid = vec2(stars_cols, stars_cols / max(aspect, 0.001));
    vec2 st = uv * grid;
    vec2 id = floor(st);
    vec2 f  = fract(st) - 0.5;
    float k = h1(dot(id, vec2(1.0,57.0)));
    if (k > 0.86){
        vec2 j = (vec2(h1(k+11.3), h1(k+7.1)) - 0.5) * 0.6;
        float d = length(f - j);
        float r = 0.08 * (0.6 + 0.8 * h1(k+23.7));
        float star = smoothstep(r, r-0.02, d);
        float tw = 0.7 + 0.3*sin(TIME*6.0 + 5.0*k);
        col += vec3(1.0) * star * stars_brightness * tw;
    }
    return col;
}

void fragment(){
    // Sky gradient + horizon glow
    vec3 col = mix(sky_bot.rgb, sky_top.rgb, clamp(UV.y,0.0,1.0));
    float gy = abs(UV.y - horizon_y);
    col += glow_col.rgb * exp(-pow(gy*8.0,2.0)) * glow_strength;

    // Stars behind mountains
    col += stars(UV);

    // Mountains (paint far → near, so nearer layers overdraw)
    float r4 = ridge(UV, y4, a4, s4, v4, 10.3);
    if (UV.y > r4) col = mcol4.rgb;
    float r3 = ridge(UV, y3, a3, s3, v3, 23.7);
    if (UV.y > r3) col = mcol3.rgb;
    float r2 = ridge(UV, y2, a2, s2, v2, 41.9);
    if (UV.y > r2) col = mcol2.rgb;
    float r1 = ridge(UV, y1, a1, s1, v1, 58.1);
    if (UV.y > r1) col = mcol1.rgb;

    COLOR = vec4(col, 1.0);
}
