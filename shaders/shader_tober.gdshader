shader_type canvas_item;

/* === your exact uniforms === */
uniform bool enable_audio = true;
uniform float aspect = 1.7778;
uniform sampler2D spectrum_tex;   // 64 bins across X, sample y=0.5
uniform sampler2D waveform_tex;   // (unused here)
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

/* === constants (match Shadertoy) === */
uniform float ITER = 64.0;
uniform float hit_epsilon = 0.001;
uniform float bass_max = 0.75;

/* === audio: iChannel0 → your spectrum_tex === */
float spectrum_sample(float x01){
    // x in [0,1] over 64 bins; sample at row y=0.5
    x01 = clamp(x01, 0.0, 1.0);
    return texture(spectrum_tex, vec2(x01, 0.5)).r * audio_gain;
}

// Shadertoy used: #define megabass (texture(iChannel0, vec2(0.001,0.25)).x)
float megabass(){
    if (!enable_audio) return 0.0;
    // 0.001 is basically the first FFT bin
    return spectrum_sample(0.001);
}

/* === small helpers === */
float hash21(vec2 x){
    return fract(sin(dot(x, vec2(12.4, 14.1))) * 1245.4);
}

vec2 moda(vec2 p, float per){
    float a = atan(p.y, p.x);
    float l = length(p);
    a = mod(a - per*0.5, per) - per*0.5;
    return vec2(cos(a), sin(a)) * l;
}

// robust 2D rotate (avoid mat2 constructor differences)
vec2 rotate(vec2 v, float a){
    float c = cos(a), s = sin(a);
    return vec2(c*v.x - s*v.y, s*v.x + c*v.y);
}

float smin(float a, float b, float k){
    float res = exp(-k*a) + exp(-k*b);
    return -log(res) / k;
}

float sphe(vec3 p, float r){ return length(p) - r; }
float cyl(vec2 p, float r){  return length(p) - r; }

/* === scene SDFs === */
float needles(vec3 p){
    vec3 pp = p;
    float l_needle = 0.8 - clamp(megabass(), 0.0, bass_max);

    // set 1
    p.xz = moda(p.xz, 2.0*PI/7.0);
    float n1 = cyl(p.yz, 0.1 - p.x*l_needle);

    // set 2
    p = pp;
    p.y = abs(p.y);
    p.y -= 0.1;
    p.xz = moda(p.xz, 2.0*PI/7.0);
    p.xy = rotate(p.xy, PI/4.5);
    float n2 = cyl(p.yz, 0.1 - p.x*l_needle);

    // set 3
    p = pp;
    float n3 = cyl(p.xz, 0.1 - abs(p.y)*l_needle);

    return min(n3, min(n2, n1));
}

float spikyball(vec3 p){
    p.y  -= TIME;
    p.xz  = rotate(p.xz, TIME);
    p.yz  = rotate(p.yz, TIME*0.5);
    float s = sphe(p, 0.9);
    return smin(s, needles(p), 5.0);
}

// provided by Shane (ported)
float room(vec3 p){
    p += sin(p.yzx - cos(p.zxy));
    p += sin(p.yzx/1.5 + cos(p.zxy)/2.0) * 0.5;
    return -length(p.xz) + 5.0;
}

float SDF(vec3 p){
    return min(spikyball(p), room(p));
}

/* === fragment (raymarch) === */
void fragment(){
    // Shadertoy uv: (2*fragCoord - iRes)/iRes.y
    // Here: center UV and fix aspect; no screen size needed.
    vec2 uv = UV * 2.0 - 1.0;
    uv.x *= aspect;

    float dither = hash21(uv);

    // camera
    vec3 ro  = vec3(0.001, 0.001 + TIME, -3.0);
    vec3 dir = normalize(vec3(uv, 1.0));
    vec3 p   = ro;

    float shad = 0.0;

    // sphere tracing
    for (float i = 0.0; i < ITER; i += 1.0){
        float d = SDF(p);
        if (d < hit_epsilon){
            shad = i / ITER;
            break;
        }
        d *= (0.9 + dither*0.1);
        p += d * dir;
    }

    vec3 c = vec3(shad);
    // gamma-ish lift like ST pow(c, vec3(1.5))
    c = pow(c, vec3(1.5));

    // optional: let your overall level add a little energy
    c *= 0.9 + 0.3 * level * audio_gain;

    COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
