shader_type canvas_item;

// Ring-buffered waterfall of spectra
uniform sampler2D waterfall_tex; // width = bar_count, height = rows, FORMAT_R8
uniform int bar_count = 64;
uniform int rows = 256;
uniform float head_norm = 0.0;   // head_row / rows
uniform float aspect = 1.7777;

// Visual controls
uniform float gain = 1.0;        // post gain before gamma
uniform float gamma = 0.9;       // visual shaping
uniform float age_fade = 0.25;   // 0..1 fade older rows
uniform bool  colorize = true;   // false = grayscale

vec3 heat(float m){
    // simple 4-stop gradient: blue -> cyan -> yellow -> white
    m = clamp(m, 0.0, 1.0);
    if (m < 0.3333) {
        float t = m / 0.3333;
        return mix(vec3(0.00, 0.00, 0.20), vec3(0.00, 0.70, 1.00), t);
    } else if (m < 0.6666) {
        float t = (m - 0.3333) / 0.3333;
        return mix(vec3(0.00, 0.70, 1.00), vec3(1.00, 1.00, 0.00), t);
    } else {
        float t = (m - 0.6666) / 0.3334;
        return mix(vec3(1.00, 1.00, 0.00), vec3(1.00, 1.00, 1.00), t);
    }
}

void fragment(){
    vec2 uv = UV;
    float u = clamp(uv.x, 0.0, 1.0);
    float v = clamp(uv.y, 0.0, 1.0); // top=0, bottom=1 in canvas UV

    float rf = float(rows);
    float fb = float(bar_count);

    // We want newest at the bottom.
    float age = 1.0 - v;             // 0 at bottom (new), 1 at top (old)
    float head = head_norm * rf;     // 0..rows
    float offset = age * (rf - 1.0);
    float sample_row = mod(head - offset + rf, rf);
    float ty = (floor(sample_row) + 0.5) / rf;

    float tx = (clamp(u, 0.0, 1.0) * (fb - 1.0) + 0.5) / fb;
    float m = texture(waterfall_tex, vec2(tx, ty)).r;

    // Gain + gamma
    float mag = pow(clamp(m * gain, 0.0, 1.0), gamma);

    // Colorize or grayscale
    vec3 col = colorize ? heat(mag) : vec3(mag);

    // Fade by age
    col *= (1.0 - age_fade * age);

    COLOR = vec4(col, 1.0);
}
