shader_type canvas_item;

// Uses the same 1xN spectrum texture (R=current, G=peak optional)
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float aspect = 1.7777;

// Style
uniform float line_thickness = 0.01; // in UV
uniform float gamma = 0.85;
uniform bool  fill_under = true;
uniform vec3  line_color = vec3(1.0, 0.95, 0.8);
uniform vec3  fill_color = vec3(0.08, 0.12, 0.18);
uniform float hue_shift = 0.0; // optional frequency tint

vec3 hsv2rgb(vec3 c){
    vec4 K = vec4(1., 2./3., 1./3., 3.);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6. - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0., 1.), c.y);
}

float sample_mag(float u){
    // u in [0,1], continuous index across [0..bar_count-1]
    float fb = float(bar_count);
    float idx = u * (fb - 1.0);
    float i0 = floor(idx);
    float t  = fract(idx);
    float tx0 = (i0 + 0.5) / fb;
    float tx1 = (min(i0 + 1.0, fb - 1.0) + 0.5) / fb;
    float h0 = texture(spectrum_tex, vec2(tx0, 0.5)).r;
    float h1 = texture(spectrum_tex, vec2(tx1, 0.5)).r;
    return mix(h0, h1, t);
}

void fragment(){
    vec2 uv = UV;
    float u = clamp(uv.x, 0.0, 1.0);
    float v = 1.0 - clamp(uv.y, 0.0, 1.0); // bottom = 0

    float h = pow(clamp(sample_mag(u), 0.0, 1.0), gamma);

    // Line mask
    float d = abs(v - h);
    float aa = fwidth(v) * 1.5 + line_thickness * 0.5;
    float line_mask = 1.0 - smoothstep(line_thickness + aa, aa, d);

    // Optional fill under curve
    float fill_mask = fill_under ? smoothstep(0.0, fwidth(v) * 1.5, h - v) : 0.0;

    // Subtle frequency tint along X
    float f = u + hue_shift;
    vec3 tint = hsv2rgb(vec3(fract(f), 1.0, 1.0));

    vec3 col = line_color * line_mask + fill_color * fill_mask;
    col = mix(col, tint, 0.15 * line_mask); // tint mainly the line

    float alpha = max(line_mask, fill_mask);
    COLOR = vec4(col, alpha);
}
