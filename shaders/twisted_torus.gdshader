shader_type canvas_item;

const int   MAX_STEPS = 400;
const float FAR_CLIP  = 50.0;
const float EPSILON   = 0.00001;
const float LOG_CUT   = 1e5;
const float PI_CONST  = 3.14159265;

uniform float aspect        = 1.7777;
uniform float fov           = 1.0;
uniform float cam_base_z    = 4.5;
uniform float cam_bob_amp   = 1.5;
uniform float cam_bob_rate  = 1.25;  // radians per second
uniform float fade_factor   = 0.0125;
uniform float glow_mix      = 0.4;

uniform bool audio_enabled = true;
uniform sampler2D spectrum_tex : hint_default_black;
uniform vec2  audio_band   = vec2(0.05, 0.35);
uniform float audio_gain   = 0.30;
uniform float audio_floor  = 0.05;
uniform float audio_level  = 0.0;
uniform float audio_fallback_mix : hint_range(0.0, 1.0) = 0.08;

float sample_spectrum_band(vec2 band){
    const int TAPS = 8;
    float acc = 0.0;
    for (int k = 0; k < TAPS; k++){
        float t = float(k) / float(max(TAPS - 1, 1));
        float u = clamp(mix(band.x, band.y, t), 0.0, 1.0);
        acc += texture(spectrum_tex, vec2(u, 0.125)).r;
    }
    return acc / float(TAPS);
}

float audio_value(float time_full){
    float sample = clamp(audio_level, 0.0, 1.0);
    if (audio_enabled){
        sample = max(sample, sample_spectrum_band(audio_band));
    }
    float fallback = 0.5 + 0.5 * sin(time_full * 0.8);
    sample = mix(fallback, sample, audio_enabled ? 1.0 : 0.0);
    // even when audio is active, keep a faint fallback for idle moments
    sample = max(sample, audio_fallback_mix * fallback);
    return clamp(sample, 0.0, 1.0);
}

void rotate(inout vec2 v, float angle){
    float c = cos(angle);
    float s = sin(angle);
    v = vec2(c * v.x + s * v.y, -s * v.x + c * v.y);
}

vec3 camera(vec2 uv){
    vec3 forward = vec3(0.0, 0.0, -1.0);
    vec3 right   = vec3(1.0, 0.0, 0.0);
    vec3 up      = vec3(0.0, 1.0, 0.0);
    return normalize(uv.x * right + uv.y * up + fov * forward);
}

float scene(vec3 p, float time_full, float audio_drv, inout vec3 ret_col, inout vec3 h){
    float mind = 1e5;

    p.z += 25.0;
    rotate(p.xz, 1.57 - 0.5 * time_full);
    rotate(p.yz, 1.57 - 0.5 * time_full);

    float var = atan(p.x, p.y);
    vec2 q = vec2(length(p.xy) - 9.0, p.z);
    rotate(q, var * 0.75 + time_full * 0.4);

    vec2 oq = q;

    q = abs(q) - vec2(3.0) - sin(q) * 7.0;

    float twist = 3.3;
    float s = time_full;
    if (oq.x < q.x && oq.y > q.y){
        rotate(q, ((var * twist) + s) * PI_CONST + s);
    } else {
        rotate(q, (0.28 - (var * twist) + s) * PI_CONST + s);
    }

    float oldvar = var;
    ret_col = vec3(1.0) - vec3(0.350, 0.2, 0.3);

    q *= 0.2;

    float wave = sin(oldvar - time_full);
    float freq = sin(oldvar - 2.0 * time_full + PI_CONST);
    float freq2 = sin(oldvar - 2.0 * time_full);

    mind = length(q) + 0.5 + 1.05 * (length(fract(q * 0.5 * (3.0 + 3.0 * wave)) - 0.5) - 1.215);

    float denom1 = 0.051 + pow(mind - freq * 0.125, 2.0);
    h -= vec3(-3.20, 0.20, 1.0) * 0.0025 / denom1;

    float denom2 = 0.501 + pow(mind - freq2 * 0.5, 2.0);
    h -= vec3(1.20, -0.50, -0.50) * 0.025 / denom2;

    float denom3 = 0.021 + mind * mind;
    h += vec3(0.25, 0.4, 0.5) * 0.0025 / denom3;

    float f = audio_floor + audio_gain * audio_drv;
    h += vec3(f * 0.1 - 0.005);

    return mind;
}

vec2 march(vec3 pos, vec3 dir, float time_full, float audio_drv, inout vec3 ret_col, inout vec3 h){
    vec2 dist = vec2(0.0);
    vec2 result = vec2(0.0);

    for (int i = 0; i < MAX_STEPS; i++){
        vec3 p = pos + dir * dist.y;
        dist.x = scene(p, time_full, audio_drv, ret_col, h);
        dist.y += dist.x * 0.2;
        float log_term = log(dist.y * dist.y / max(dist.x, EPSILON) / LOG_CUT);
        if (log_term > 0.0 || dist.x < EPSILON || dist.y > FAR_CLIP){
            break;
        }
        result.x += 1.0;
    }
    result.y = dist.y;
    return result;
}

void fragment(){
    float time_full = TIME;
    vec2 uv = UV * 2.0 - 1.0;
    uv.x *= aspect;

    vec3 dir = camera(uv);
    vec3 pos = vec3(0.0, 0.0, 0.0);
    pos.z = cam_base_z + cam_bob_amp * sin(time_full * cam_bob_rate);

    vec3 ret_col = vec3(0.0);
    vec3 h = vec3(0.0);

    float audio_drv = audio_value(time_full);
    vec2 inter = march(pos, dir, time_full, audio_drv, ret_col, h);

    vec3 col = ret_col * (1.0 - inter.x * fade_factor);
    col += h * glow_mix;

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}