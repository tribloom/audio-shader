shader_type canvas_item;

// ---- inputs from GDScript ----
uniform sampler2D spectrum_tex;   // 1 x N RG texture: R=bar height, G=peak
uniform int bar_count = 64;
uniform float aspect = 1.7777;

// ---- style controls ----
uniform float gap = 0.15;         // 0..0.45 fraction of bar width reserved as gap
uniform float gamma = 0.85;       // amplitude shaping (visual lift)
uniform bool  color_by_frequency = true;
uniform vec3  color_lo = vec3(0.06, 0.10, 0.20);
uniform vec3  color_hi = vec3(1.00, 0.92, 0.55);
uniform float hue_shift = 0.0;    // 0..1 hue offset when color_by_frequency
uniform bool  draw_peaks = true;
uniform float peak_thickness = 0.015; // in UV 0..1

// small HSV->RGB helper
vec3 hsv2rgb(vec3 c){
    vec4 K = vec4(1., 2./3., 1./3., 3.);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6. - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0., 1.), c.y);
}

void fragment(){
    vec2 uv = UV;
    float u = clamp(uv.x, 0.0, 1.0);
    float v = 1.0 - clamp(uv.y, 0.0, 1.0); // bottom = 0

    float fb = float(bar_count);
    float idx_f = floor(u * fb);
    float bar_u = fract(u * fb);

    // sample this bar's height + peak from the tiny texture
    float tx = (idx_f + 0.5) / fb;
    vec2 hp = texture(spectrum_tex, vec2(tx, 0.5)).rg;
    float h    = clamp(pow(hp.r, gamma), 0.0, 1.0);
    float peak = clamp(hp.g, 0.0, 1.0);

    // anti-aliased bar mask with a configurable gap
    float edge = clamp(gap * 0.5, 0.0, 0.45);
    float aa   = fwidth(bar_u) * 1.25;
    float mask_x = smoothstep(0.0, aa, bar_u - edge) * smoothstep(0.0, aa, (1.0 - edge) - bar_u);
    float mask_y = smoothstep(0.0, fwidth(v) * 1.25, h - v);
    float bar_mask = mask_x * mask_y;

    // optional white peak line
    float peak_mask = 0.0;
    if (draw_peaks) {
        float d = abs(v - peak);
        peak_mask = smoothstep(peak_thickness, 0.0, d) * mask_x;
    }

    // color
    float f = idx_f / max(fb - 1.0, 1.0);
    vec3 base = mix(color_lo, color_hi, h);
    if (color_by_frequency) {
        vec3 freq_rgb = hsv2rgb(vec3(fract(f + hue_shift), 1.0, 1.0));
        base = mix(base, freq_rgb, 0.8);
    }

    vec3 col = base * bar_mask + vec3(1.0) * peak_mask;
    COLOR = vec4(col, bar_mask + peak_mask); // premult not needed here
}
