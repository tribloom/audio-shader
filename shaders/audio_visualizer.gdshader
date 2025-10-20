shader_type canvas_item;

/* ---- Inputs ---- */
uniform sampler2D spectrum_tex : hint_default_black; // 1×N “spectrum”/wave texture
uniform float aspect = 1.7777778;                     // set from GDScript (e.g., 16.0/9.0)
uniform float sample_scale = 1.0;                     // optional scaling for the sample domain

/* ---- Helpers ---- */
float sigmoid_f(float x) {
    return 1.0 / (1.0 + exp(x));
}

vec3 sigmoid_v(vec3 xyz) {
    return vec3(sigmoid_f(xyz.x), sigmoid_f(xyz.y), sigmoid_f(xyz.z));
}

float sample_at(float f) {
    // Original shadertoy used iChannel0 at (f/16, 0).
    // Keep the same mapping; provide sample_scale to adjust if needed.
    return texture(spectrum_tex, vec2((f * sample_scale) / 16.0, 0.0)).x;
}

float sample_multiple(float f) {
    float delta = 0.1;
    return 0.2 * (
        sample_at(f - 2.0 * delta) +
        sample_at(f - 1.0 * delta) +
        sample_at(f) +
        sample_at(f + 1.0 * delta) +
        sample_at(f + 2.0 * delta)
    );
}

/* ---- Fragment ---- */
void fragment() {
    // Map to [-1, 1] with correct orientation (right side up for Godot 4)
    vec2 uv = (UV - 0.5) * 2.0;
    uv.y = -uv.y;            // flip so it’s not upside down vs. Shadertoy
    //uv.x *= aspect;          // preserve aspect
	    if (aspect >= 1.0) {
        uv.x *= aspect;      // landscape: stretch X so radius stays circular
    } else {
        uv.y /= aspect;      // portrait: compress Y to balance composition
    }

    vec2 center = vec2(0.0);
    float d = length(uv - center);

    float amplitude = sample_multiple(d * d);
    d -= amplitude;

    float weird = sigmoid_f(abs(uv.x) * abs(uv.y));
    float speed = 6.0 * amplitude * sin(TIME * weird * 0.005) * 0.001;

    float dist_diagonal = abs(abs(uv.x) - abs(uv.y));
    dist_diagonal += d * amplitude;
    dist_diagonal *= dist_diagonal;

    amplitude += 0.1 / (0.1 + smoothstep(1.0, 0.1, dist_diagonal));
    float brightness = 3.0 * amplitude *
        sigmoid_f(sin(d * d * 16.0 - speed * TIME + 2.0 * speed * amplitude));

    vec3 col = sigmoid_v(vec3(uv, sin(TIME)));

    COLOR = vec4(col * brightness, 1.0);
}
