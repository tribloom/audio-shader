shader_type canvas_item;

uniform float time_scale : hint_range(0.0, 5.0) = 1.0;
uniform float aspect = 1.7778; // set to your window aspect
uniform float radius = 0.55;
uniform float beams  = 8.0;
uniform float glow   = 0.8;

// driven from GDScript:
uniform float level = 0.0; // wide RMS 0..1
uniform float kick  = 0.0; // bass 0..1

vec3 hsv2rgb(vec3 c){
    vec4 K = vec4(1., 2./3., 1./3., 3.);
    vec3 p = abs(fract(c.xxx + K.xyz)*6. - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0., 1.), c.y);
}

float ring_profile(float d, float r, float w){
    float a = clamp(1.0 - abs(d - r) / max(w, 1e-4), 0.0, 1.0);
    return a*a*(3.0 - 2.0*a);
}

float beam_shape(float a, float t){
    float x = clamp(1.0 - a / max(t, 1e-4), 0.0, 1.0);
    return x*x*(3.0 - 2.0*x);
}

void fragment(){
    vec2 uv = SCREEN_UV;          // 0..1
    vec2 p  = uv * 2.0 - 1.0;     // -1..1
    p.x *= aspect;

    float t = TIME * time_scale * (0.6 + 1.2*level);
    float R = radius * (1.0 + 0.18*level + 0.25*kick);
    float thickness = mix(0.015, 0.06, max(level, kick));
    float beam_th   = mix(0.06,  0.20, level);
    float beam_gain = mix(0.3,   1.5,  max(level, kick));

    float dist = length(p);
    float ang  = atan(p.y, p.x) + t;

    float hue  = fract(ang / (6.28318));
    vec3 base  = hsv2rgb(vec3(hue, 1.0, 1.0));
    float ring = ring_profile(dist, R, thickness);

    float slice = 6.28318 / max(beams, 1.0);
    float k     = floor(ang / slice + 0.5);
    float d0    = abs(ang - k*slice);
    d0 = min(d0, 6.28318 - d0);
    float beam  = beam_shape(d0, beam_th);
    // feather neighbors
    float dL = abs(ang - (k-1.0)*slice); dL = min(dL, 6.28318 - dL);
    float dR = abs(ang - (k+1.0)*slice); dR = min(dR, 6.28318 - dR);
    beam += 0.5*beam_shape(dL, beam_th) + 0.5*beam_shape(dR, beam_th);
    beam *= beam_gain;

    vec3 col = base * ring + base * beam;
    col += glow * ring * vec3(0.9, 0.95, 1.0);
    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
