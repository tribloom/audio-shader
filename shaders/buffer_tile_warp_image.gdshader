shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D buffer_a_tex : filter_linear;
uniform vec2 buffer_a_size = vec2(1920.0, 1080.0);
uniform float normal_texel = 1.0;

void fragment() {
        vec2 resolution = buffer_a_size;
        if (resolution.x <= 0.0 || resolution.y <= 0.0) {
                resolution = vec2(textureSize(buffer_a_tex, 0));
        }

        vec2 uv = UV;
        vec4 buffer_sample = texture(buffer_a_tex, uv);
        float base = buffer_sample.r;
        vec4 color = vec4(base, base, base, base);

        vec2 texel = normal_texel / resolution;
        vec2 uv_dx = clamp(uv + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0));
        vec2 uv_dy = clamp(uv + vec2(0.0, texel.y), vec2(0.0), vec2(1.0));
        float sample_dx = texture(buffer_a_tex, uv_dx).r - base;
        float sample_dy = texture(buffer_a_tex, uv_dy).r - base;
        vec3 normal = normalize(vec3(sample_dx, sample_dy, 1.0));

        vec4 wave = sin(color * vec4(1.0, 2.0, 3.0 * sin(TIME), 4.0));
        float lighting = dot(normal, vec3(0.0, 1.0, 0.0)) + 1.0;

        COLOR = vec4(wave.rgb * lighting, 1.0);
}