shader_type canvas_item;
render_mode unshaded, blend_mix;

/* === Your pipeline uniforms === */
uniform sampler2D buffer_a_tex : hint_default_black; // read the updated buffer
uniform vec2      buffer_a_size = vec2(1920.0, 1080.0);

/* === Finishing controls (image/stylist) === */
uniform float img_tone_contrast : hint_range(0.5, 1.8) = 1.10;
uniform float img_sat           : hint_range(0.0, 2.0) = 1.15;
uniform float img_bloom_strength: hint_range(0.0, 1.0) = 0.35;
uniform float img_white_clip    : hint_range(0.8, 1.2) = 1.00;
uniform float img_edge_sharpen  : hint_range(0.0, 1.0) = 0.25;

float luma(vec3 c){ return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 adjust_contrast(vec3 c, float k){
    return clamp((c - 0.5) * k + 0.5, 0.0, 1.0);
}

vec3 adjust_saturation(vec3 c, float s){
    float y = luma(c);
    return clamp(mix(vec3(y), c, s), 0.0, 1.0);
}

vec3 soft_clip(vec3 c, float white_clip){
    vec3 x = c / max(white_clip, 1e-3);
    return clamp(x / (1.0 + x), 0.0, 1.0);
}

void fragment(){
    vec2 uv = UV;
    vec2 texel = 1.0 / max(buffer_a_size, vec2(1.0));

    vec3 base = texture(buffer_a_tex, uv).rgb;

    // Tiny blur for bloom/unsharp
    vec3 b0 = texture(buffer_a_tex, uv + vec2(0.0, -texel.y)).rgb;
    vec3 b1 = texture(buffer_a_tex, uv + vec2(0.0,  texel.y)).rgb;
    vec3 b2 = texture(buffer_a_tex, uv + vec2( texel.x, 0.0)).rgb;
    vec3 b3 = texture(buffer_a_tex, uv + vec2(-texel.x, 0.0)).rgb;
    vec3 blur4 = (b0 + b1 + b2 + b3) * 0.25;

    // Unsharp
    vec3 detail = base - blur4;
    vec3 sharpened = clamp(base + img_edge_sharpen * detail, 0.0, 1.0);

    // Bloom
    vec3 bloomed = clamp(sharpened + img_bloom_strength * blur4, 0.0, 1.0);

    // Grade
    vec3 graded = adjust_contrast(bloomed, img_tone_contrast);
    graded = adjust_saturation(graded, img_sat);
    graded = soft_clip(graded, img_white_clip);

    COLOR = vec4(graded, 1.0);
}
