shader_type canvas_item;
render_mode unshaded, blend_mix;

const float ZUCCONI_OFFSET = 1.05;
const float SHAPE_SIZE = 0.618;
const float CHROMATIC_ABBERATION = 0.02;
const int ITERATIONS = 7;
const float INITIAL_LUMA = 0.6;

uniform sampler2D buffer_a_tex : filter_linear;
uniform vec2 buffer_a_size = vec2(1920.0, 1080.0);

float saturate(float x) {
        return clamp(x, 0.0, 1.0);
}

vec3 saturate(vec3 x) {
        return clamp(x, vec3(0.0), vec3(1.0));
}

vec3 bump3y(vec3 x, vec3 yoffset) {
        vec3 y = vec3(1.0) - x * x;
        y = saturate(y - yoffset);
        return y;
}

vec3 spectral_zucconi6(float x) {
        const vec3 c1 = vec3(3.54585104, 2.93225262, 2.41593945);
        const vec3 x1 = vec3(0.69549072, 0.49228336, 0.27699880);
        const vec3 y1 = vec3(0.02312639, 0.15225084, 0.52607955);

        const vec3 c2 = vec3(3.90307140, 3.21182957, 3.96587128);
        const vec3 x2 = vec3(0.11748627, 0.86755042, 0.66077860);
        const vec3 y2 = vec3(0.84897130, 0.88445281, 0.73949448);

        return bump3y(c1 * (x - x1), y1) + bump3y(c2 * (x - x2), y2);
}

mat2 rotate2d(float angle) {
        float s = sin(angle);
        float c = cos(angle);
        return mat2(c, -s, s, c);
}

float get_color_component(vec2 st, float mod_scale, float blur) {
        vec2 mod_st = mod(st, 1.0 / mod_scale) * mod_scale * 2.0 - 1.0;
        float dist = length(mod_st);
        float shape_map = smoothstep(SHAPE_SIZE + blur, SHAPE_SIZE - blur, sin(dist * 3.0) * 0.5 + 0.5);
        return shape_map;
}

void fragment() {
        vec2 resolution = buffer_a_size;
        if (resolution.x <= 0.0 || resolution.y <= 0.0) {
                resolution = vec2(texture_size(buffer_a_tex, 0));
        }
        vec2 frag_coord = UV * resolution;
        vec2 uv = frag_coord / resolution;
        vec4 feedback = texture(buffer_a_tex, uv);
        float blur = 0.4 + sin(TIME * 0.52) * 0.2;

        vec2 st = (2.0 * frag_coord - resolution) / min(resolution.x, resolution.y);
        vec2 orig_st = st;

        st -= (feedback.r + feedback.g + feedback.b) * st * 0.3;

        st *= rotate2d(sin(TIME * 0.14) * 0.3);
        st *= (sin(TIME * 0.15) + 2.0) * 0.3;

        float safe_len = max(length(st * 0.428), 1e-4);
        st *= log(safe_len) * 1.3;

        float mod_scale = 1.0;
        vec3 color = vec3(0.0);
        float luma = INITIAL_LUMA;

        for (int i = 0; i < ITERATIONS; i++) {
                vec2 center = st + vec2(sin(TIME * 0.12), cos(TIME * 0.13)) * 1.5;
                vec3 shape_color = vec3(
                        get_color_component(center - st * CHROMATIC_ABBERATION, mod_scale, blur),
                        get_color_component(center, mod_scale, blur),
                        get_color_component(center + st * CHROMATIC_ABBERATION, mod_scale, blur)
                ) * luma;

                st *= 1.1 + get_color_component(center, mod_scale, 0.04) * 1.2;
                st *= rotate2d(sin(TIME * 0.05) * 1.33);
                color += shape_color;
                color = saturate(color);
                luma *= 0.6;
                blur *= 0.63;
        }

        float orig_dist = length(orig_st);
        float zucconi_domain = ZUCCONI_OFFSET - orig_dist;
        vec3 audio_color = spectral_zucconi6(zucconi_domain) * feedback.a * 0.4;
        color *= feedback.rgb;
        color += audio_color;

        COLOR = vec4(color, 1.0);
}
