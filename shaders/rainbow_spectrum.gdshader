shader_type canvas_item;

/* Your uniforms */
uniform bool enable_audio = true;
uniform float aspect = 1.7778;      // not used here
uniform sampler2D spectrum_tex;
uniform sampler2D waveform_tex;     // unused
uniform float level = 0.0;
uniform float kick = 0.0;
uniform float audio_gain = 1.0;

/* Use screen-space UVs by default to avoid flat color when mesh UVs are constant */
uniform bool use_screen_uv = true;

float bump(float x) {
    return abs(x) > 1.0 ? 0.0 : 1.0 - x * x;
}

float sample_spectrum(float x01){
    return texture(spectrum_tex, vec2(clamp(x01, 0.0, 1.0), 0.5)).r * audio_gain;
}

void fragment() {
    // Get 0..1 coords: screen-space by default (works on ColorRect/TextureRect/etc.)
    vec2 uv = use_screen_uv ? SCREEN_UV : UV;

    // RGB bumps along X
    float c = 3.0;
    vec3 color = vec3(1.0);
    color.r = bump(c * (uv.x - 0.75));
    color.g = bump(c * (uv.x - 0.50));
    color.b = bump(c * (uv.x - 0.25));

    // Line emphasis around y = 0.5
    float dy   = abs(0.5 - uv.y);
    float line = 0.01 / max(dy, 1e-4);

    // Spectrum-driven energy (Shadertoy used a 2D history; we use spectrum X)
    float x_sample   = clamp(abs(0.5 - uv.x) + 0.005, 0.0, 1.0);
    float spec       = enable_audio ? sample_spectrum(x_sample) : 0.0;

    // Shaping (keep lively but safe)
    float audio_boost = pow(spec, 3.0) * 10.0 + level * 0.5;

    float base = 1.0 - 2.0 * abs(0.5 - uv.x);   // 0..1 across X
    float modv = line * (base + audio_boost);

    color *= modv;

    COLOR = vec4(clamp(color, 0.0, 3.0), 1.0);
}
