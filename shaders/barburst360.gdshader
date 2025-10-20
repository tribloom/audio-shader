shader_type canvas_item;
render_mode unshaded;

uniform bool audio_enabled = false;
uniform sampler2D spectrum_tex;
uniform int bar_count = 64;
uniform float audio_gain = 3.0;
uniform float aspect = 1.0;
uniform float inner_radius = 0.18;
uniform float bar_len = 0.55;
uniform float blur = 0.012;

float bar_at_index(int i){
    if (bar_count <= 0) return 0.0;
    int idx = clamp(i, 0, bar_count-1);
    float u = (float(idx) + 0.5) / float(bar_count);
    return texture(spectrum_tex, vec2(u, 0.5)).r * audio_gain;
}

vec2 norm_uv(vec2 uv){ vec2 p = uv*2.0 - 1.0; p.x *= aspect; return p; }

void fragment(){
    vec2 p = norm_uv(UV);
    float ang = atan(p.y, p.x);
    float a = (ang + 3.14159265) / (2.0*3.14159265); // 0..1
    int i = int(floor(a * float(bar_count)));
    float v = audio_enabled ? clamp(bar_at_index(i), 0.0, 1.5) : 0.25;

    float r = length(p);
    float r0 = inner_radius;
    float r1 = inner_radius + bar_len * (0.15 + 0.85 * v);

    float body = smoothstep(blur, 0.0, abs(r - clamp(r, r0, r1)));
    float head = smoothstep(0.02, 0.0, abs(r - r1));
    float val = max(body*0.6, head);

    // subtle rotational shimmer from highs
    int n_hi = max(1, min(12, bar_count));
    float hi = 0.0; int start = max(0, bar_count-n_hi);
    for (int k=0;k<n_hi;k++) hi += bar_at_index(start+k);
    hi /= float(n_hi);
    float rim = smoothstep(0.01, 0.0, abs(r - (inner_radius + bar_len)) )*hi;

    vec3 col = mix(vec3(0.02), vec3(1.0, 0.95, 0.6), val) + vec3(0.2,0.4,1.0)*rim;
    COLOR = vec4(col, 1.0);
}
